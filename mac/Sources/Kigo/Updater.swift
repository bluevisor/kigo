// Over-the-air updates from GitHub releases, like the Haiku app's: once a
// day (and from Check for Updates) it reads the latest release, downloads
// kigo-<version>-macos.zip, checks it's signed by the same developer as this
// copy, swaps it into place and restarts.
import AppKit

final class Updater {
	static let shared = Updater()

	private static let latest = URL(string: "https://api.github.com/repos/bluevisor/kigo/releases/latest")!
	private static let releases = URL(string: "https://github.com/bluevisor/kigo/releases")!
	private static let assetSuffix = "-macos.zip"
	private static let day: TimeInterval = 86400

	private var timer: Timer?
	private var checking = false

	var currentVersion: String {
		Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0"
	}

	/// Checks now if a day has passed, then every few hours after.
	func start() {
		checkIfDue()
		timer = Timer.scheduledTimer(withTimeInterval: 4 * 3600, repeats: true) { [weak self] _ in
			self?.checkIfDue()
		}
	}

	private func checkIfDue() {
		guard Prefs.shared.updates else { return }
		let last = UserDefaults.standard.double(forKey: "updateChecked")
		guard Date().timeIntervalSince1970 - last >= Updater.day else { return }
		check(manual: false)
	}

	/// `manual` reports every outcome; the daily check is silent unless it installs.
	func check(manual: Bool) {
		guard !checking else { return }
		checking = true
		UserDefaults.standard.set(Date().timeIntervalSince1970, forKey: "updateChecked")
		var request = URLRequest(url: Updater.latest, timeoutInterval: 30)
		request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
		URLSession.shared.dataTask(with: request) { data, _, _ in
			DispatchQueue.main.async {
				self.handleRelease(data, manual: manual)
			}
		}.resume()
	}

	private func handleRelease(_ data: Data?, manual: Bool) {
		guard let data,
			let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
			let tag = json["tag_name"] as? String else {
			finish(manual ? ("Can't check for updates", "Couldn't reach GitHub.") : nil)
			return
		}
		let version = tag.hasPrefix("v") ? String(tag.dropFirst()) : tag
		guard Updater.isNewer(version, than: currentVersion) else {
			finish(manual ? ("Kigo is up to date", "Kigo \(currentVersion) is the latest version.") : nil)
			return
		}
		let assets = json["assets"] as? [[String: Any]] ?? []
		let url = assets.compactMap { $0["browser_download_url"] as? String }
			.first(where: { $0.hasSuffix(Updater.assetSuffix) }).flatMap(URL.init(string:))
		// A development build, or a release without a Mac build: point at the page.
		guard let url, Bundle.main.bundlePath.hasSuffix(".app"),
			!Bundle.main.bundlePath.contains("/.build/") else {
			finish(nil)
			if manual { NSWorkspace.shared.open(Updater.releases) }
			return
		}
		URLSession.shared.downloadTask(with: url) { file, _, _ in
			// The temporary file goes away when this returns: move it first.
			let zip = FileManager.default.temporaryDirectory.appendingPathComponent("kigo-update.zip")
			try? FileManager.default.removeItem(at: zip)
			let moved = file.map { (try? FileManager.default.moveItem(at: $0, to: zip)) != nil } ?? false
			DispatchQueue.main.async {
				if moved {
					self.install(zip, version: version, manual: manual)
				} else {
					self.finish(manual ? ("Can't update Kigo", "The download failed.") : nil)
				}
			}
		}.resume()
	}

	private func install(_ zip: URL, version: String, manual: Bool) {
		let fm = FileManager.default
		let staging = fm.temporaryDirectory.appendingPathComponent("kigo-update", isDirectory: true)
		try? fm.removeItem(at: staging)
		try? fm.createDirectory(at: staging, withIntermediateDirectories: true)
		let fresh = staging.appendingPathComponent("Kigo.app")
		guard Updater.run("/usr/bin/ditto", ["-x", "-k", zip.path, staging.path]).status == 0,
			fm.fileExists(atPath: fresh.path) else {
			finish(manual ? ("Can't update Kigo", "The download wasn't a Kigo app.") : nil)
			return
		}
		// Same developer, intact signature: otherwise leave this copy alone.
		let ours = Updater.teamID(Bundle.main.bundlePath)
		guard Updater.run("/usr/bin/codesign", ["--verify", "--deep", "--strict", fresh.path]).status == 0,
			let theirs = Updater.teamID(fresh.path), theirs == ours else {
			finish(("Can't update Kigo", "The new version's signature didn't check out."))
			return
		}

		// A shell that outlives Kigo swaps the apps once Kigo has quit, then
		// starts the new one, hidden.
		let app = Bundle.main.bundlePath
		let script = """
			while kill -0 \(ProcessInfo.processInfo.processIdentifier) 2>/dev/null; do sleep 0.2; done
			rm -rf "\(app).old"
			mv "\(app)" "\(app).old" && mv "\(fresh.path)" "\(app)" && rm -rf "\(app).old"
			[ -d "\(app)" ] || mv "\(app).old" "\(app)"
			rm -rf "\(staging.path)" "\(zip.path)"
			open -g "\(app)" --args --updated
			"""
		let process = Process()
		process.executableURL = URL(fileURLWithPath: "/bin/sh")
		process.arguments = ["-c", script]
		do {
			try process.run()
		} catch {
			finish(("Can't update Kigo", "Couldn't start the installer."))
			return
		}
		NSLog("Kigo: updating \(currentVersion) -> \(version)")
		NSApp.terminate(nil)
	}

	private func finish(_ message: (String, String)?) {
		checking = false
		guard let (title, text) = message else { return }
		let alert = NSAlert()
		alert.messageText = title
		alert.informativeText = text
		NSApp.activate(ignoringOtherApps: true)
		alert.runModal()
	}

	/// Whether dotted version `a` is past `b`.
	static func isNewer(_ a: String, than b: String) -> Bool {
		let x = a.split(separator: ".").map { Int($0) ?? 0 }
		let y = b.split(separator: ".").map { Int($0) ?? 0 }
		for i in 0..<max(x.count, y.count) {
			let p = i < x.count ? x[i] : 0, q = i < y.count ? y[i] : 0
			if p != q { return p > q }
		}
		return false
	}

	private static func teamID(_ path: String) -> String? {
		let output = run("/usr/bin/codesign", ["-dv", "--verbose=2", path]).output
		for line in output.split(separator: "\n") where line.hasPrefix("TeamIdentifier=") {
			let id = String(line.dropFirst("TeamIdentifier=".count))
			return id == "not set" ? nil : id
		}
		return nil
	}

	@discardableResult
	private static func run(_ tool: String, _ arguments: [String]) -> (status: Int32, output: String) {
		let process = Process()
		process.executableURL = URL(fileURLWithPath: tool)
		process.arguments = arguments
		let pipe = Pipe()
		process.standardOutput = pipe
		process.standardError = pipe
		guard (try? process.run()) != nil else { return (-1, "") }
		let data = pipe.fileHandleForReading.readDataToEndOfFile()
		process.waitUntilExit()
		return (process.terminationStatus, String(decoding: data, as: UTF8.self))
	}
}
