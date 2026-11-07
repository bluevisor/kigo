// Vendored from SaddleIsland/Packages/IslandKit — keep in sync.
// The client's socket engine: everything that runs on IslandClient's IO queue.
import Darwin
import Foundation
import Synchronization

// MARK: - Engine (IO queue only)

extension IslandClient {
    /// All socket state. Every member is touched only on `queue`.
    nonisolated final class Engine: @unchecked Sendable {
        let queue = DispatchQueue(label: "IslandKit.client", qos: .userInitiated)
        private let hello: Hello
        private let path: String
        private let shared: Shared

        private var activated = false
        private var socket: SocketHandle?
        private var readSource: DispatchSourceRead?
        private var writeSource: DispatchSourceWrite?
        private var timer: DispatchSourceTimer?
        private var readyObserver: ReadyObserver?

        private var readBuffer = Data()
        private(set) var outbox = IslandOutbox()
        /// The encoded frame being written. A partial write keeps its tail here: never cut a line.
        private var inFlight = Data()
        private var seq: UInt64 = 0
        /// Written frames Saddle Island hasn't answered yet, oldest first.
        private var unacked: [(seq: UInt64, at: UInt64)] = []
        /// The first frame written after Saddle Island was quiet for `heardWithin` (nothing is sent while
        /// nothing is live). Until Saddle Island answers it, nothing recent proves its main thread is alive.
        private var proof: (seq: UInt64, at: UInt64)?

        private var accepted = false
        private var presentedByServer = true
        private var congested = false
        private var lastHeard: UInt64 = 0
        private var lastSent: UInt64 = 0
        private var lastAttempt: UInt64 = 0
        private var nextAttempt: UInt64 = 0
        private var backoff = Timing.reconnect.islandKitNanos

        private struct Live { var content: ActivityContent; var options: ActivityOptions? }
        private var live: [String: Live] = [:]
        /// The app's panel (`IslandPanel`), sent again on every accepted connection.
        private var panel: IslandPanel?
        private var liveOrder: [String] = []
        /// Activities the user swiped away in Saddle Island: they stay hidden there until they end, so
        /// updates for them are dropped here instead of restarting them without their options.
        private var dismissed: Set<String> = []
        private var published = Status()

        init(hello: Hello, path: String, shared: Shared) {
            self.hello = hello
            self.path = path
            self.shared = shared
        }

        // MARK: Lifecycle

        func activate() {
            guard !activated else { return }
            activated = true
            let timer = DispatchSource.makeTimerSource(queue: queue)
            timer.setEventHandler { [weak self] in self?.tick() }
            timer.schedule(deadline: .distantFuture)
            timer.resume()
            self.timer = timer
            readyObserver = ReadyObserver { [weak self] in
                guard let self else { return }
                queue.async { self.saddleIslandBecameReady() }
            }
            connect()
        }

        func invalidate() {
            guard activated else { return }
            activated = false
            disconnect(retry: false)
            timer?.cancel()
            timer = nil
            readyObserver?.unregister()
            readyObserver = nil
            live.removeAll()
            liveOrder.removeAll()
            dismissed.removeAll()
            update()
        }

        private func saddleIslandBecameReady() {
            guard activated, socket == nil else { return }
            backoff = Timing.reconnect.islandKitNanos
            connect()
        }

        private func connect() {
            guard activated, socket == nil else { return }
            lastAttempt = IslandKit.now()
            switch UnixSocket.connect(path: path) {
            case .success(let fd):
                var size = IslandClient.sendBufferBytes
                setsockopt(fd, SOL_SOCKET, SO_SNDBUF, &size, socklen_t(MemoryLayout<Int32>.size))
                let socket = SocketHandle(fd)
                self.socket = socket
                readSource = Self.makeReadSource(socket: socket, queue: queue) { [weak self] data, closed in
                    self?.received(data, closed: closed)
                }
                backoff = Timing.reconnect.islandKitNanos
                accepted = false
                presentedByServer = true
                lastHeard = 0
                readBuffer.removeAll()
                outbox.removeAll()
                inFlight.removeAll()
                unacked.removeAll()
                proof = nil
                enqueue(.hello(hello))
            case .failure:
                scheduleRetry()
            }
            update()
        }

        /// Built outside any actor context so the handler never inherits an isolation it can't
        /// satisfy on `queue` (a MainActor-formed handler traps when it fires there).
        private static func makeReadSource(
            socket: SocketHandle, queue: DispatchQueue, onRead: @escaping @Sendable (Data, Bool) -> Void
        ) -> DispatchSourceRead {
            let source = DispatchSource.makeReadSource(fileDescriptor: socket.fd, queue: queue)
            source.setEventHandler {
                var data = Data()
                var chunk = [UInt8](repeating: 0, count: 16 * 1024)
                var closed = false
                while true {
                    let n = read(socket.fd, &chunk, chunk.count)
                    if n > 0 {
                        data.append(chunk, count: n)
                        if data.count > 4 * IslandKit.maxFrameBytes { break }
                        continue
                    }
                    if n == 0 || (errno != EAGAIN && errno != EINTR) { closed = true }
                    break
                }
                onRead(data, closed)
            }
            // The fd closes when the last source holding `socket` lets go of its handlers.
            source.setCancelHandler { _ = socket }
            source.resume()
            return source
        }

        private func disconnect(retry: Bool) {
            guard socket != nil else { return }
            readSource?.cancel()
            readSource = nil
            writeSource?.cancel()
            writeSource = nil
            socket = nil
            accepted = false
            congested = false
            outbox.removeAll()
            inFlight.removeAll()
            unacked.removeAll()
            proof = nil
            readBuffer.removeAll()
            // A new connection starts clean: Saddle Island ended everything the old one had.
            dismissed.removeAll()
            if retry { scheduleRetry() }
            update()
        }

        private func scheduleRetry() {
            guard activated else { return }
            // Stay at 2 s while the caller has something to show; back off when idle (Saddle Island's
            // ready notification reconnects at once anyway).
            if !live.isEmpty { backoff = Timing.reconnect.islandKitNanos }
            nextAttempt = IslandKit.now() &+ backoff
            if live.isEmpty { backoff = min(backoff * 2, Timing.maxIdleReconnect.islandKitNanos) }
        }

        // MARK: Activities

        /// An explicit `start` is sent even for a dismissed id (Saddle Island keeps it hidden until it ends);
        /// its updates flow again so the content is current if it shows after a reconnect.
        func start(id: String, content: ActivityContent, options: ActivityOptions?) {
            dismissed.remove(id)
            let content = content.finite
            let options = options.map(\.finite)
            if !activated { activate() }
            if live[id] == nil { liveOrder.append(id) }
            live[id] = Live(content: content, options: options)
            if accepted {
                enqueue(.start(id: id, content: content, options: options))
            } else if socket == nil, IslandKit.now() &- lastAttempt > 250_000_000 {
                connect() // something to show: don't wait for the retry timer
            }
            update()
        }

        func update(id: String, content: ActivityContent) {
            guard !dismissed.contains(id) else { return }
            let content = content.finite
            guard let current = live[id] else { return start(id: id, content: content, options: nil) }
            guard current.content != content else { return }
            live[id]?.content = content
            if accepted { enqueue(.update(id: id, content: content)) }
        }

        func end(id: String, dismissAfter: Double?) {
            dismissed.remove(id)
            if live.removeValue(forKey: id) != nil { liveOrder.removeAll { $0 == id } }
            if accepted { enqueue(.end(id: id, dismissAfter: dismissAfter.flatMap { $0.isFinite ? $0 : nil })) }
            update()
        }

        private func resendLive() {
            for id in liveOrder {
                guard let entry = live[id] else { continue }
                enqueue(.start(id: id, content: entry.content, options: entry.options))
            }
            if let panel { enqueue(.panel(panel)) }
        }

        /// Publishes (or with nil withdraws) the app's panel; unchanged content isn't re-sent.
        func setPanel(_ new: IslandPanel?) {
            let new = new?.trimmed
            guard new != panel else { return }
            panel = new
            if !activated { activate() }
            if accepted { enqueue(.panel(new)) }
            update()
        }

        // MARK: Reading

        private func received(_ data: Data, closed: Bool) {
            readBuffer.append(data)
            if readBuffer.count > IslandKit.maxFrameBytes, !readBuffer.contains(0x0A) {
                return disconnect(retry: true) // not a Saddle Island we understand
            }
            let frames = NDJSON.drain(&readBuffer, as: ServerMessage.self).compactMap { try? $0.get() }
            if !frames.isEmpty { lastHeard = IslandKit.now() }
            for frame in frames { handle(frame) }
            if closed { disconnect(retry: true) } else { update() }
        }

        private func handle(_ frame: Frame<ServerMessage>) {
            switch frame.message {
            case .welcome(let welcome):
                answered(upTo: frame.seq, roundTrip: false)
                setAccepted(welcome.accepted && welcome.v == IslandKit.protocolVersion)
            case .policy(let accepted):
                setAccepted(accepted)
            case .ack(let seq, let presented):
                answered(upTo: seq, roundTrip: true)
                presentedByServer = presented
            case .pong(let seq):
                answered(upTo: seq, roundTrip: true)
            case .action(let id, let action):
                shared.deliver { $0.onAction?(id, action) }
            case .panelAction(let row, let value):
                shared.deliver { $0.onPanelAction?(row, value) }
            case .dismissed(let id):
                if live.removeValue(forKey: id) != nil { liveOrder.removeAll { $0 == id } }
                dismissed.insert(id)
                shared.deliver { $0.onDismissed?(id) }
            }
        }

        private func setAccepted(_ value: Bool) {
            let was = accepted
            accepted = value
            if value, !was { resendLive() }
        }

        private func answered(upTo seq: UInt64, roundTrip: Bool) {
            let now = IslandKit.now()
            var latest: UInt64?
            while let first = unacked.first, first.seq <= seq {
                latest = first.at
                unacked.removeFirst()
            }
            if let proof, proof.seq <= seq { self.proof = nil }
            if roundTrip, let latest, shared.handlers.withLock({ $0.onRoundTrip != nil }) {
                let rtt = now &- latest
                shared.deliver { $0.onRoundTrip?(rtt) }
            }
        }

        // MARK: Writing

        private func enqueue(_ message: ClientMessage) {
            guard socket != nil else { return }
            outbox.enqueue(message)
            flush()
        }

        private func flush() {
            while let socket {
                if inFlight.isEmpty {
                    guard let message = outbox.popFirst() else { break }
                    seq += 1
                    guard let data = try? NDJSON.encode(Frame(seq: seq, message: message)) else { continue }
                    inFlight = data
                    let now = IslandKit.now()
                    lastSent = now
                    // Keeping the oldest entries keeps "unanswered for 600 ms" detectable.
                    if unacked.count < 4096 { unacked.append((seq, now)) }
                    if proof == nil, now &- lastHeard >= Timing.heardWithin.islandKitNanos { proof = (seq, now) }
                }
                switch UnixSocket.write(socket.fd, inFlight) {
                case .ok:
                    inFlight.removeAll()
                case .wouldBlock(let written):
                    inFlight = Data(inFlight.dropFirst(written))
                    congested = true
                    armWriteSource(socket)
                    return update()
                case .failed:
                    return disconnect(retry: true) // EPIPE etc.: SO_NOSIGPIPE means no signal
                }
            }
            if congested {
                congested = false
                writeSource?.cancel()
                writeSource = nil
            }
            update()
        }

        private func armWriteSource(_ socket: SocketHandle) {
            guard writeSource == nil else { return }
            let source = DispatchSource.makeWriteSource(fileDescriptor: socket.fd, queue: queue)
            source.setEventHandler { [weak self] in self?.flush() }
            source.setCancelHandler { _ = socket }
            writeSource = source
            source.resume()
        }

        // MARK: Timer: pings, presenting deadlines, reconnects

        private func tick() {
            let now = IslandKit.now()
            if socket == nil {
                if activated, now >= nextAttempt { connect() }
            } else if accepted, let interval = pingInterval, now &- lastSent >= interval {
                enqueue(.ping)
            }
            update()
        }

        /// Saddle Island's `staleAfter` default and floor (docs/IslandKit.md, `options`).
        private static let defaultStaleAfter = 3.0
        private static let minStaleAfter = 0.5

        /// How long the client may go without sending a frame before it pings. nil while nothing is
        /// live: then nothing is sent at all (EOF and the ready notification cover a Saddle Island that
        /// quits or relaunches, and `proof` one that hung meanwhile). While a microphone is live
        /// (iSay's dictation) a hang must show within a second: `livePing`. Otherwise a third of the
        /// shortest `staleAfter`, so the activity isn't swept, and at least every `maxLivePing` to
        /// keep `heardWithin` true.
        var pingInterval: UInt64? {
            guard !live.isEmpty else { return nil }
            var interval = Timing.maxLivePing.islandKitNanos
            for entry in live.values {
                if entry.options?.priority == .critical || entry.content.levels != nil {
                    return Timing.livePing.islandKitNanos
                }
                let staleAfter = max(entry.options?.staleAfter ?? Self.defaultStaleAfter, Self.minStaleAfter)
                interval = min(interval, UInt64(staleAfter / 3 * 1e9))
            }
            return interval
        }

        /// Recomputes the published status and the next timer deadline.
        private func update() {
            let now = IslandKit.now()
            let oldestUnacked = unacked.first?.at
            // While something is live, pings keep Saddle Island's answers coming: it must have spoken
            // within `heardWithin`. While nothing is live nothing is sent, so its last word stands
            // until the next frame, and that one must be answered within `firstAckWithin`. It can't
            // turn presenting on before then, nor (answered in time, as it is in under a
            // millisecond) flicker it off, which would flash a caller's own UI at every start.
            let vouched = if let proof {
                published.isPresenting && now &- proof.at < Timing.firstAckWithin.islandKitNanos
            } else {
                live.isEmpty || now &- lastHeard < Timing.heardWithin.islandKitNanos
            }
            let presenting = socket != nil && accepted && presentedByServer && !congested && vouched
                && (oldestUnacked.map { now &- $0 < Timing.ackWithin.islandKitNanos } ?? true)
            let state: State = socket == nil ? .disconnected : (lastHeard == 0 ? .connecting : .connected(accepted: accepted))
            publish(Status(state: state, isPresenting: presenting, isCongested: congested))

            var next = UInt64.max
            if socket != nil, accepted, let interval = pingInterval { next = min(next, lastSent &+ interval) }
            if presenting {
                if let proof {
                    next = min(next, proof.at &+ Timing.firstAckWithin.islandKitNanos)
                } else if !live.isEmpty {
                    next = min(next, lastHeard &+ Timing.heardWithin.islandKitNanos)
                }
                if let oldestUnacked { next = min(next, oldestUnacked &+ Timing.ackWithin.islandKitNanos) }
            }
            if socket == nil, activated { next = min(next, nextAttempt) }
            guard let timer else { return }
            if next == .max {
                timer.schedule(deadline: .distantFuture)
            } else {
                let delay = next > now ? next - now : 0
                timer.schedule(deadline: .now() + .nanoseconds(Int(min(delay, UInt64(Int.max)))),
                               leeway: .milliseconds(5))
            }
        }

        private func publish(_ status: Status) {
            guard status != published else { return }
            let old = published
            published = status
            shared.status.withLock { $0 = status }
            if status.state != old.state {
                let state = status.state
                shared.deliver { $0.onStateChange?(state) }
            }
            if status.isPresenting != old.isPresenting {
                let presenting = status.isPresenting
                shared.deliver { $0.onPresentingChanged?(presenting) }
            }
        }
    }
}

// MARK: - Helpers

extension IslandClient {
    /// Owns a socket fd; closes it when the last reference (engine or a dispatch source handler)
    /// goes, so the fd is never closed while a source still watches it.
    nonisolated final class SocketHandle: Sendable {
        let fd: Int32
        init(_ fd: Int32) { self.fd = fd }
        deinit { close(fd) }
    }
}

/// Saddle Island's "listener is up" broadcast. `.deliverImmediately`: a background app's distributed
/// notifications are otherwise suspended, and coalesced ones are lost.
nonisolated private final class ReadyObserver: NSObject, @unchecked Sendable {
    private let handler: @Sendable () -> Void

    init(handler: @escaping @Sendable () -> Void) {
        self.handler = handler
        super.init()
        // Delivery needs a running run loop; the main thread has one in any app.
        DispatchQueue.main.async { [self] in
            DistributedNotificationCenter.default().addObserver(
                self, selector: #selector(ready(_:)), name: IslandKit.readyNotification, object: nil,
                suspensionBehavior: .deliverImmediately)
        }
    }

    @objc private func ready(_ note: Notification) { handler() }

    func unregister() {
        DispatchQueue.main.async { [self] in DistributedNotificationCenter.default().removeObserver(self) }
    }
}

// JSONEncoder throws on NaN and infinity, which would silently drop the whole frame while the
// client still reported `isPresenting` (a NaN audio level is enough). Fix the numbers instead.
extension ActivityContent {
    nonisolated fileprivate var finite: ActivityContent {
        var c = self
        c.levels = c.levels?.map { $0.isNaN ? 0 : min(max($0, 0), 1) }
        c.progress = c.progress.map { ActivityProgress(value: $0.value.map { $0.isNaN ? 0 : min(max($0, 0), 1) }) }
        if let tint = c.tint, ![tint.r, tint.g, tint.b, tint.a].allSatisfy(\.isFinite) { c.tint = nil }
        // Saddle Island drops timers more than a year away (a JavaScript millisecond timestamp sent as seconds).
        if let timer = c.timer {
            let offset = timer.date.timeIntervalSinceNow
            if !offset.isFinite || abs(offset) > 366 * 24 * 3600 { c.timer = nil }
        }
        return c
    }
}

extension ActivityOptions {
    nonisolated fileprivate var finite: ActivityOptions {
        var o = self
        if let staleAfter = o.staleAfter, !staleAfter.isFinite { o.staleAfter = nil }
        return o
    }
}

extension Duration {
    /// Whole nanoseconds (named to stay clear of a host app's own extensions when vendored).
    nonisolated var islandKitNanos: UInt64 {
        let (seconds, attoseconds) = components
        return UInt64(max(0, seconds)) * 1_000_000_000 + UInt64(max(0, attoseconds) / 1_000_000_000)
    }
}
