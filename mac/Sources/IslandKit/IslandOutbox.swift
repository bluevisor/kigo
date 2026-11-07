// Vendored from SaddleIsland/Packages/IslandKit — keep in sync.
// Client-side queue of frames the socket hasn't taken yet.
import Foundation

/// Frames waiting for the socket. Activity content is full state (every `update` replaces the
/// whole thing), so a newer frame for an activity replaces an older one that was never written:
/// under congestion the client sends the latest state, not a backlog.
nonisolated struct IslandOutbox: Sendable {
    /// Hard bound. Past it, queued updates and pings are dropped oldest first, then anything.
    static let capacity = 64

    private(set) var messages: [ClientMessage] = []

    var isEmpty: Bool { messages.isEmpty }
    var count: Int { messages.count }

    mutating func popFirst() -> ClientMessage? {
        messages.isEmpty ? nil : messages.removeFirst()
    }

    mutating func removeAll() { messages.removeAll() }

    mutating func enqueue(_ message: ClientMessage) {
        switch message {
        case .hello:
            messages.append(message)
        case .ping:
            // Any queued frame proves liveness as well as a ping does.
            if messages.isEmpty { messages.append(message) }
        case .start(let id, _, _):
            removeUnsentState(of: id)
            messages.append(message)
        case .update(let id, let content):
            switch lastIndex(of: id).map({ (index: $0, message: messages[$0]) }) {
            case let (i, .start(_, _, options))?:
                messages[i] = .start(id: id, content: content, options: options)
            case let (i, .update)?:
                messages[i] = message
            default:
                messages.append(message)
            }
        case .end(let id, _):
            removeUnsentState(of: id, keepingStarts: true)
            messages.append(message)
        case .panel:
            // Only the latest panel matters.
            messages.removeAll { if case .panel = $0 { true } else { false } }
            messages.append(message)
        }
        enforceCapacity()
    }

    /// Drops queued `start`/`update` frames for `id` back to its last queued `end`.
    private mutating func removeUnsentState(of id: String, keepingStarts: Bool = false) {
        var i = messages.count - 1
        while i >= 0 {
            switch messages[i] {
            case .end(let other, _) where other == id:
                return
            case .update(let other, _) where other == id:
                messages.remove(at: i)
            case .start(let other, _, _) where other == id && !keepingStarts:
                messages.remove(at: i)
            default:
                break
            }
            i -= 1
        }
    }

    private func lastIndex(of id: String) -> Int? {
        messages.lastIndex { message in
            switch message {
            case .start(let other, _, _), .update(let other, _), .end(let other, _): other == id
            case .hello, .ping, .panel: false
            }
        }
    }

    private mutating func enforceCapacity() {
        while messages.count > Self.capacity, let i = messages.firstIndex(where: \.isDroppable) {
            messages.remove(at: i)
        }
        while messages.count > Self.capacity, let i = messages.firstIndex(where: { !$0.isHello }) {
            messages.remove(at: i)
        }
    }
}

extension ClientMessage {
    nonisolated var isDroppable: Bool {
        switch self {
        case .update, .ping: true
        case .hello, .start, .end, .panel: false
        }
    }

    nonisolated var isHello: Bool {
        if case .hello = self { true } else { false }
    }
}
