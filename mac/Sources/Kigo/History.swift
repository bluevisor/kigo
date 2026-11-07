// What you opened and when, for frecency ranking and suggestions. Same file
// format as the Haiku app: one item per line, count<TAB>last-used<TAB>id<TAB>title.
import Foundation

final class History {
	private struct Item {
		var count: Int
		var lastUsed: TimeInterval
		var title: String
	}

	private static let maxItems = 300
	private var items: [String: Item] = [:]

	private var url: URL {
		let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
			.appendingPathComponent("Kigo", isDirectory: true)
		try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
		return dir.appendingPathComponent("history")
	}

	func load() {
		items = [:]
		guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
		for line in text.split(separator: "\n") {
			let parts = line.split(separator: "\t", maxSplits: 3, omittingEmptySubsequences: false)
			guard parts.count == 4, let count = Int(parts[0]), let used = Double(parts[1]) else { continue }
			items[String(parts[2])] = Item(count: count, lastUsed: used, title: String(parts[3]))
		}
	}

	func save() {
		let text = items.map { "\($0.value.count)\t\(Int($0.value.lastUsed))\t\($0.key)\t\($0.value.title)\n" }
			.joined()
		try? text.write(to: url, atomically: true, encoding: .utf8)
	}

	func clear() {
		items = [:]
		save()
	}

	private func frecency(_ item: Item, _ now: TimeInterval) -> Double {
		let days = max(0, (now - item.lastUsed) / 86400)
		// Recent use counts for more; a week-old launch is worth about half.
		return log2(1 + Double(item.count)) / (1 + days / 7)
	}

	func record(_ id: String, title: String) {
		var item = items[id] ?? Item(count: 0, lastUsed: 0, title: title)
		item.count += 1
		item.lastUsed = Date().timeIntervalSince1970
		item.title = title
		items[id] = item
		if items.count > History.maxItems {
			// Forget the stalest entry.
			let now = Date().timeIntervalSince1970
			if let worst = items.min(by: { frecency($0.value, now) < frecency($1.value, now) }) {
				items.removeValue(forKey: worst.key)
			}
		}
		save()
	}

	/// Bonus added to a result's match score.
	func boost(_ id: String) -> Double {
		guard let item = items[id] else { return 0 }
		return frecency(item, Date().timeIntervalSince1970) * 60
	}

	/// Ids by frecency, best first.
	func top(_ count: Int) -> [String] {
		let now = Date().timeIntervalSince1970
		return items.sorted { frecency($0.value, now) > frecency($1.value, now) }
			.prefix(count).map(\.key)
	}
}
