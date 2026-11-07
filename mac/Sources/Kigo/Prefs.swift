// What you picked in Kigo's settings page, kept in UserDefaults.
import AppKit
import ServiceManagement

enum WebSearch: Int, CaseIterable {
	case off, duckDuckGo, google, bing

	var name: String { ["Off", "DuckDuckGo", "Google", "Bing"][rawValue] }

	func url(for query: String) -> String? {
		var allowed = CharacterSet.urlQueryAllowed
		allowed.remove(charactersIn: "&+=#?")
		let q = query.addingPercentEncoding(withAllowedCharacters: allowed) ?? query
		switch self {
		case .off: return nil
		case .duckDuckGo: return "https://duckduckgo.com/?q=\(q)"
		case .google: return "https://www.google.com/search?q=\(q)"
		case .bing: return "https://www.bing.com/search?q=\(q)"
		}
	}
}

enum Size: Int, CaseIterable {
	case small, standard, large, larger

	var name: String { ["Small", "Default", "Large", "Larger"][rawValue] }
	var scale: CGFloat { [0.88, 1.0, 1.15, 1.3][rawValue] }
}

/// The key that opens Kigo, always with Space.
enum Shortcut: Int, CaseIterable {
	case option, control, command

	var name: String { ["⌥ Space", "⌃ Space", "⌘ Space"][rawValue] }
}

/// The color of the selected row, switches and choices.
enum ThemeColor: Int, CaseIterable {
	case ginkgo, system, blue, purple, pink, red, orange, green, graphite

	var name: String {
		["Ginkgo", "System accent", "Blue", "Purple", "Pink", "Red", "Orange", "Green", "Graphite"][rawValue]
	}

	var color: NSColor {
		switch self {
		case .ginkgo: return NSColor(red: 0.86, green: 0.68, blue: 0.30, alpha: 1)
		case .system: return .controlAccentColor
		case .blue: return NSColor(red: 0.04, green: 0.52, blue: 1.0, alpha: 1)
		case .purple: return NSColor(red: 0.66, green: 0.36, blue: 0.86, alpha: 1)
		case .pink: return NSColor(red: 0.97, green: 0.33, blue: 0.62, alpha: 1)
		case .red: return NSColor(red: 1.0, green: 0.29, blue: 0.25, alpha: 1)
		case .orange: return NSColor(red: 1.0, green: 0.58, blue: 0.0, alpha: 1)
		case .green: return NSColor(red: 0.22, green: 0.76, blue: 0.36, alpha: 1)
		case .graphite: return NSColor(red: 0.6, green: 0.6, blue: 0.63, alpha: 1)
		}
	}
}

final class Prefs: ObservableObject {
	static let shared = Prefs()
	private let defaults = UserDefaults.standard

	@Published var searchApps: Bool { didSet { defaults.set(searchApps, forKey: "searchApps") } }
	@Published var searchFiles: Bool { didSet { defaults.set(searchFiles, forKey: "searchFiles") } }
	@Published var searchCommands: Bool { didSet { defaults.set(searchCommands, forKey: "searchCommands") } }
	@Published var calculator: Bool { didSet { defaults.set(calculator, forKey: "calculator") } }
	@Published var suggestions: Bool { didSet { defaults.set(suggestions, forKey: "suggestions") } }
	@Published var webSearch: WebSearch { didSet { defaults.set(webSearch.rawValue, forKey: "webSearch") } }
	@Published var size: Size { didSet { defaults.set(size.rawValue, forKey: "size") } }
	@Published var shortcut: Shortcut { didSet { defaults.set(shortcut.rawValue, forKey: "shortcut") } }
	@Published var theme: ThemeColor { didSet { defaults.set(theme.rawValue, forKey: "theme") } }
	@Published var updates: Bool { didSet { defaults.set(updates, forKey: "updates") } }
	@Published var openAtLogin: Bool {
		didSet {
			guard openAtLogin != oldValue else { return }
			defaults.set(openAtLogin, forKey: "openAtLogin")
			Prefs.applyLoginItem(openAtLogin)
		}
	}

	private init() {
		defaults.register(defaults: [
			"searchApps": true, "searchFiles": true, "searchCommands": true,
			"calculator": true, "suggestions": true, "openAtLogin": true,
			"webSearch": WebSearch.duckDuckGo.rawValue, "size": Size.standard.rawValue,
			"shortcut": Shortcut.option.rawValue, "theme": ThemeColor.ginkgo.rawValue, "updates": true,
		])
		searchApps = defaults.bool(forKey: "searchApps")
		searchFiles = defaults.bool(forKey: "searchFiles")
		searchCommands = defaults.bool(forKey: "searchCommands")
		calculator = defaults.bool(forKey: "calculator")
		suggestions = defaults.bool(forKey: "suggestions")
		openAtLogin = defaults.bool(forKey: "openAtLogin")
		webSearch = WebSearch(rawValue: defaults.integer(forKey: "webSearch")) ?? .duckDuckGo
		size = Size(rawValue: defaults.integer(forKey: "size")) ?? .standard
		shortcut = Shortcut(rawValue: defaults.integer(forKey: "shortcut")) ?? .option
		theme = ThemeColor(rawValue: defaults.integer(forKey: "theme")) ?? .ginkgo
		updates = defaults.bool(forKey: "updates")
	}

	/// Registers or removes Kigo as a login item. Only an installed copy (in an
	/// Applications folder) registers, not a development build.
	static func applyLoginItem(_ on: Bool) {
		let service = SMAppService.mainApp
		if on {
			guard Bundle.main.bundlePath.contains("/Applications/") else { return }
			if service.status != .enabled { try? service.register() }
		} else if service.status == .enabled {
			try? service.unregister()
		}
	}
}
