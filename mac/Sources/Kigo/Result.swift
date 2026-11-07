// One row in Kigo's results list.
import AppKit

enum ResultKind {
	case app, preference, file, folder, command, calculator, url, web, shell

	var label: String {
		switch self {
		case .app: return "Application"
		case .preference: return "Settings Pane"
		case .file: return "File"
		case .folder: return "Folder"
		case .command: return "Command"
		case .calculator: return "Calculator"
		case .url: return "Link"
		case .web: return "Web Search"
		case .shell: return "Terminal"
		}
	}
}

struct Result: Identifiable {
	var kind: ResultKind
	var title: String
	var subtitle = ""
	/// Stable key for history/frecency: "app:/path", "file:/path", "cmd:sleep".
	var id: String
	var section = ""
	/// Command id, calculator value, URL, settings pane id or shell command line.
	var payload = ""
	var path: String?
	var needsConfirm = false
	var score = 0.0
	/// An SF Symbol drawn on a tile, for rows without a file icon.
	var symbol: String?
	var icon: NSImage?

	var canReveal: Bool { path != nil }

	var primaryAction: String {
		switch kind {
		case .app: return "Open Application"
		case .preference: return "Open Settings"
		case .file: return "Open File"
		case .folder: return "Open Folder"
		case .command: return needsConfirm ? title : "Run Command"
		case .calculator: return "Copy Answer"
		case .url: return "Open Link"
		case .web: return "Search"
		case .shell: return "Run in Terminal"
		}
	}
}

/// File icons, looked up once per path.
enum Icons {
	private static var cache: [String: NSImage] = [:]

	static func forPath(_ path: String) -> NSImage {
		if let icon = cache[path] { return icon }
		let icon = NSWorkspace.shared.icon(forFile: path)
		cache[path] = icon
		return icon
	}

	static func app(_ bundleID: String) -> NSImage? {
		guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
		return forPath(url.path)
	}

	static var browser: NSImage? {
		guard let url = NSWorkspace.shared.urlForApplication(toOpen: URL(string: "https://example.com")!)
		else { return nil }
		return forPath(url.path)
	}

	static var kigo: NSImage { NSApplication.shared.applicationIconImage }

	/// The ginkgo leaf alone (no icon tile): the bundle's copy of
	/// haiku/kigo.svg, or the source tree's when run from `swift build`.
	static let leaf: NSImage = {
		let source = URL(fileURLWithPath: #filePath)
			.deletingLastPathComponent().appendingPathComponent("../../../haiku/kigo.svg")
		for url in [Bundle.main.url(forResource: "kigo-leaf", withExtension: "svg"), source] {
			if let url, let image = NSImage(contentsOf: url) { return image }
		}
		return kigo
	}()
}
