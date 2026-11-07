// What the launcher shows: the query, the ranked results, the selection.
import AppKit

final class LauncherModel: ObservableObject {
	static let maxApps = 8
	static let maxCommands = 4
	static let maxFiles = 8
	static let topHitScore = 700.0

	@Published var query = "" { didSet { if query != oldValue { queryChanged() } } }
	@Published private(set) var results: [Result] = []
	@Published var selection = 0
	/// The result waiting for a second Enter (Restart, Shut Down…).
	@Published var confirming: String?
	@Published var settingsOpen = false
	/// The settings page's natural height, measured by SwiftUI.
	@Published var settingsHeight: CGFloat = 0
	/// Bumped to put the caret back in the field.
	@Published var focusToken = 0

	let apps = AppIndex()
	let history = History()
	private let files = FileSearch()
	private var fileResults: [Result] = []
	private let prefs = Prefs.shared

	init() {
		history.load()
		apps.rebuild { [weak self] in self?.update(keepSelection: true) }
		files.onResults = { [weak self] text, results in
			guard let self, text == self.query else { return }
			self.fileResults = results
			self.update(keepSelection: true)
		}
		NotificationCenter.default.addObserver(forName: .kigoReindex, object: nil, queue: .main) { [weak self] _ in
			self?.apps.rebuild { self?.update(keepSelection: true) }
		}
	}

	var selected: Result? { results.indices.contains(selection) ? results[selection] : nil }

	/// Called each time the launcher opens.
	func prepare() {
		apps.refreshIfNeeded { [weak self] in self?.update(keepSelection: true) }
		update(keepSelection: false)
	}

	private func queryChanged() {
		confirming = nil
		fileResults = []
		if prefs.searchFiles && !query.hasPrefix(">") { files.start(query) } else { files.cancel() }
		update(keepSelection: false)
	}

	func move(_ delta: Int) {
		guard !results.isEmpty else { return }
		selection = max(0, min(results.count - 1, selection + delta))
		confirming = nil
	}

	func update(keepSelection: Bool) {
		// Late results (files, a rescan) keep a row you moved to; from the top,
		// the selection stays on the best match.
		let previous = keepSelection && selection > 0 ? selected?.id : nil
		let query = self.query.trimmingCharacters(in: .whitespaces)
		var list: [Result] = []

		if query.isEmpty {
			if prefs.suggestions { list = suggestions() }
		} else if query.hasPrefix(">") {
			// "> command" runs a shell command in Terminal.
			let command = query.dropFirst().trimmingCharacters(in: .whitespaces)
			if !command.isEmpty {
				list.append(Result(kind: .shell, title: command, subtitle: "Run in Terminal", id: "shell",
					section: "Terminal", payload: command, icon: Icons.app("com.apple.Terminal")))
			}
		} else {
			if prefs.calculator, let value = calculate(query) {
				list.append(Result(kind: .calculator, title: "= " + value, subtitle: query, id: "calc",
					section: "Calculator", payload: value, icon: Icons.app("com.apple.calculator")))
			}
			if let url = urlFor(query) {
				list.append(Result(kind: .url, title: "Open " + query, subtitle: url, id: "url",
					section: "Link", payload: url, icon: Icons.browser))
			}

			var groups: [[Result]] = [
				apps.search(query, includeApps: prefs.searchApps),
				// Kigo Settings stays findable with commands off.
				searchCommands(query, all: prefs.searchCommands),
				prefs.searchFiles ? fileResults : [],
			]
			for g in groups.indices {
				for r in groups[g].indices { groups[g][r].score += history.boost(groups[g][r].id) }
			}

			// Top Hit: the single best match across kinds, Spotlight-style.
			var best: (Int, Int)?
			for g in groups.indices {
				for r in groups[g].indices where groups[g][r].score >= LauncherModel.topHitScore {
					if best == nil || groups[g][r].score > groups[best!.0][best!.1].score { best = (g, r) }
				}
			}
			if let (g, r) = best {
				var top = groups[g].remove(at: r)
				top.section = "Top Hit"
				list.append(top)
			}

			let sections = ["Applications", "Commands", "Files"]
			let limits = [LauncherModel.maxApps, LauncherModel.maxCommands, LauncherModel.maxFiles]
			for g in groups.indices {
				let sorted = groups[g].enumerated().sorted {
					$0.element.score != $1.element.score ? $0.element.score > $1.element.score : $0.offset < $1.offset
				}
				for (_, var result) in sorted.prefix(limits[g]) {
					result.section = sections[g]
					list.append(result)
				}
			}

			// Fallbacks, always last: search the web, or run it as a command.
			let fallbacks = "Use \u{201C}\(query)\u{201D} with…"
			if let url = prefs.webSearch.url(for: query) {
				list.append(Result(kind: .web, title: "Search the web for \u{201C}\(query)\u{201D}",
					subtitle: prefs.webSearch.name, id: "web", section: fallbacks, payload: url,
					icon: Icons.browser))
			}
			list.append(Result(kind: .shell, title: "Run \u{201C}\(query)\u{201D}",
				subtitle: "in Terminal (or type > first)", id: "shell", section: fallbacks, payload: query,
				icon: Icons.app("com.apple.Terminal")))
		}

		results = list
		selection = previous.flatMap { id in list.firstIndex(where: { $0.id == id }) } ?? 0
	}

	private func suggestions() -> [Result] {
		var list: [Result] = []
		for id in history.top(8) {
			var result: Result?
			if id.hasPrefix("app:") || id.hasPrefix("pref:") {
				result = apps.find(id: id)
			} else if id.hasPrefix("file:") {
				let path = String(id.dropFirst(5))
				var isDirectory: ObjCBool = false
				if FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory) {
					result = Result(kind: isDirectory.boolValue ? .folder : .file,
						title: (path as NSString).lastPathComponent,
						subtitle: (path as NSString).deletingLastPathComponent
							.replacingOccurrences(of: NSHomeDirectory(), with: "~"),
						id: id, path: path, icon: Icons.forPath(path))
				}
			} else {
				result = command(forId: id)
			}
			if var result {
				result.section = "Suggestions"
				list.append(result)
			}
		}
		return list
	}

	// Actions ---------------------------------------------------------------

	enum Outcome { case stay, hide, openSettings, failed }

	/// Enter on the selection. `reveal` (⌘ or ⌥) shows it in Finder,
	/// `alternate` (⇧) opens a new instance.
	func invoke(at index: Int? = nil, reveal: Bool, alternate: Bool) -> Outcome {
		let index = index ?? selection
		guard results.indices.contains(index) else { return .failed }
		let result = results[index]

		if reveal {
			guard result.canReveal else { return .failed }
			return Actions.reveal(result) ? .hide : .failed
		}

		// Restart, Shut Down, Log Out and Empty Trash ask twice, like Raycast.
		if result.needsConfirm && confirming != result.id {
			selection = index
			confirming = result.id
			return .stay
		}

		if result.kind == .command && result.payload == "settings" {
			history.record(result.id, title: result.title)
			query = ""
			return .openSettings
		}

		guard Actions.open(result, alternate: alternate) else { return .failed }
		let remember: Bool
		switch result.kind {
		case .app, .preference, .file, .folder: remember = true
		case .command: remember = result.payload != "quit"
		default: remember = false
		}
		if remember { history.record(result.id, title: result.title) }
		query = ""
		return .hide
	}

	func copySelection() -> Bool {
		guard let result = selected, let text = Actions.copyText(result) else { return false }
		Actions.copy(text)
		return true
	}

	/// Tab completes the selected title, like a shell.
	func complete() {
		guard let result = selected, ![.calculator, .web, .shell, .url].contains(result.kind) else { return }
		query = result.title
		focusToken += 1
	}
}
