// Your next video call, from Calendar: from 15 minutes before it starts until
// 10 minutes in, the suggestions lead with it, and Enter joins it in its app
// (a 2:00 Zoom call opened at 1:59 joins on Zoom).
import AppKit
import EventKit

enum MeetingService: CaseIterable {
	case zoom, meet, teams, webex, facetime

	var name: String {
		switch self {
		case .zoom: return "Zoom"
		case .meet: return "Google Meet"
		case .teams: return "Microsoft Teams"
		case .webex: return "Webex"
		case .facetime: return "FaceTime"
		}
	}

	/// The app that joins, newest first; Google Meet joins in the browser.
	var bundleIDs: [String] {
		switch self {
		case .zoom: return ["us.zoom.xos"]
		case .meet: return []
		case .teams: return ["com.microsoft.teams2", "com.microsoft.teams"]
		case .webex: return ["Cisco-Systems.Spark"]
		case .facetime: return ["com.apple.FaceTime"]
		}
	}

	var appURL: URL? {
		for id in bundleIDs {
			if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: id) { return url }
		}
		return nil
	}

	/// The service a meeting link belongs to.
	static func of(_ url: URL) -> MeetingService? {
		guard let host = url.host?.lowercased(), url.scheme?.lowercased().hasPrefix("http") == true else { return nil }
		let path = url.path.lowercased()
		func on(_ domain: String) -> Bool { host == domain || host.hasSuffix("." + domain) }
		if on("zoom.us") || on("zoomgov.com") {
			return ["/j/", "/my/", "/w/", "/s/"].contains { path.hasPrefix($0) } ? .zoom : nil
		}
		if host == "meet.google.com" { return path.count > 1 ? .meet : nil }
		if on("teams.microsoft.com") || on("teams.live.com") { return path.contains("meet") ? .teams : nil }
		if on("webex.com") { return .webex }
		if host == "facetime.apple.com" { return .facetime }
		return nil
	}

	/// The first meeting link in an event's URL, location and notes, in that order.
	static func link(in texts: [String?]) -> (MeetingService, URL)? {
		let detector = try? NSDataDetector(types: NSTextCheckingResult.CheckingType.link.rawValue)
		for text in texts.compactMap({ $0 }) where !text.isEmpty {
			let range = NSRange(text.startIndex..., in: text)
			for match in detector?.matches(in: text, range: range) ?? [] {
				if let url = match.url, let service = of(url) { return (service, url) }
			}
		}
		return nil
	}

	/// Opens a meeting link in its app.
	static func join(_ link: URL) -> Bool {
		let app = of(link)?.appURL
		return NSWorkspace.shared.open(of(link)?.joinURL(link, appInstalled: app != nil) ?? link)
	}

	/// The link to open: a Zoom link straight into the Zoom app (skipping the
	/// browser's "Open zoom.us?" page) when it's installed.
	func joinURL(_ link: URL, appInstalled: Bool) -> URL {
		guard self == .zoom, appInstalled,
			var parts = URLComponents(url: link, resolvingAgainstBaseURL: false),
			parts.path.hasPrefix("/j/")
		else { return link }
		let number = parts.path.dropFirst(3).split(separator: "/").first.map(String.init) ?? ""
		guard !number.isEmpty, number.allSatisfy(\.isNumber) else { return link }
		var query = [URLQueryItem(name: "action", value: "join"), URLQueryItem(name: "confno", value: number)]
		query += (parts.queryItems ?? []).filter { $0.name == "pwd" }
		parts.scheme = "zoommtg"
		parts.path = "/join"
		parts.queryItems = query
		return parts.url ?? link
	}
}

struct Meeting {
	var id: String
	var title: String
	var start: Date
	var end: Date
	var service: MeetingService
	var link: URL

	static let lead: TimeInterval = 15 * 60
	static let grace: TimeInterval = 10 * 60

	/// From 15 minutes before the start until 10 minutes in (and not over).
	func isDue(at now: Date) -> Bool {
		start.timeIntervalSince(now) <= Meeting.lead && now.timeIntervalSince(start) <= Meeting.grace && end > now
	}

	/// "2:00 PM, in 1 min", "2:00 PM, now", "2:00 PM, 3 min ago".
	func when(at now: Date) -> String {
		let time = start.formatted(date: .omitted, time: .shortened)
		let minutes = Int((start.timeIntervalSince(now) / 60).rounded())
		if minutes > 0 { return "\(time), in \(minutes) min" }
		if minutes < 0 { return "\(time), \(-minutes) min ago" }
		return "\(time), now"
	}

	func result(at now: Date) -> Result {
		Result(kind: .meeting, title: "Join \u{201C}\(title)\u{201D}",
			subtitle: "\(service.name) \u{00B7} \(when(at: now))", id: "meeting:" + id,
			payload: link.absoluteString, icon: service.appURL.map { Icons.forPath($0.path) } ?? Icons.browser)
	}
}

/// Today's video calls around now, read from Calendar in the background each
/// time the launcher opens, so opening it never waits on EventKit.
final class Meetings {
	private let store = EKEventStore()
	private var meetings: [Meeting] = []
	private let queue = DispatchQueue(label: "kigo.meetings")
	/// Set for a snapshot: shown instead of Calendar's.
	var fixed: [Meeting]?
	var onChange: (() -> Void)?

	static var authorized: Bool { EKEventStore.authorizationStatus(for: .event) == .fullAccess }
	static var denied: Bool {
		[.denied, .restricted].contains(EKEventStore.authorizationStatus(for: .event))
	}

	/// Asks for Calendar access the first time; macOS remembers the answer.
	func requestAccess(then done: @escaping () -> Void = {}) {
		guard EKEventStore.authorizationStatus(for: .event) == .notDetermined else { return done() }
		store.requestFullAccessToEvents { _, _ in
			DispatchQueue.main.async {
				self.refresh()
				done()
			}
		}
	}

	func refresh() {
		guard fixed == nil, Meetings.authorized else { return }
		queue.async { [store] in
			let now = Date()
			let predicate = store.predicateForEvents(withStart: now.addingTimeInterval(-3600),
				end: now.addingTimeInterval(3 * 3600), calendars: nil)
			let found: [Meeting] = store.events(matching: predicate).compactMap { event in
				guard !event.isAllDay, event.status != .canceled,
					event.attendees?.first(where: \.isCurrentUser)?.participantStatus != .declined,
					let (service, link) = MeetingService.link(in: [event.url?.absoluteString, event.location, event.notes])
				else { return nil }
				return Meeting(id: event.calendarItemIdentifier + "@\(Int(event.startDate.timeIntervalSince1970))",
					title: event.title ?? service.name, start: event.startDate, end: event.endDate,
					service: service, link: link)
			}
			DispatchQueue.main.async {
				self.meetings = found
				self.onChange?()
			}
		}
	}

	/// The due meetings, the one starting closest to now first.
	func due(at now: Date = Date()) -> [Meeting] {
		(fixed ?? meetings).filter { $0.isDue(at: now) }
			.sorted { abs($0.start.timeIntervalSince(now)) < abs($1.start.timeIntervalSince(now)) }
	}
}
