// Files and folders by name, through Spotlight's index (no crawler), scored
// with the same fuzzy matcher as everything else.
import Foundation

final class FileSearch: NSObject {
	private static let maxResults = 24
	private static let maxScanned = 3000

	var onResults: ((String, [Result]) -> Void)?
	private var query: NSMetadataQuery?
	private var queryText = ""
	private var pending: DispatchWorkItem?

	func start(_ text: String) {
		cancel()
		let trimmed = text.trimmingCharacters(in: .whitespaces)
		guard trimmed.count >= 2 else {
			onResults?(text, [])
			return
		}
		// Wait for a pause in typing.
		let work = DispatchWorkItem { [weak self] in self?.run(text, trimmed) }
		pending = work
		DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
	}

	func cancel() {
		pending?.cancel()
		pending = nil
		if let query {
			query.stop()
			NotificationCenter.default.removeObserver(self, name: .NSMetadataQueryDidFinishGathering, object: query)
		}
		query = nil
	}

	private func run(_ text: String, _ trimmed: String) {
		// Spotlight narrows by the longest word; fuzzy scoring does the rest.
		let words = trimmed.split(separator: " " as Character)
		let word = words.max(by: { $0.count < $1.count }).map(String.init) ?? trimmed
		let query = NSMetadataQuery()
		query.predicate = NSPredicate(format: "%K CONTAINS[cd] %@", NSMetadataItemFSNameKey, word)
		query.searchScopes = [NSMetadataQueryUserHomeScope]
		NotificationCenter.default.addObserver(self, selector: #selector(finished(_:)),
			name: .NSMetadataQueryDidFinishGathering, object: query)
		self.query = query
		queryText = text
		query.start()
	}

	@objc private func finished(_ note: Notification) {
		guard let query = note.object as? NSMetadataQuery, query === self.query else { return }
		query.disableUpdates()
		let home = NSHomeDirectory()
		let count = min(query.resultCount, FileSearch.maxScanned)
		var hits: [(Double, String)] = []
		for i in 0..<count {
			guard let item = query.result(at: i) as? NSMetadataItem,
				let path = item.value(forAttribute: NSMetadataItemPathKey) as? String else { continue }
			if FileSearch.hidden(path, home: home) { continue }
			let name = (path as NSString).lastPathComponent
			let score = FileSearch.score(queryText, name: name, path: path, home: home)
			if score > 0 { hits.append((score, path)) }
		}
		cancel()
		hits.sort { $0.0 > $1.0 }
		var results: [Result] = []
		for (score, path) in hits.prefix(FileSearch.maxResults) {
			var isDirectory: ObjCBool = false
			FileManager.default.fileExists(atPath: path, isDirectory: &isDirectory)
			let parent = (path as NSString).deletingLastPathComponent
			results.append(Result(kind: isDirectory.boolValue ? .folder : .file,
				title: (path as NSString).lastPathComponent,
				subtitle: parent.replacingOccurrences(of: home, with: "~"),
				id: "file:" + path, path: path, score: score, icon: Icons.forPath(path)))
		}
		onResults?(queryText, results)
	}

	// Library, dot folders, app bundles' insides and build trees are noise.
	private static func hidden(_ path: String, home: String) -> Bool {
		if path.hasPrefix(home + "/Library/") { return true }
		for part in ["/.", "/node_modules/", ".app/", "/build/", "/DerivedData/", "/Pods/"]
			where path.contains(part) { return true }
		return path.hasSuffix(".app")
	}

	private static func score(_ query: String, name: String, path: String, home: String) -> Double {
		var score = fuzzyScore(query, name)
		if score <= 0 { return 0 }
		// Below apps and commands, and documents near home beat deep paths.
		score *= 0.75
		if path.hasPrefix(home + "/") { score += 15 }
		if path.hasPrefix(home + "/Desktop/") || path.hasPrefix(home + "/Downloads/") { score += 10 }
		let depth = path.split(separator: "/").count - home.split(separator: "/").count
		return score - Double(max(depth, 0)) * 2
	}
}
