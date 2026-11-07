// Built-in commands, and what Enter does for each kind of result.
import AppKit

private struct CommandInfo {
	let id: String
	let title: String
	let subtitle: String
	let keywords: String
	let symbol: String
	var needsConfirm = false
	/// A folder opens in Finder and shows its own icon.
	var folder: String?
}

private let home = NSHomeDirectory()
private let commands: [CommandInfo] = [
	CommandInfo(id: "sleep", title: "Sleep", subtitle: "System", keywords: "suspend", symbol: "moon.fill"),
	CommandInfo(id: "lock", title: "Lock Screen", subtitle: "System", keywords: "away", symbol: "lock.fill"),
	CommandInfo(id: "restart", title: "Restart", subtitle: "System", keywords: "reboot",
		symbol: "arrow.clockwise", needsConfirm: true),
	CommandInfo(id: "shutdown", title: "Shut Down", subtitle: "System", keywords: "power off poweroff halt",
		symbol: "power", needsConfirm: true),
	CommandInfo(id: "logout", title: "Log Out", subtitle: "System", keywords: "sign out signout",
		symbol: "rectangle.portrait.and.arrow.right", needsConfirm: true),
	CommandInfo(id: "empty-trash", title: "Empty Trash", subtitle: "Finder", keywords: "delete clean bin",
		symbol: "trash.fill", needsConfirm: true),
	CommandInfo(id: "dark-mode", title: "Toggle Dark Mode", subtitle: "Appearance",
		keywords: "light theme appearance night", symbol: "circle.lefthalf.filled"),
	CommandInfo(id: "home", title: "Home", subtitle: "Folder", keywords: "folder user", symbol: "house",
		folder: home),
	CommandInfo(id: "desktop", title: "Desktop", subtitle: "Folder", keywords: "folder", symbol: "menubar.dock.rectangle",
		folder: home + "/Desktop"),
	CommandInfo(id: "documents", title: "Documents", subtitle: "Folder", keywords: "folder", symbol: "doc",
		folder: home + "/Documents"),
	CommandInfo(id: "downloads", title: "Downloads", subtitle: "Folder", keywords: "folder", symbol: "arrow.down.circle",
		folder: home + "/Downloads"),
	CommandInfo(id: "applications", title: "Applications", subtitle: "Folder", keywords: "folder apps",
		symbol: "square.grid.2x2", folder: "/Applications"),
	CommandInfo(id: "trash", title: "Trash", subtitle: "Folder", keywords: "bin deleted", symbol: "trash",
		folder: home + "/.Trash"),
	CommandInfo(id: "new-terminal", title: "New Terminal Window", subtitle: "Terminal", keywords: "shell console",
		symbol: "terminal"),
	CommandInfo(id: "settings", title: "Kigo Settings", subtitle: "Kigo",
		keywords: "preferences options configure setup", symbol: "gearshape"),
	CommandInfo(id: "reindex", title: "Reload Applications", subtitle: "Kigo", keywords: "refresh rescan reindex",
		symbol: "arrow.triangle.2.circlepath"),
	CommandInfo(id: "update", title: "Check for Updates", subtitle: "Kigo", keywords: "upgrade update version kigo",
		symbol: "arrow.down.circle"),
	CommandInfo(id: "quit", title: "Quit Kigo", subtitle: "Kigo", keywords: "exit close", symbol: "xmark.circle"),
]

private func makeCommand(_ info: CommandInfo) -> Result {
	var result = Result(kind: .command, title: info.title, subtitle: info.subtitle, id: "cmd:" + info.id,
		payload: info.id, needsConfirm: info.needsConfirm, symbol: info.symbol)
	if info.subtitle == "Kigo" {
		result.symbol = nil
		result.icon = Icons.kigo
	} else if info.id == "new-terminal" {
		result.icon = Icons.app("com.apple.Terminal")
		result.symbol = result.icon == nil ? info.symbol : nil
	}
	if let folder = info.folder {
		result.kind = .folder
		result.subtitle = folder.replacingOccurrences(of: home, with: "~")
		result.path = folder
		result.icon = Icons.forPath(folder)
		result.symbol = nil
	}
	return result
}

/// Matching built-in commands, scored; with `all` false, only Kigo Settings
/// (which must stay findable).
func searchCommands(_ query: String, all: Bool) -> [Result] {
	var results: [Result] = []
	for info in commands where all || info.id == "settings" {
		var score = fuzzyScore(query, info.title)
		for word in info.keywords.split(separator: " ") {
			let keywordScore = fuzzyScore(query, String(word)) * 0.75
			if keywordScore >= 600 && keywordScore > score { score = keywordScore }
		}
		if score <= 0 { continue }
		var result = makeCommand(info)
		result.score = score
		results.append(result)
	}
	return results
}

/// Rebuilds a command result from its id ("cmd:sleep") for suggestions.
func command(forId id: String) -> Result? {
	guard id.hasPrefix("cmd:") else { return nil }
	let name = id.dropFirst(4)
	return commands.first(where: { $0.id == name }).map(makeCommand)
}

/// "apple.com", "github.com/x", "https://…": the URL to open, or nil.
func urlFor(_ text: String) -> String? {
	let input = text.trimmingCharacters(in: .whitespaces)
	if input.isEmpty || input.contains(" ") { return nil }
	let lower = input.lowercased()
	for scheme in ["http://", "https://", "ftp://", "file://"] where lower.hasPrefix(scheme) { return input }
	if lower.hasPrefix("www.") { return "https://" + input }

	// A dot followed by a 2+ letter TLD.
	let host = input.split(separator: "/", maxSplits: 1, omittingEmptySubsequences: false)[0]
	guard let dot = host.lastIndex(of: "."), dot != host.startIndex else { return nil }
	let tld = host[host.index(after: dot)...]
	guard tld.count >= 2, tld.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
	guard host.allSatisfy({ $0.isASCII && ($0.isLetter || $0.isNumber || ".-:".contains($0)) }) else { return nil }
	return "https://" + input
}

// Actions ------------------------------------------------------------------

enum Actions {
	/// Opens a result; false when it couldn't. `alternate` (Shift) opens a
	/// new instance of an app.
	static func open(_ result: Result, alternate: Bool) -> Bool {
		switch result.kind {
		case .app:
			guard let path = result.path else { return false }
			let config = NSWorkspace.OpenConfiguration()
			config.createsNewApplicationInstance = alternate
			NSWorkspace.shared.openApplication(at: URL(fileURLWithPath: path), configuration: config)
			return true
		case .preference:
			return openURL("x-apple.systempreferences:" + result.payload)
		case .file, .folder:
			guard let path = result.path else { return false }
			return NSWorkspace.shared.open(URL(fileURLWithPath: path))
		case .url, .web:
			return openURL(result.payload)
		case .calculator:
			copy(result.payload)
			return true
		case .shell:
			return runInTerminal(result.payload)
		case .command:
			return run(result.payload)
		}
	}

	static func reveal(_ result: Result) -> Bool {
		guard let path = result.path else { return false }
		NSWorkspace.shared.activateFileViewerSelecting([URL(fileURLWithPath: path)])
		return true
	}

	/// The path, answer or URL; nil when there's nothing worth copying.
	static func copyText(_ result: Result) -> String? {
		if let path = result.path { return path }
		switch result.kind {
		case .calculator, .url, .web, .shell: return result.payload
		default: return nil
		}
	}

	static func copy(_ text: String) {
		NSPasteboard.general.clearContents()
		NSPasteboard.general.setString(text, forType: .string)
	}

	private static func openURL(_ text: String) -> Bool {
		guard let url = URL(string: text) else { return false }
		return NSWorkspace.shared.open(url)
	}

	private static func appleScript(_ source: String) -> Bool {
		var error: NSDictionary?
		NSAppleScript(source: source)?.executeAndReturnError(&error)
		if let error { NSLog("Kigo: AppleScript failed: \(error)") }
		return error == nil
	}

	private static func quoted(_ text: String) -> String {
		"\"" + text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"") + "\""
	}

	static func runInTerminal(_ command: String) -> Bool {
		appleScript("""
			tell application "Terminal"
				activate
				do script \(quoted(command))
			end tell
			""")
	}

	private static func shell(_ path: String, _ arguments: [String]) -> Bool {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: path)
		process.arguments = arguments
		return (try? process.run()) != nil
	}

	private static func lockScreen() -> Bool {
		// The same call as the Lock Screen menu item.
		guard let handle = dlopen("/System/Library/PrivateFrameworks/login.framework/Versions/Current/login", RTLD_NOW),
			let symbol = dlsym(handle, "SACLockScreenImmediate") else { return false }
		typealias Lock = @convention(c) () -> Int32
		_ = unsafeBitCast(symbol, to: Lock.self)()
		return true
	}

	private static func run(_ id: String) -> Bool {
		switch id {
		case "sleep": return shell("/usr/bin/pmset", ["sleepnow"])
		case "lock": return lockScreen()
		case "restart": return appleScript("tell application \"System Events\" to restart")
		case "shutdown": return appleScript("tell application \"System Events\" to shut down")
		case "logout": return appleScript("tell application \"System Events\" to log out")
		case "empty-trash": return appleScript("tell application \"Finder\" to empty trash")
		case "dark-mode":
			return appleScript("""
				tell application "System Events" to tell appearance preferences to set dark mode to not dark mode
				""")
		case "new-terminal":
			return appleScript("tell application \"Terminal\"\nactivate\ndo script \"\"\nend tell")
		case "reindex":
			NotificationCenter.default.post(name: .kigoReindex, object: nil)
			return true
		case "update":
			Updater.shared.check(manual: true)
			return true
		case "quit":
			NSApp.terminate(nil)
			return true
		default:
			return false
		}
	}
}

extension Notification.Name {
	static let kigoReindex = Notification.Name("KigoReindex")
}
