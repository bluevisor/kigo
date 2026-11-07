// Vendored from SaddleIsland/Packages/IslandKit — keep in sync.
// IslandKit wire schema v1 — shared by Saddle Island (server) and any posting app (client).
// Transport: AF_UNIX SOCK_STREAM, newline-delimited JSON (one object per line, UTF-8).
// Every frame is a flat JSON object: {"type": "...", "seq": N, "t": ns?, ...fields}.
import Foundation
import Darwin

public enum IslandKit {
    public static let protocolVersion = 1
    /// Longest accepted line; longer frames close the connection.
    public static let maxFrameBytes = 64 * 1024
    /// Saddle Island posts this (DistributedNotificationCenter, no payload) when its listener comes up
    /// or the user toggles a module, so clients reconnect without polling.
    public static let readyNotification = Notification.Name("com.bucaastudio.saddleisland.islandkit.ready")

    /// ~/Library/Application Support/Saddle Island/islandkit.sock, from the *real* home directory
    /// (getpwuid, not NSHomeDirectory, which is a container path for sandboxed callers).
    /// sun_path is 104 bytes on Darwin; this is 73 for /Users/johnzheng.
    public static var socketPath: String {
        if let override = ProcessInfo.processInfo.environment["ISLANDKIT_SOCKET"] { return override }
        let home = getpwuid(getuid()).map { String(cString: $0.pointee.pw_dir) } ?? NSHomeDirectory()
        return home + "/Library/Application Support/Saddle Island/islandkit.sock"
    }

    /// System-wide monotonic clock, comparable across processes (for latency diagnostics).
    public static func now() -> UInt64 { clock_gettime_nsec_np(CLOCK_UPTIME_RAW) }
}

// MARK: - Activity content

public struct RGBA: Codable, Sendable, Hashable {
    public var r: Double, g: Double, b: Double, a: Double
    public init(r: Double, g: Double, b: Double, a: Double = 1) { self.r = r; self.g = g; self.b = b; self.a = a }
}

public struct ActivityAction: Codable, Sendable, Hashable {
    public enum Role: String, Codable, Sendable { case normal, destructive, cancel }
    /// Echoed back in the `action` frame.
    public var id: String
    public var title: String
    public var symbol: String?
    public var role: Role?
    public init(id: String, title: String, symbol: String? = nil, role: Role? = nil) {
        self.id = id; self.title = title; self.symbol = symbol; self.role = role
    }
}

public struct ActivityProgress: Codable, Sendable, Hashable {
    /// 0...1; nil = indeterminate (Saddle Island draws its activity dots).
    public var value: Double?
    public init(value: Double? = nil) { self.value = value }
}

public struct ActivityTimer: Codable, Sendable, Hashable {
    public enum Direction: String, Codable, Sendable { case up, down }
    /// Seconds since 1970. `up` counts from it ("0:07"), `down` counts to it.
    public var date: Date
    public var direction: Direction
    public init(date: Date, direction: Direction = .up) { self.date = date; self.direction = direction }
}

/// Full state of one activity. Every `update` replaces the whole thing (idempotent, so a
/// dropped frame never leaves Saddle Island out of sync).
public struct ActivityContent: Codable, Sendable, Hashable {
    public var title: String?
    public var subtitle: String?
    /// SF Symbol name.
    public var symbol: String?
    public var tint: RGBA?
    public var progress: ActivityProgress?
    /// 0...1 loudness, oldest first; Saddle Island draws one bar per value (≤ 32).
    public var levels: [Float]?
    public var timer: ActivityTimer?
    /// Short trailing hint, e.g. the key that finishes hands-free dictation ("fn").
    public var trailing: String?
    /// ≤ 3 buttons; a click sends an `action` frame back to the poster.
    public var actions: [ActivityAction]?
    /// The words heard so far (iSay's dictation), shown as one line moving left in full views only: never in the ears
    /// or a sneak peek. Local to the socket; Saddle Island keeps the last 1000 characters.
    public var transcript: String?
    public init(title: String? = nil, subtitle: String? = nil, symbol: String? = nil, tint: RGBA? = nil,
                progress: ActivityProgress? = nil, levels: [Float]? = nil, timer: ActivityTimer? = nil,
                trailing: String? = nil, actions: [ActivityAction]? = nil, transcript: String? = nil) {
        self.title = title; self.subtitle = subtitle; self.symbol = symbol; self.tint = tint
        self.progress = progress; self.levels = levels; self.timer = timer; self.trailing = trailing
        self.actions = actions; self.transcript = transcript
    }
}

public struct ActivityOptions: Codable, Sendable, Hashable {
    public enum Priority: String, Codable, Sendable { case low, normal, high, critical }
    public var priority: Priority?
    /// Saddle Island ends the activity if no frame (update or ping) arrives for this long. Default 3 s.
    public var staleAfter: Double?
    /// Expand the island when this starts (vs. compact only).
    public var expand: Bool?
    public init(priority: Priority? = nil, staleAfter: Double? = nil, expand: Bool? = nil) {
        self.priority = priority; self.staleAfter = staleAfter; self.expand = expand
    }
}

// MARK: - Frames

public struct Hello: Codable, Sendable, Hashable {
    public var v: Int
    /// Advisory; Saddle Island trusts the peer's audit token (LOCAL_PEERTOKEN), not this.
    public var bundleID: String?
    public var name: String
    public var pid: Int32
    public init(bundleID: String?, name: String, pid: Int32 = getpid()) {
        self.v = IslandKit.protocolVersion; self.bundleID = bundleID; self.name = name; self.pid = pid
    }
}

public struct Welcome: Codable, Sendable, Hashable {
    public var v: Int
    /// False when the user switched this app's module off: the client should show its own UI.
    public var accepted: Bool
    public var server: String
    public init(accepted: Bool, server: String) { self.v = IslandKit.protocolVersion; self.accepted = accepted; self.server = server }
}

/// An app's own screen inside Saddle Island: when the user clicks the app's tile in a bag, the island turns into it,
/// drawn in the island's style from this description (no views cross the socket). Sections of rows; each row is one
/// of a few kinds, and using one sends `ServerMessage.panelAction` back with its id (and the new value).
public struct IslandPanel: Codable, Sendable, Hashable {
    public var title: String?
    public var sections: [Section]
    /// A round button in the header's left corner, opposite the close button (a gear for your settings): its `symbol`
    /// and `title` (the tooltip); a click sends its `id` like a button row.
    public var headerButton: Row?

    public init(title: String? = nil, sections: [Section], headerButton: Row? = nil) {
        self.title = title
        self.sections = sections
        self.headerButton = headerButton
    }

    public struct Section: Codable, Sendable, Hashable {
        public var title: String?
        public var rows: [Row]
        public init(title: String? = nil, rows: [Row]) {
            self.title = title
            self.rows = rows
        }
    }

    public struct Row: Codable, Sendable, Hashable, Identifiable {
        public enum Kind: String, Codable, Sendable {
            /// A label, with an optional value on the right.
            case text
            /// A button; `role` colours it.
            case button
            /// A switch: `on`.
            case toggle
            /// `value` between `min` and `max`.
            case slider
            /// One of `options`, `selected` lit.
            case choice
            /// A clickable list row: title, subtitle, symbol (a recent item, a file).
            case item
            /// A live activity of yours (`activity`, its id) drawn large: a waveform from its `levels` and its
            /// `transcript` as one line moving left; idle, a flat line and `title` as a quiet placeholder.
            case live
        }
        /// Echoed back in `panelAction`. Unique within the panel.
        public var id: String
        public var kind: Kind
        public var title: String?
        public var subtitle: String?
        /// An SF Symbol.
        public var symbol: String?
        /// `text`: the value on the right.
        public var detail: String?
        public var on: Bool?
        public var value: Double?
        public var min: Double?
        public var max: Double?
        public var options: [String]?
        public var selected: String?
        public var role: ActivityAction.Role?
        /// Drawn quieter: a status line under a heading.
        public var secondary: Bool?
        /// `live`: the id of the activity to draw.
        public var activity: String?

        public init(
            id: String, kind: Kind, title: String? = nil, subtitle: String? = nil, symbol: String? = nil,
            detail: String? = nil, on: Bool? = nil, value: Double? = nil, min: Double? = nil, max: Double? = nil,
            options: [String]? = nil, selected: String? = nil, role: ActivityAction.Role? = nil, secondary: Bool? = nil,
            activity: String? = nil
        ) {
            self.id = id
            self.kind = kind
            self.title = title
            self.subtitle = subtitle
            self.symbol = symbol
            self.detail = detail
            self.on = on
            self.value = value
            self.min = min
            self.max = max
            self.options = options
            self.selected = selected
            self.role = role
            self.secondary = secondary
            self.activity = activity
        }
    }

    /// Up to 8 sections of up to 40 rows; text up to 160 characters, 12 options. Saddle Island trims the rest.
    public static let maxSections = 8
    public static let maxRows = 40
    public static let maxText = 160
    public static let maxOptions = 12

    /// Within the limits, numbers finite.
    public var trimmed: IslandPanel {
        func cut(_ s: String?) -> String? { s.map { String($0.prefix(Self.maxText)) } }
        return IslandPanel(
            title: cut(title),
            sections: sections.prefix(Self.maxSections).map { section in
                Section(title: cut(section.title), rows: section.rows.prefix(Self.maxRows).map { row in
                    var r = row
                    r.id = String(row.id.prefix(64))
                    r.title = cut(row.title)
                    r.subtitle = cut(row.subtitle)
                    r.detail = cut(row.detail)
                    r.options = row.options.map { Array($0.prefix(Self.maxOptions).map { String($0.prefix(40)) }) }
                    for key in [\Row.value, \Row.min, \Row.max] where r[keyPath: key]?.isFinite == false { r[keyPath: key] = nil }
                    return r
                })
            },
            headerButton: headerButton.map { button in
                var b = button
                b.id = String(button.id.prefix(64))
                b.title = cut(button.title)
                return b
            })
    }
}

// MARK: - Search provider

/// What the user typed in the island's search, sent to the app of a plugin that provides the search
/// (`PluginPrivileges.searchProvider`, Kigo). `id` grows with every keystroke and each time the search opens
/// (then with empty `text`: the app's suggestions, if any).
public struct SearchProviderQuery: Codable, Sendable, Hashable {
    public var id: Int
    public var text: String

    public init(id: Int, text: String) { self.id = id; self.text = text }
}

/// One row of a search provider's results, drawn by the island in its own style.
public struct SearchProviderRow: Codable, Sendable, Hashable {
    /// Echoed back in `SearchProviderPick`. Unique within the results.
    public var id: String
    public var title: String
    public var subtitle: String?
    /// The Finder icon of this path (an app, file, folder or Settings extension).
    public var iconPath: String?
    /// The default browser's icon, when there's no `iconPath`.
    public var browser: Bool?
    /// An SF Symbol on a grey tile, when there's neither.
    public var symbol: String?
    /// What ⌘C copies with the row selected.
    public var copy: String?
    /// ⌘Return shows it in Finder (the pick's `how` is `reveal`).
    public var reveal: Bool?
    /// Drawn as an answer (larger, all emphasised): a calculator result.
    public var answer: Bool?

    public init(
        id: String, title: String, subtitle: String? = nil, iconPath: String? = nil, browser: Bool? = nil,
        symbol: String? = nil, copy: String? = nil, reveal: Bool? = nil, answer: Bool? = nil
    ) {
        self.id = id
        self.title = title
        self.subtitle = subtitle
        self.iconPath = iconPath
        self.browser = browser
        self.symbol = symbol
        self.copy = copy
        self.reveal = reveal
        self.answer = answer
    }
}

/// A search provider's answer to query `query`: its rows, best first (replacing any earlier answer: send again
/// when more arrive, such as files), or `close` to close the search (after a pick opened something).
public struct SearchProviderResults: Codable, Sendable, Hashable {
    public var query: Int
    public var rows: [SearchProviderRow]?
    public var close: Bool?

    public init(query: Int, rows: [SearchProviderRow]? = nil, close: Bool? = nil) {
        self.query = query
        self.rows = rows
        self.close = close
    }

    public static let maxRows = 20

    /// At most `maxRows` rows, text cut to 160 characters, ids to 200.
    public var trimmed: SearchProviderResults {
        func cut(_ text: String?) -> String? { text.map { String($0.prefix(160)) } }
        return SearchProviderResults(
            query: query,
            rows: rows.map { rows in
                rows.prefix(Self.maxRows).map { row in
                    var r = row
                    r.id = String(row.id.prefix(200))
                    r.title = String(row.title.prefix(160))
                    r.subtitle = cut(row.subtitle)
                    r.symbol = row.symbol.map { String($0.prefix(64)) }
                    r.copy = row.copy.map { String($0.prefix(4096)) }
                    return r
                }
            },
            close: close)
    }
}

/// The user picked row `row` of the answer to query `query`: open it, or (`reveal`) show it in Finder. The app
/// answers with `SearchProviderResults` (`close`, or new rows to stay open, such as "press Return again").
public struct SearchProviderPick: Codable, Sendable, Hashable {
    public enum How: String, Codable, Sendable { case open, reveal }

    public var query: Int
    public var row: String
    public var how: How

    public init(query: Int, row: String, how: How) { self.query = query; self.row = row; self.how = how }
}

/// Client → Saddle Island.
public enum ClientMessage: Sendable, Hashable {
    case hello(Hello)
    case start(id: String, content: ActivityContent, options: ActivityOptions?)
    case update(id: String, content: ActivityContent)
    case end(id: String, dismissAfter: Double?)
    case ping
    /// The app's screen in the island (`IslandPanel`); nil takes it away.
    case panel(IslandPanel?)
    /// A search provider's rows for a query (`SearchProviderResults`).
    case results(SearchProviderResults)
}

/// Saddle Island → client.
public enum ServerMessage: Sendable, Hashable {
    case welcome(Welcome)
    /// The user toggled the module while connected.
    case policy(accepted: Bool)
    /// Sent from Saddle Island's main actor after the frame `seq` was applied: proof the UI is alive.
    /// `presented` = Saddle Island can show this client's activities right now (false while the island is
    /// suppressed, e.g. fullscreen/screen-sharing privacy): the client should show its own UI.
    case ack(seq: UInt64, presented: Bool)
    case pong(seq: UInt64)
    case action(id: String, action: String)
    case dismissed(id: String)
    /// The user used a row of the app's panel: its id, and the new value (a toggle's "true"/"false", a slider's
    /// number, a choice's option), or `"@shown"` when the panel opened (refresh it now). Sent as an `action`
    /// frame with id `"panel"`.
    case panelAction(row: String, value: String?)
    /// To a search provider's app: the island's search field now reads this.
    case query(SearchProviderQuery)
    /// To a search provider's app: the user picked one of its rows.
    case pick(SearchProviderPick)
}

public enum FrameKey: String, CodingKey {
    case type, seq, t, hello, welcome, id, content, options, dismissAfter, accepted, presented, action, panel, value
    case query, pick, results
}

public protocol FrameCodable {
    init(type: String, from c: KeyedDecodingContainer<FrameKey>) throws
    func encode(into c: inout KeyedEncodingContainer<FrameKey>) throws
}

public struct Frame<Message: Sendable & Hashable & FrameCodable>: Codable, Sendable {
    public var seq: UInt64
    /// Sender's IslandKit.now() — optional, for latency diagnostics.
    public var t: UInt64?
    public var message: Message
    public init(seq: UInt64, t: UInt64? = IslandKit.now(), message: Message) { self.seq = seq; self.t = t; self.message = message }

    public init(from decoder: any Decoder) throws {
        let c = try decoder.container(keyedBy: FrameKey.self)
        seq = try c.decode(UInt64.self, forKey: .seq)
        t = try c.decodeIfPresent(UInt64.self, forKey: .t)
        message = try Message(type: c.decode(String.self, forKey: .type), from: c)
    }

    public func encode(to encoder: any Encoder) throws {
        var c = encoder.container(keyedBy: FrameKey.self)
        try c.encode(seq, forKey: .seq)
        try c.encodeIfPresent(t, forKey: .t)
        try message.encode(into: &c)
    }
}

extension ClientMessage: FrameCodable {
    public init(type: String, from c: KeyedDecodingContainer<FrameKey>) throws {
        switch type {
        case "hello": self = .hello(try c.decode(Hello.self, forKey: .hello))
        case "start": self = .start(id: try c.decode(String.self, forKey: .id),
                                    content: try c.decode(ActivityContent.self, forKey: .content),
                                    options: try c.decodeIfPresent(ActivityOptions.self, forKey: .options))
        case "update": self = .update(id: try c.decode(String.self, forKey: .id),
                                      content: try c.decode(ActivityContent.self, forKey: .content))
        case "end": self = .end(id: try c.decode(String.self, forKey: .id),
                                dismissAfter: try c.decodeIfPresent(Double.self, forKey: .dismissAfter))
        case "ping": self = .ping
        case "panel": self = .panel(try c.decodeIfPresent(IslandPanel.self, forKey: .panel))
        case "results": self = .results(try c.decode(SearchProviderResults.self, forKey: .results))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown type \(type)")
        }
    }

    public func encode(into c: inout KeyedEncodingContainer<FrameKey>) throws {
        switch self {
        case .hello(let h):
            try c.encode("hello", forKey: .type); try c.encode(h, forKey: .hello)
        case .start(let id, let content, let options):
            try c.encode("start", forKey: .type); try c.encode(id, forKey: .id)
            try c.encode(content, forKey: .content); try c.encodeIfPresent(options, forKey: .options)
        case .update(let id, let content):
            try c.encode("update", forKey: .type); try c.encode(id, forKey: .id); try c.encode(content, forKey: .content)
        case .end(let id, let dismissAfter):
            try c.encode("end", forKey: .type); try c.encode(id, forKey: .id); try c.encodeIfPresent(dismissAfter, forKey: .dismissAfter)
        case .ping:
            try c.encode("ping", forKey: .type)
        case .panel(let panel):
            try c.encode("panel", forKey: .type); try c.encodeIfPresent(panel, forKey: .panel)
        case .results(let results):
            try c.encode("results", forKey: .type); try c.encode(results, forKey: .results)
        }
    }
}

/// For `ack` and `pong` the frame's own `seq` is the client seq being acknowledged.
extension ServerMessage: FrameCodable {
    public init(type: String, from c: KeyedDecodingContainer<FrameKey>) throws {
        switch type {
        case "welcome": self = .welcome(try c.decode(Welcome.self, forKey: .welcome))
        case "policy": self = .policy(accepted: try c.decode(Bool.self, forKey: .accepted))
        case "ack": self = .ack(seq: try c.decode(UInt64.self, forKey: .seq), presented: try c.decode(Bool.self, forKey: .presented))
        case "pong": self = .pong(seq: try c.decode(UInt64.self, forKey: .seq))
        case "action":
            let id = try c.decode(String.self, forKey: .id), action = try c.decode(String.self, forKey: .action)
            self = id == "panel"
                ? .panelAction(row: action, value: try c.decodeIfPresent(String.self, forKey: .value))
                : .action(id: id, action: action)
        case "dismissed": self = .dismissed(id: try c.decode(String.self, forKey: .id))
        case "query": self = .query(try c.decode(SearchProviderQuery.self, forKey: .query))
        case "pick": self = .pick(try c.decode(SearchProviderPick.self, forKey: .pick))
        default: throw DecodingError.dataCorruptedError(forKey: .type, in: c, debugDescription: "unknown type \(type)")
        }
    }

    public func encode(into c: inout KeyedEncodingContainer<FrameKey>) throws {
        switch self {
        case .welcome(let w): try c.encode("welcome", forKey: .type); try c.encode(w, forKey: .welcome)
        case .policy(let accepted): try c.encode("policy", forKey: .type); try c.encode(accepted, forKey: .accepted)
        case .ack(_, let presented): try c.encode("ack", forKey: .type); try c.encode(presented, forKey: .presented)
        case .pong: try c.encode("pong", forKey: .type)
        case .action(let id, let action): try c.encode("action", forKey: .type); try c.encode(id, forKey: .id); try c.encode(action, forKey: .action)
        case .dismissed(let id): try c.encode("dismissed", forKey: .type); try c.encode(id, forKey: .id)
        case .panelAction(let row, let value):
            try c.encode("action", forKey: .type); try c.encode("panel", forKey: .id); try c.encode(row, forKey: .action)
            try c.encodeIfPresent(value, forKey: .value)
        case .query(let query): try c.encode("query", forKey: .type); try c.encode(query, forKey: .query)
        case .pick(let pick): try c.encode("pick", forKey: .type); try c.encode(pick, forKey: .pick)
        }
    }
}

// MARK: - NDJSON codec

public enum NDJSON {
    public static func encode<M>(_ frame: Frame<M>) throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.withoutEscapingSlashes]
        var data = try encoder.encode(frame)
        data.append(0x0A)
        return data
    }

    /// Splits complete lines off the front of `buffer` and decodes them.
    public static func drain<M>(_ buffer: inout Data, as: M.Type) -> [Result<Frame<M>, any Error>] {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        var out: [Result<Frame<M>, any Error>] = []
        while let nl = buffer.firstIndex(of: 0x0A) {
            let line = buffer[buffer.startIndex..<nl]
            buffer.removeSubrange(buffer.startIndex...nl)
            if line.isEmpty { continue }
            out.append(Result { try decoder.decode(Frame<M>.self, from: Data(line)) })
        }
        return out
    }
}

// MARK: - Socket helpers (Darwin)

public enum UnixSocket {
    /// SO_NOSIGPIPE: a write to a peer that died returns EPIPE instead of killing this process.
    public static func configure(_ fd: Int32, nonBlocking: Bool) {
        var one: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &one, socklen_t(MemoryLayout<Int32>.size))
        if nonBlocking { _ = fcntl(fd, F_SETFL, fcntl(fd, F_GETFL) | O_NONBLOCK) }
        _ = fcntl(fd, F_SETFD, FD_CLOEXEC)
    }

    static func address(_ path: String) -> sockaddr_un? {
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8)
        guard bytes.count < MemoryLayout.size(ofValue: addr.sun_path) else { return nil }
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            raw.copyBytes(from: bytes)
            raw[bytes.count] = 0
        }
        addr.sun_len = UInt8(MemoryLayout<sockaddr_un>.size)
        return addr
    }

    /// Returns a connected fd, or errno (ENOENT: Saddle Island never ran; ECONNREFUSED: stale socket file).
    public static func connect(path: String) -> Result<Int32, POSIXError> {
        guard var addr = address(path) else { return .failure(POSIXError(.ENAMETOOLONG)) }
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return .failure(POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO)) }
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        guard rc == 0 else {
            let e = errno
            close(fd)
            return .failure(POSIXError(POSIXErrorCode(rawValue: e) ?? .EIO))
        }
        configure(fd, nonBlocking: true)
        return .success(fd)
    }

    /// Binds and listens. A leftover file from a crashed server is replaced only if nothing answers on it.
    public static func listen(path: String) -> Result<Int32, POSIXError> {
        guard var addr = address(path) else { return .failure(POSIXError(.ENAMETOOLONG)) }
        if case .success(let probe) = connect(path: path) {
            close(probe)
            return .failure(POSIXError(.EADDRINUSE)) // another server is alive
        }
        unlink(path)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        let old = umask(0o077) // socket file 0700 (srwx------): same user only
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, socklen_t(MemoryLayout<sockaddr_un>.size)) }
        }
        umask(old)
        guard rc == 0, Darwin.listen(fd, 16) == 0 else {
            let e = errno
            close(fd)
            return .failure(POSIXError(POSIXErrorCode(rawValue: e) ?? .EIO))
        }
        configure(fd, nonBlocking: true)
        return .success(fd)
    }

    /// The peer's audit token (LOCAL_PEERTOKEN) → its code-signing identifier and team, via SecCode.
    public static func peerIdentity(_ fd: Int32) -> (pid: pid_t, identifier: String?, team: String?) {
        var token = audit_token_t()
        var len = socklen_t(MemoryLayout<audit_token_t>.size)
        var pid: pid_t = 0
        var plen = socklen_t(MemoryLayout<pid_t>.size)
        getsockopt(fd, SOL_LOCAL, LOCAL_PEERPID, &pid, &plen)
        guard getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, &token, &len) == 0 else { return (pid, nil, nil) }
        let tokenData = withUnsafeBytes(of: &token) { Data($0) }
        var code: SecCode?
        let attrs = [kSecGuestAttributeAudit: tokenData] as CFDictionary
        guard SecCodeCopyGuestWithAttributes(nil, attrs, [], &code) == errSecSuccess, let code else { return (pid, nil, nil) }
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, [], &staticCode) == errSecSuccess, let staticCode else { return (pid, nil, nil) }
        var info: CFDictionary?
        SecCodeCopySigningInformation(staticCode, SecCSFlags(rawValue: kSecCSSigningInformation), &info)
        let dict = info as? [String: Any] ?? [:]
        return (pid, dict[kSecCodeInfoIdentifier as String] as? String, dict[kSecCodeInfoTeamIdentifier as String] as? String)
    }

    /// Writes all of `data` or reports why not. Non-blocking fds return .wouldBlock instead of stalling.
    public enum WriteResult: Equatable { case ok, wouldBlock(written: Int), failed(Int32) }
    public static func write(_ fd: Int32, _ data: Data) -> WriteResult {
        data.withUnsafeBytes { raw -> WriteResult in
            var off = 0
            while off < raw.count {
                let n = Darwin.write(fd, raw.baseAddress! + off, raw.count - off)
                if n > 0 { off += n; continue }
                if errno == EINTR { continue }
                if errno == EAGAIN { return .wouldBlock(written: off) }
                return .failed(errno)
            }
            return .ok
        }
    }
}
