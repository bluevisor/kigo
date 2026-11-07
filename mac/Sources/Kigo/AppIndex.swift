// The applications and System Settings panes Kigo can open, rescanned in the
// background when the launcher opens and the folders have changed.
import AppKit

struct AppEntry {
	var name: String
	var path: String
	var keywords: [String]
	/// System Settings pane id; nil for applications.
	var pane: String?
}

final class AppIndex {
	private var entries: [AppEntry] = []
	private let lock = NSLock()
	private var lastScan = Date.distantPast
	private var scanning = false

	private static let folders = [
		"/Applications", "/Applications/Utilities",
		"/System/Applications", "/System/Applications/Utilities",
		NSHomeDirectory() + "/Applications",
		"/System/Library/CoreServices/Applications",
	]
	private static let extras = ["/System/Library/CoreServices/Finder.app"]

	// Search words for apps whose names don't say what they're for.
	private static let aliases: [String: String] = [
		"com.apple.Safari": "browser web internet",
		"com.google.Chrome": "browser web internet",
		"org.mozilla.firefox": "browser web internet",
		"company.thebrowser.Browser": "browser web internet",
		"com.apple.Terminal": "shell console command",
		"dev.warp.Warp-Stable": "terminal shell console",
		"com.apple.systempreferences": "preferences settings control panel",
		"com.apple.ActivityMonitor": "task manager processes cpu",
		"com.apple.finder": "files folders explorer",
		"com.apple.calculator": "math",
		"com.apple.TextEdit": "editor text notepad",
		"com.apple.Preview": "pdf images viewer",
		"com.apple.MobileSMS": "messages imessage sms",
		"com.apple.AppStore": "store install",
	]

	// The System Settings panes worth finding, with the words people use.
	private static let panes: [(String, String, String)] = [
		("com.apple.wifi-settings-extension", "Wi-Fi", "wireless network internet"),
		("com.apple.BluetoothSettings", "Bluetooth", "devices headphones"),
		("com.apple.Network-Settings.extension", "Network", "ethernet vpn internet"),
		("com.apple.NetworkExtensionSettingsUI.NESettingsUIExtension", "VPN", "network"),
		("com.apple.Notifications-Settings.extension", "Notifications", "alerts banners"),
		("com.apple.Sound-Settings.extension", "Sound", "volume audio output input"),
		("com.apple.Focus-Settings.extension", "Focus", "do not disturb"),
		("com.apple.Screen-Time-Settings.extension", "Screen Time", "limits"),
		("com.apple.systempreferences.GeneralSettings", "General", ""),
		("com.apple.SystemProfiler.AboutExtension", "About This Mac", "version serial"),
		("com.apple.Software-Update-Settings.extension", "Software Update", "upgrade macos"),
		("com.apple.settings.Storage", "Storage", "disk space"),
		("com.apple.Appearance-Settings.extension", "Appearance", "dark mode light theme accent"),
		("com.apple.Accessibility-Settings.extension", "Accessibility", "zoom voiceover"),
		("com.apple.ControlCenter-Settings.extension", "Control Center", "menu bar"),
		("com.apple.Siri-Settings.extension", "Siri", "apple intelligence"),
		("com.apple.Spotlight-Settings.extension", "Spotlight", "search"),
		("com.apple.settings.PrivacySecurity.extension", "Privacy & Security", "permissions"),
		("com.apple.Desktop-Settings.extension", "Desktop & Dock", "dock stage manager mission control"),
		("com.apple.Displays-Settings.extension", "Displays", "monitor resolution brightness night shift"),
		("com.apple.Wallpaper-Settings.extension", "Wallpaper", "background desktop picture"),
		("com.apple.Lock-Screen-Settings.extension", "Lock Screen", "screen saver sleep"),
		("com.apple.Battery-Settings.extension", "Battery", "energy power"),
		("com.apple.Touch-ID-Settings.extension", "Touch ID & Password", "fingerprint login"),
		("com.apple.Users-Groups-Settings.extension", "Users & Groups", "accounts"),
		("com.apple.Internet-Accounts-Settings.extension", "Internet Accounts", "mail email"),
		("com.apple.Game-Center-Settings.extension", "Game Center", ""),
		("com.apple.Keyboard-Settings.extension", "Keyboard", "shortcuts input sources"),
		("com.apple.Mouse-Settings.extension", "Mouse", "pointer scroll"),
		("com.apple.Trackpad-Settings.extension", "Trackpad", "gestures pointer scroll"),
		("com.apple.Print-Scan-Settings.extension", "Printers & Scanners", "printer"),
		("com.apple.LoginItems-Settings.extension", "Login Items", "startup"),
		("com.apple.Sharing-Settings.extension", "Sharing", "airdrop file sharing remote"),
		("com.apple.Date-Time-Settings.extension", "Date & Time", "clock timezone"),
		("com.apple.Localization-Settings.extension", "Language & Region", "locale"),
		("com.apple.Time-Machine-Settings.extension", "Time Machine", "backup"),
		("com.apple.Startup-Disk-Settings.extension", "Startup Disk", "boot"),
		("com.apple.Transfer-Reset-Settings.extension", "Transfer or Reset", "erase"),
		("com.apple.systempreferences.AppleIDSettings", "Apple Account", "icloud apple id"),
	]

	/// Rescans when any app folder changed since the last scan, off the main thread.
	func refreshIfNeeded(completion: @escaping () -> Void) {
		let changed = AppIndex.folders.contains { folder in
			let date = (try? FileManager.default.attributesOfItem(atPath: folder)[.modificationDate]) as? Date
			return (date ?? .distantPast) > lastScan
		}
		guard changed || entries.isEmpty, !scanning else { return }
		rebuild(completion: completion)
	}

	func rebuild(completion: @escaping () -> Void) {
		scanning = true
		let started = Date()
		DispatchQueue.global(qos: .userInitiated).async {
			let found = AppIndex.scan()
			DispatchQueue.main.async {
				self.lock.lock()
				self.entries = found
				self.lock.unlock()
				self.lastScan = started
				self.scanning = false
				completion()
			}
		}
	}

	private static func scan() -> [AppEntry] {
		let fm = FileManager.default
		var seen = Set<String>()
		var found: [AppEntry] = []

		func add(_ path: String) {
			let resolved = (path as NSString).resolvingSymlinksInPath
			let bundle = Bundle(path: resolved)
			let id = bundle?.bundleIdentifier ?? resolved
			guard !seen.contains(id) else { return }
			seen.insert(id)
			var name = fm.displayName(atPath: path)
			if name.hasSuffix(".app") { name.removeLast(4) }
			var keywords: [String] = []
			if let bundleName = bundle?.infoDictionary?["CFBundleName"] as? String, bundleName != name {
				keywords.append(bundleName)
			}
			if let alias = aliases[id] { keywords += alias.split(separator: " ").map(String.init) }
			found.append(AppEntry(name: name, path: path, keywords: keywords, pane: nil))
		}

		for folder in folders {
			guard let items = try? fm.contentsOfDirectory(atPath: folder) else { continue }
			for item in items where !item.hasPrefix(".") {
				let path = folder + "/" + item
				if item.hasSuffix(".app") {
					add(path)
				} else if folder.hasPrefix("/Applications") || folder.hasSuffix("/Applications"),
					item != "Utilities",
					let inner = try? fm.contentsOfDirectory(atPath: path) {
					// One level into folders such as "Adobe Photoshop 2026".
					for app in inner where app.hasSuffix(".app") { add(path + "/" + app) }
				}
			}
		}
		for path in extras where fm.fileExists(atPath: path) { add(path) }

		for (id, name, words) in panes {
			found.append(AppEntry(name: name, path: "", keywords: words.split(separator: " ").map(String.init),
				pane: id))
		}
		return found
	}

	static let settingsAppPath = "/System/Applications/System Settings.app"

	static func makeResult(_ entry: AppEntry) -> Result {
		if let pane = entry.pane {
			return Result(kind: .preference, title: entry.name, subtitle: "System Settings",
				id: "pref:" + pane, payload: pane, icon: Icons.forPath(settingsAppPath))
		}
		let folder = (entry.path as NSString).deletingLastPathComponent
		return Result(kind: .app, title: entry.name, subtitle: folder.replacingOccurrences(
			of: NSHomeDirectory(), with: "~"), id: "app:" + entry.path, path: entry.path,
			icon: Icons.forPath(entry.path))
	}

	func search(_ query: String, includeApps: Bool) -> [Result] {
		lock.lock()
		let snapshot = entries
		lock.unlock()
		var results: [Result] = []
		for entry in snapshot {
			if !includeApps { break }
			var score = fuzzyScore(query, entry.name)
			if score <= 0 {
				// Match single keywords so "web" finds browsers; whole-word
				// prefixes only, so short queries don't light up everything.
				for word in entry.keywords {
					let keywordScore = fuzzyScore(query, word)
					if keywordScore >= 800 && keywordScore * 0.7 > score { score = keywordScore * 0.7 }
				}
			}
			if score <= 0 { continue }
			var result = AppIndex.makeResult(entry)
			// Apps outrank settings panes at equal match quality (files rank lower still).
			result.score = score + (entry.pane == nil ? 40 : 30)
			results.append(result)
		}
		return results
	}

	func find(id: String) -> Result? {
		lock.lock()
		defer { lock.unlock() }
		if id.hasPrefix("app:") {
			let path = String(id.dropFirst(4))
			if let entry = entries.first(where: { $0.path == path }) { return AppIndex.makeResult(entry) }
		} else if id.hasPrefix("pref:") {
			let pane = String(id.dropFirst(5))
			if let entry = entries.first(where: { $0.pane == pane }) { return AppIndex.makeResult(entry) }
		}
		return nil
	}
}
