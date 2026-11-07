// Kigo as a Saddle Island plugin. Saddle Island (a Dynamic Island for the
// MacBook notch) has its own search on F4; with its Settings › Plugins › Kigo
// switch on, Kigo answers that search while the island draws it. Over
// IslandKit (a local socket, docs/IslandKit.md in Saddle Island's repo):
//
//   query   Saddle Island → Kigo   what the island's field reads now
//   results Kigo → Saddle Island   Kigo's rows for it, best first (again when
//                                  files arrive), or `close` after a pick
//   pick    Saddle Island → Kigo   Return (or ⌘Return) on one of the rows
//
// So the island looks like Saddle Island and ranks, opens and remembers like
// Kigo: the same model as Kigo's own panel, with its history, commands, links,
// shell and "press Return again". Saddle Island knows Kigo by its code
// signature, so only a Kigo signed by bluevisor's team is asked.
//
// When Saddle Island isn't running the client waits quietly (it retries,
// backing off to a minute, and at once when Saddle Island announces itself).
// Option+Space opens Kigo's own panel either way.
import AppKit
import Combine
import IslandKit

final class SaddleIslandLink {
	/// Rows the island shows; Kigo's fallbacks (web search, Terminal) always among them.
	static let rowLimit = 9

	private let client = IslandClient(name: "Kigo")
	private let controller: LauncherController
	private var model: LauncherModel { controller.model }
	/// The island's latest query, and whether its search is Kigo's right now
	/// (from a query until a pick closes it or Kigo's own panel opens).
	private var queryID = 0
	private var answering = false
	private var subscriptions: Set<AnyCancellable> = []

	init(controller: LauncherController) {
		self.controller = controller
		// Callbacks run on the main queue.
		client.onSearchQuery = { [weak self] query in self?.query(query) }
		client.onSearchPick = { [weak self] pick in self?.pick(pick) }
		// Files arrive after the first answer; send the rows again.
		model.$results.dropFirst().receive(on: DispatchQueue.main)
			.sink { [weak self] _ in self?.resultsChanged() }
			.store(in: &subscriptions)
		client.activate()
	}

	deinit { client.invalidate() }

	private func query(_ query: SearchProviderQuery) {
		if controller.isShowing { controller.hide() }
		queryID = query.id
		answering = true
		if query.text.isEmpty {
			// The island's search just opened (or was cleared): Kigo's suggestions.
			model.query = ""
			model.confirming = nil
			model.suggestionsHidden = false
			model.prepare()
		} else {
			model.query = query.text
		}
		send()
	}

	private func pick(_ pick: SearchProviderPick) {
		guard answering, pick.query == queryID,
			let index = model.results.firstIndex(where: { $0.id == pick.row })
		else { return NSSound.beep() }
		switch model.invoke(at: index, reveal: pick.how == .reveal, alternate: false) {
		case .hide:
			close()
		case .openSettings:
			close()
			controller.show(settings: true)
		case .stay:
			send() // "Press Return again"
		case .failed:
			NSSound.beep()
		}
	}

	private func resultsChanged() {
		guard answering, !controller.isShowing else { return answering = false }
		send()
	}

	private func close() {
		answering = false
		client.sendSearchResults(SearchProviderResults(query: queryID, close: true))
	}

	private func send() {
		client.sendSearchResults(SearchProviderResults(query: queryID, rows: Self.rows(model.results, confirming: model.confirming)))
	}

	/// Kigo's results as island rows: the best `rowLimit`, keeping the fallbacks last.
	static func rows(_ results: [Result], confirming: String?) -> [SearchProviderRow] {
		let isFallback: (Result) -> Bool = { $0.section.hasPrefix("Use \u{201C}") }
		let fallbacks = results.filter(isFallback)
		let kept = results.filter { !isFallback($0) }.prefix(max(0, rowLimit - fallbacks.count)) + fallbacks
		return kept.map { row($0, confirming: confirming == $0.id) }
	}

	static func row(_ result: Result, confirming: Bool) -> SearchProviderRow {
		var row = SearchProviderRow(id: result.id, title: result.title, subtitle: result.subtitle)
		if confirming { row.subtitle = "Press Return again to \(result.title.lowercased())" }
		row.copy = Actions.copyText(result)
		if result.canReveal { row.reveal = true }
		if result.kind == .calculator { row.answer = true }
		switch result.kind {
		case .app, .file, .folder: row.iconPath = result.path
		case .preference: row.iconPath = appPath("com.apple.systempreferences")
		case .calculator: row.iconPath = appPath("com.apple.calculator")
		case .shell: row.iconPath = appPath("com.apple.Terminal")
		case .url, .web: row.browser = true
		case .command: break
		}
		if row.iconPath == nil, row.browser == nil {
			if let symbol = result.symbol { row.symbol = symbol } else { row.iconPath = Bundle.main.bundlePath }
		}
		return row
	}

	private static func appPath(_ bundleID: String) -> String? {
		NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID)?.path
	}
}
