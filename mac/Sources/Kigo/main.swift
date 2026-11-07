// Kigo for macOS: a Spotlight and Raycast style launcher. Option+Space, type,
// Enter. Runs in the background with no Dock icon.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var controller: LauncherController!
	private var hotKey: HotKey!

	func applicationDidFinishLaunching(_ notification: Notification) {
		controller = LauncherController()
		hotKey = HotKey { [weak self] in self?.controller.toggle() }
		hotKey.register(Prefs.shared.shortcut)
		controller.onShortcutChanged = { [weak self] in self?.hotKey.register(Prefs.shared.shortcut) }
		Prefs.applyLoginItem(Prefs.shared.openAtLogin)

		// Say hello the first time; after that, start hidden (as at login).
		let arguments = CommandLine.arguments
		let firstRun = !UserDefaults.standard.bool(forKey: "launchedBefore")
		UserDefaults.standard.set(true, forKey: "launchedBefore")
		if arguments.contains("--settings") {
			controller.show(settings: true)
		} else if firstRun || arguments.contains("--show") {
			controller.show()
		}
		snapshotForTests()
	}

	// KIGO_SNAPSHOT=out.png [KIGO_QUERY=text] shows the launcher, types the
	// query and saves what the panel shows (out.png, out-settings.png).
	private func snapshotForTests() {
		let env = ProcessInfo.processInfo.environment
		guard let path = env["KIGO_SNAPSHOT"] else { return }
		controller.show()
		controller.model.query = env["KIGO_QUERY"] ?? ""
		DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) {
			self.controller.snapshot(to: path)
			self.controller.openSettings()
			DispatchQueue.main.asyncAfter(deadline: .now() + 1) {
				self.controller.snapshot(to: path.replacingOccurrences(of: ".png", with: "-settings.png"))
				NSApp.terminate(nil)
			}
		}
	}

	// Opening Kigo again (Finder, `open -a Kigo`) shows the launcher.
	func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
		controller.show()
		return false
	}
}

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
