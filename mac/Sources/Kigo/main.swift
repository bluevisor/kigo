// Kigo for macOS: a Spotlight and Raycast style launcher. Option+Space, type,
// Enter. Runs in the background with no Dock icon.
import AppKit

final class AppDelegate: NSObject, NSApplicationDelegate {
	private var controller: LauncherController!
	private var hotKey: HotKey!
	/// F4, when Saddle Island hands it over (SaddleIsland.swift).
	private var saddleIsland: SaddleIslandLink?

	func applicationDidFinishLaunching(_ notification: Notification) {
		controller = LauncherController()
		hotKey = HotKey { [weak self] in self?.controller.toggle() }
		controller.onShortcutChanged = { [weak self] in self?.updateHotKey() }
		updateHotKey()
		if ProcessInfo.processInfo.environment["KIGO_SNAPSHOT"] == nil {
			saddleIsland = SaddleIslandLink { [weak self] in self?.controller.toggle() }
		}
		NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
			object: nil, queue: .main) { [weak self] _ in self?.updateHotKey() }
		Prefs.applyLoginItem(Prefs.shared.openAtLogin)
		Updater.shared.start()

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
	// query and saves what the panel shows (out.png, out-settings.png), without
	// taking the keyboard.
	private func snapshotForTests() {
		let env = ProcessInfo.processInfo.environment
		guard let path = env["KIGO_SNAPSHOT"] else { return }
		controller.passive = true
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

	/// Apps showing another computer's screen. While one is in front Kigo lets
	/// go of its shortcut, so Option+Space reaches the Kigo on that machine
	/// (Beam to Linux, UTM to Haiku) instead of opening this one.
	private static let remoteScreens: Set<String> = [
		"dev.bluevisor.beam", "com.utmapp.UTM", "com.apple.ScreenSharing",
		"com.parallels.desktop.console", "com.vmware.fusion", "com.microsoft.rdc.macos",
		"com.p5sys.jump.mac.viewer", "com.realvnc.vncviewer",
	]

	private func updateHotKey() {
		let front = NSWorkspace.shared.frontmostApplication?.bundleIdentifier ?? ""
		if AppDelegate.remoteScreens.contains(front) {
			hotKey.unregister()
		} else {
			hotKey.register(Prefs.shared.shortcut)
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
