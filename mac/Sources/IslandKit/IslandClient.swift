// Vendored from SaddleIsland/Packages/IslandKit — keep in sync.
// IslandKit client: posts live activities to Saddle Island.
// Vendorable: copy IslandKit.swift, IslandOutbox.swift, IslandClient.swift and
// IslandClientEngine.swift into a target with the default (nonisolated) actor isolation, as iSay's
// is. IslandKit.swift (the wire schema) isn't annotated, so in a target that defaults to MainActor
// isolation its types turn MainActor and the client doesn't compile (verified): depend on the
// package, or put the four files in a module of their own, instead.
import Darwin
import Foundation
import Synchronization

/// Posts live activities to Saddle Island over IslandKit (docs/IslandKit.md).
///
/// ```swift
/// let island = IslandClient(name: "Builder")
/// // Callbacks are @Sendable and run on `callbackQueue` (main by default), so MainActor state needs:
/// island.onPresentingChanged = { showing in MainActor.assumeIsolated { hud.isHidden = showing } }
/// island.onAction = { id, action in MainActor.assumeIsolated { if action == "stop" { build.cancel() } } }
/// island.activate()
/// island.start(id: "build", content: ActivityContent(title: "Building…", symbol: "hammer"))
/// ```
///
/// - Every method may be called from any thread and returns at once. Socket IO runs on one private
///   serial queue with non-blocking writes, so a hung or stopped Saddle Island never stalls the caller.
/// - Callbacks run on `callbackQueue` (main by default), in order.
/// - The client remembers the latest content of each live activity and re-sends it whenever
///   Saddle Island (re)accepts the connection, so a Saddle Island relaunch mid-activity needs no caller code.
nonisolated public final class IslandClient: Sendable {
    public enum State: Equatable, Sendable {
        /// Saddle Island isn't running or isn't listening. Show your own UI.
        case disconnected
        /// Connected, waiting for Saddle Island's `welcome`.
        case connecting
        /// `accepted` is false while the user has switched your app off in Saddle Island (or hasn't
        /// answered its consent prompt yet).
        case connected(accepted: Bool)
    }

    /// Thresholds behind `isPresenting` and the ping cadence. Nothing is sent, pings included,
    /// while no activity is live.
    public enum Timing {
        /// Retry delay after a failed connect or a dropped connection. Doubles up to
        /// `maxIdleReconnect` while nothing is live; Saddle Island's ready notification short-cuts it.
        public static let reconnect: Duration = .seconds(2)
        public static let maxIdleReconnect: Duration = .seconds(60)
        /// Ping cadence while a microphone is live: an activity started with `priority: .critical`,
        /// or whose content has `levels`. Pings go out only when nothing else was sent for this long.
        public static let livePing: Duration = .milliseconds(250)
        /// Ping cadence while anything else is live: a third of the shortest `staleAfter`, and at
        /// least this often.
        public static let maxLivePing: Duration = .seconds(1)
        /// While an activity is live, Saddle Island must have been heard from within this window.
        public static let heardWithin: Duration = .milliseconds(2500)
        /// The first frame sent after Saddle Island was quiet for `heardWithin` (the first one after an
        /// idle spell) must be answered within this; acks normally take well under a millisecond.
        public static let firstAckWithin: Duration = .milliseconds(150)
        /// No frame may wait longer than this for its ack (acks come from Saddle Island's main thread).
        public static let ackWithin: Duration = .milliseconds(600)
    }

    /// The socket's send buffer. The 8 KB default fills in under a second at 30 Hz.
    public static let sendBufferBytes: Int32 = 64 * 1024

    private let engine: Engine
    private let shared: Shared

    /// - Parameters:
    ///   - name: shown in Saddle Island's consent prompt and Settings when your app has no bundle name.
    ///   - bundleID: advisory only; Saddle Island identifies you by your code signature.
    ///   - socketPath: `IslandKit.socketPath` (or `ISLANDKIT_SOCKET`) unless testing.
    ///   - callbackQueue: where callbacks run.
    public init(
        name: String, bundleID: String? = Bundle.main.bundleIdentifier,
        socketPath: String = IslandKit.socketPath, callbackQueue: DispatchQueue = .main
    ) {
        shared = Shared(callbackQueue: callbackQueue)
        engine = Engine(hello: Hello(bundleID: bundleID, name: name), path: socketPath, shared: shared)
    }

    deinit {
        let engine = engine
        engine.queue.async { engine.invalidate() }
    }

    // MARK: Status

    /// True while Saddle Island is showing your activities: hide your own UI only while this is true.
    /// It requires a connection Saddle Island accepted, `presented` in Saddle Island's last ack, no frame
    /// unanswered for 600 ms, and a socket Saddle Island is draining. While an activity is live, Saddle Island
    /// must also have answered within the last 2.5 s (pings see to that). While nothing is live,
    /// nothing is sent and it says whether Saddle Island would show a new activity, going by its last
    /// word; the first frame after 2.5 s of quiet must then be answered within 150 ms, so a Saddle Island
    /// that hung meanwhile is caught at your next `start` without idle heartbeats.
    public var isPresenting: Bool { shared.status.withLock { $0.isPresenting } }
    public var state: State { shared.status.withLock { $0.state } }
    /// Saddle Island stopped draining the socket; queued updates are being coalesced.
    public var isCongested: Bool { shared.status.withLock { $0.isCongested } }

    // MARK: Callbacks

    /// The user pressed one of an activity's buttons: `(activityID, actionID)`.
    public var onAction: (@Sendable (_ activityID: String, _ action: String) -> Void)? {
        get { shared.handlers.withLock { $0.onAction } }
        set { shared.handlers.withLock { $0.onAction = newValue } }
    }
    /// The user used a row of your panel (`setPanel`): `(rowID, value)`. A toggle sends "true"/"false", a slider its
    /// number, a choice the option; `"@shown"` with no value means the panel just opened: refresh it if it's stale.
    public var onPanelAction: (@Sendable (_ row: String, _ value: String?) -> Void)? {
        get { shared.handlers.withLock { $0.onPanelAction } }
        set { shared.handlers.withLock { $0.onPanelAction = newValue } }
    }
    /// Search providers (a plugin with `searchProvider`, Kigo): the island's search field changed. Answer with
    /// `sendSearchResults` for `query.id`.
    public var onSearchQuery: (@Sendable (_ query: SearchProviderQuery) -> Void)? {
        get { shared.handlers.withLock { $0.onSearchQuery } }
        set { shared.handlers.withLock { $0.onSearchQuery = newValue } }
    }
    /// Search providers: the user picked one of your rows. Open it, then `sendSearchResults` with `close`, or
    /// new rows to keep the search open.
    public var onSearchPick: (@Sendable (_ pick: SearchProviderPick) -> Void)? {
        get { shared.handlers.withLock { $0.onSearchPick } }
        set { shared.handlers.withLock { $0.onSearchPick = newValue } }
    }
    /// Search providers that chose their own search UI (`setOwnSearchPanel(true)`): F4 was pressed. Open (or
    /// close) your own search.
    public var onShowSearch: (@Sendable () -> Void)? {
        get { shared.handlers.withLock { $0.onShowSearch } }
        set { shared.handlers.withLock { $0.onShowSearch = newValue } }
    }
    public var onPresentingChanged: (@Sendable (_ isPresenting: Bool) -> Void)? {
        get { shared.handlers.withLock { $0.onPresentingChanged } }
        set { shared.handlers.withLock { $0.onPresentingChanged = newValue } }
    }
    public var onStateChange: (@Sendable (State) -> Void)? {
        get { shared.handlers.withLock { $0.onStateChange } }
        set { shared.handlers.withLock { $0.onStateChange = newValue } }
    }
    /// The user hid an activity in Saddle Island. It stays hidden until it ends: later `update`s for it are
    /// dropped, so stop sending them, and `end` it (a `start` after that shows it anew).
    public var onDismissed: (@Sendable (_ activityID: String) -> Void)? {
        get { shared.handlers.withLock { $0.onDismissed } }
        set { shared.handlers.withLock { $0.onDismissed = newValue } }
    }
    /// Diagnostics: nanoseconds from writing a frame to reading Saddle Island's ack (or pong) for it.
    public var onRoundTrip: (@Sendable (_ nanoseconds: UInt64) -> Void)? {
        get { shared.handlers.withLock { $0.onRoundTrip } }
        set { shared.handlers.withLock { $0.onRoundTrip = newValue } }
    }

    // MARK: Lifecycle

    /// Connects now and keeps reconnecting until `invalidate()`. Idempotent. Set callbacks first.
    public func activate() {
        engine.queue.async { [engine] in engine.activate() }
    }

    /// Disconnects for good: activities end in Saddle Island at once (EOF).
    public func invalidate() {
        engine.queue.async { [engine] in engine.invalidate() }
    }

    // MARK: Activities

    /// Starts (or restarts) an activity. Activates the client if needed.
    public func start(id: String, content: ActivityContent, options: ActivityOptions? = nil) {
        engine.queue.async { [engine] in engine.start(id: id, content: content, options: options) }
    }

    /// Replaces an activity's content. Unchanged content is not re-sent; an unknown id starts it.
    public func update(id: String, content: ActivityContent) {
        engine.queue.async { [engine] in engine.update(id: id, content: content) }
    }

    /// Ends an activity, optionally leaving its final state up for `dismissAfter` seconds.
    public func end(id: String, dismissAfter: Double? = nil) {
        engine.queue.async { [engine] in engine.end(id: id, dismissAfter: dismissAfter) }
    }

    // MARK: Panel

    /// Your app's screen inside Saddle Island: a click on your tile in a bag turns the island into it, drawn in the
    /// island's style. Send it again whenever it changes (only changes go out); nil takes it away.
    public func setPanel(_ panel: IslandPanel?) {
        engine.queue.async { [engine] in engine.setPanel(panel) }
    }

    // MARK: Search provider

    /// Your rows for the island's search query `results.query` (best first), or `close` after a pick. Sent only
    /// while Saddle Island accepts you; an answer to an old query is ignored there.
    public func sendSearchResults(_ results: SearchProviderResults) {
        engine.queue.async { [engine] in engine.sendResults(results) }
    }

    /// Search providers: true to have F4 open your own search (`onShowSearch`) instead of the island's; false (the
    /// default) keeps the island's. Kept and sent again on every accepted connection.
    public func setOwnSearchPanel(_ own: Bool) {
        engine.queue.async { [engine] in engine.setOwnSearchPanel(own) }
    }

    /// Search providers: your own shortcut opens (or closes) the island's search, as F4 does. False when Saddle
    /// Island isn't connected and accepting you right now: show your own search instead.
    public func openSearch() -> Bool {
        engine.queue.sync { engine.openSearch() }
    }

    /// Test hook: runs `body` on the IO queue after everything queued so far.
    func sync<T: Sendable>(_ body: @Sendable (Engine) -> T) -> T {
        engine.queue.sync { body(engine) }
    }
}

// MARK: - Shared state (any thread)

extension IslandClient {
    nonisolated struct Status: Equatable, Sendable {
        var state: State = .disconnected
        var isPresenting = false
        var isCongested = false
    }

    nonisolated struct Handlers: Sendable {
        var onAction: (@Sendable (String, String) -> Void)?
        var onPanelAction: (@Sendable (String, String?) -> Void)?
        var onSearchQuery: (@Sendable (SearchProviderQuery) -> Void)?
        var onSearchPick: (@Sendable (SearchProviderPick) -> Void)?
        var onShowSearch: (@Sendable () -> Void)?
        var onPresentingChanged: (@Sendable (Bool) -> Void)?
        var onStateChange: (@Sendable (State) -> Void)?
        var onDismissed: (@Sendable (String) -> Void)?
        var onRoundTrip: (@Sendable (UInt64) -> Void)?
    }

    nonisolated final class Shared: Sendable {
        let status = Mutex(Status())
        let handlers = Mutex(Handlers())
        let callbackQueue: DispatchQueue

        init(callbackQueue: DispatchQueue) { self.callbackQueue = callbackQueue }

        /// Runs a handler on the callback queue, reading it at delivery time.
        func deliver(_ body: @escaping @Sendable (Handlers) -> Void) {
            callbackQueue.async { [self] in body(handlers.withLock { $0 }) }
        }
    }
}
