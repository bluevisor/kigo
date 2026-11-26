// What you opened, when and where, for frecency ranking and suggestions. Same
// file format as the Haiku app, one item per line,
// count<TAB>last-used<TAB>id<TAB>title, plus a fifth field on the Mac: the
// latest launches as time@place, comma-separated. An older Kigo reads that
// field as part of the title, which nothing shows.
import CryptoKit
import Foundation
import SystemConfiguration

/// One launch: when (in local time) and on which network.
struct Launch {
	var time: TimeInterval
	/// `Place.current()` then: a short hash of the network, "" when offline.
	var place: String
	/// Local minute of the day, and whether it was a Saturday or Sunday.
	let minute: Int
	let weekend: Bool

	init(time: TimeInterval, place: String, calendar: Calendar = .current) {
		self.time = time
		self.place = place
		let date = Date(timeIntervalSince1970: time)
		let parts = calendar.dateComponents([.hour, .minute], from: date)
		minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
		weekend = calendar.isDateInWeekend(date)
	}
}

/// Where you are, as far as Kigo can tell without asking for Location: the
/// network you're on. macOS keeps a signature of it (the router's IP and
/// hardware address); Kigo keeps only a hash of that.
enum Place {
	static func current() -> String {
		guard let store = SCDynamicStoreCreate(nil, "Kigo" as CFString, nil, nil),
			let global = SCDynamicStoreCopyValue(store, "State:/Network/Global/IPv4" as CFString) as? [String: Any],
			let service = global["PrimaryService"] as? String
		else { return "" }
		for family in ["IPv4", "IPv6"] {
			let key = "State:/Network/Service/\(service)/\(family)" as CFString
			if let value = SCDynamicStoreCopyValue(store, key) as? [String: Any],
				let signature = value["NetworkSignature"] as? String, !signature.isEmpty {
				return hash(signature)
			}
		}
		return ""
	}

	static func hash(_ signature: String) -> String {
		SHA256.hash(data: Data(signature.utf8)).prefix(4).map { String(format: "%02x", $0) }.joined()
	}
}

final class History {
	private struct Item {
		var count: Int
		var lastUsed: TimeInterval
		var title: String
		/// Newest last, at most `maxLaunches`.
		var launches: [Launch] = []
	}

	private static let maxItems = 300
	private static let maxLaunches = 16
	private var items: [String: Item] = [:]
	private let url: URL

	init(url: URL? = nil) {
		if let url {
			self.url = url
		} else {
			let dir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
				.appendingPathComponent("Kigo", isDirectory: true)
			try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
			self.url = dir.appendingPathComponent("history")
		}
	}

	func load() {
		items = [:]
		guard let text = try? String(contentsOf: url, encoding: .utf8) else { return }
		for line in text.split(separator: "\n") {
			let parts = line.split(separator: "\t", maxSplits: 4, omittingEmptySubsequences: false)
			guard parts.count >= 4, let count = Int(parts[0]), let used = Double(parts[1]) else { continue }
			var item = Item(count: count, lastUsed: used, title: String(parts[3]))
			if parts.count == 5 {
				item.launches = parts[4].split(separator: ",").compactMap { entry in
					let pair = entry.split(separator: "@", maxSplits: 1, omittingEmptySubsequences: false)
					guard let time = Double(pair[0]) else { return nil }
					return Launch(time: time, place: pair.count > 1 ? String(pair[1]) : "")
				}
			}
			items[String(parts[2])] = item
		}
	}

	func save() {
		let text = items.map { id, item in
			let launches = item.launches.map { "\(Int($0.time))@\($0.place)" }.joined(separator: ",")
			return "\(item.count)\t\(Int(item.lastUsed))\t\(id)\t\(item.title)\t\(launches)\n"
		}.joined()
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

	func record(_ id: String, title: String, at now: Date = Date(), place: String = Place.current()) {
		let time = now.timeIntervalSince1970
		var item = items[id] ?? Item(count: 0, lastUsed: 0, title: title)
		item.count += 1
		item.lastUsed = time
		item.title = title
		item.launches.append(Launch(time: time, place: place))
		if item.launches.count > History.maxLaunches { item.launches.removeFirst() }
		items[id] = item
		if items.count > History.maxItems {
			// Forget the stalest entry.
			if let worst = items.min(by: { frecency($0.value, time) < frecency($1.value, time) }) {
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

	/// How well past launches fit this moment, about 0.1 (never at this time,
	/// always somewhere else) to 3 (always at this hour, on this network); 0.7
	/// for an item opened before Kigo kept launches.
	///
	/// Time: each launch counts fully at this exact minute of the day, fading
	/// to nothing 90 minutes away, and half as much on the other kind of day
	/// (weekday or weekend). Place: the share of launches on this network;
	/// neutral when either side is unknown.
	static func fit(_ launches: [Launch], minute: Int, weekend: Bool, place: String) -> Double {
		var near = 0.0
		for launch in launches {
			let apart = abs(launch.minute - minute)
			let distance = Double(min(apart, 1440 - apart))
			let closeness = max(0, 1 - distance / 90)
			near += launch.weekend == weekend ? closeness : closeness / 2
		}
		let time = (near + 0.25) / Double(launches.count + 1)

		let known = launches.filter { !$0.place.isEmpty }
		var here = 0.5
		if !place.isEmpty, !known.isEmpty {
			here = (Double(known.filter { $0.place == place }.count) + 0.5) / Double(known.count + 1)
		}
		return (0.3 + 1.7 * time) * (0.4 + 1.2 * here)
	}

	/// Ids for suggestions, best first: frecency weighted by how well each
	/// fits the time of day and the network you're on now.
	func top(_ count: Int, at now: Date = Date(), place: String = Place.current(),
		calendar: Calendar = .current) -> [String] {
		let time = now.timeIntervalSince1970
		let parts = calendar.dateComponents([.hour, .minute], from: now)
		let minute = (parts.hour ?? 0) * 60 + (parts.minute ?? 0)
		let weekend = calendar.isDateInWeekend(now)
		let scored = items.map { id, item in
			(id, frecency(item, time) * History.fit(item.launches, minute: minute, weekend: weekend, place: place))
		}
		return scored.sorted { $0.1 != $1.1 ? $0.1 > $1.1 : $0.0 < $1.0 }.prefix(count).map(\.0)
	}
}
