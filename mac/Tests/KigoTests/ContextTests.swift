// Suggestions follow the time of day, the network and Calendar.
import XCTest
@testable import Kigo

final class ContextTests: XCTestCase {
	/// Launches take the local time zone, as in the app.
	private let calendar = Calendar.current

	/// Wednesday Nov 25 2026 (or another day around it) at hour:minute, local time.
	private func date(day: Int = 25, _ hour: Int, _ minute: Int = 0) -> Date {
		calendar.date(from: DateComponents(year: 2026, month: 11, day: day, hour: hour, minute: minute))!
	}

	private func history() -> History {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("kigo-history-\(UUID().uuidString)")
		addTeardownBlock { try? FileManager.default.removeItem(at: url) }
		return History(url: url)
	}

	func testTimeOfDay() {
		let h = history()
		// Mail all day, more often; Zoom only around 2 PM.
		for day in 16...24 {
			for hour in [8, 10, 12, 16, 18] { h.record("app:Mail", title: "Mail", at: date(day: day, hour), place: "") }
			h.record("app:Zoom", title: "Zoom", at: date(day: day, 13, 58), place: "")
		}
		XCTAssertEqual(h.top(1, at: date(14), place: "", calendar: calendar), ["app:Zoom"])
		XCTAssertEqual(h.top(1, at: date(9), place: "", calendar: calendar), ["app:Mail"])
	}

	func testPlace() {
		let h = history()
		for day in 16...24 {
			h.record("app:Xcode", title: "Xcode", at: date(day: day, 10), place: "office")
			h.record("app:Music", title: "Music", at: date(day: day, 10), place: "home")
		}
		XCTAssertEqual(h.top(1, at: date(10), place: "office", calendar: calendar), ["app:Xcode"])
		XCTAssertEqual(h.top(1, at: date(10), place: "home", calendar: calendar), ["app:Music"])
	}

	func testHistoryFile() {
		let url = FileManager.default.temporaryDirectory.appendingPathComponent("kigo-history-\(UUID().uuidString)")
		defer { try? FileManager.default.removeItem(at: url) }
		// An entry from before launches were kept still loads.
		try! "3\t1700000000\tapp:/Old.app\tOld\n".write(to: url, atomically: true, encoding: .utf8)
		let h = History(url: url)
		h.load()
		h.record("app:/New.app", title: "New", at: date(14), place: "ab12cd34")
		let again = History(url: url)
		again.load()
		XCTAssertEqual(Set(again.top(5, at: date(14), place: "ab12cd34", calendar: calendar)),
			["app:/Old.app", "app:/New.app"])
		let text = try! String(contentsOf: url, encoding: .utf8)
		XCTAssertTrue(text.contains("\tNew\t\(Int(date(14).timeIntervalSince1970))@ab12cd34\n"))
		XCTAssertTrue(text.contains("\tOld\t\n"))
	}

	func testFit() {
		let at2 = (0..<5).map { Launch(time: date(day: 16 + $0, 14).timeIntervalSince1970, place: "home", calendar: calendar) }
		let now = 14 * 60
		XCTAssertGreaterThan(History.fit(at2, minute: now, weekend: false, place: "home"), 2.5)
		XCTAssertLessThan(History.fit(at2, minute: now, weekend: false, place: "work"), 1)
		XCTAssertLessThan(History.fit(at2, minute: 9 * 60, weekend: false, place: "home"), 0.6)
		// Midnight wraps around: 11:50 PM is close to 12:10 AM.
		let late = [Launch(time: date(23, 50).timeIntervalSince1970, place: "", calendar: calendar)]
		XCTAssertGreaterThan(History.fit(late, minute: 10, weekend: false, place: ""),
			History.fit(late, minute: 12 * 60, weekend: false, place: ""))
		XCTAssertEqual(History.fit([], minute: now, weekend: false, place: "home"), 0.725, accuracy: 0.001)
	}

	func testMeetingLinks() {
		func service(_ texts: [String?]) -> MeetingService? { MeetingService.link(in: texts)?.0 }
		XCTAssertEqual(service([nil, "https://us02web.zoom.us/j/81234567890?pwd=abc", nil]), .zoom)
		XCTAssertEqual(service([nil, "Room 4", "Join: https://meet.google.com/abc-defg-hij"]), .meet)
		XCTAssertEqual(service([nil, nil,
			"Microsoft Teams meeting https://teams.microsoft.com/l/meetup-join/19%3ameeting_x%40thread.v2/0"]), .teams)
		XCTAssertEqual(service(["https://acme.webex.com/meet/jane"]), .webex)
		XCTAssertEqual(service([nil, "https://facetime.apple.com/join#v=1&p=xyz"]), .facetime)
		XCTAssertNil(service([nil, "https://zoom.us/pricing", "https://example.com"]))
		XCTAssertNil(service([nil, "Conference Room B", nil]))
		// The event's own URL wins over the notes.
		XCTAssertEqual(service(["https://zoom.us/j/1", nil, "https://meet.google.com/abc-defg-hij"]), .zoom)
	}

	func testZoomOpensInTheApp() {
		let link = URL(string: "https://us02web.zoom.us/j/81234567890?pwd=abc.1&from=addon")!
		XCTAssertEqual(MeetingService.zoom.joinURL(link, appInstalled: true).absoluteString,
			"zoommtg://us02web.zoom.us/join?action=join&confno=81234567890&pwd=abc.1")
		XCTAssertEqual(MeetingService.zoom.joinURL(link, appInstalled: false), link)
		let personal = URL(string: "https://zoom.us/my/jane")!
		XCTAssertEqual(MeetingService.zoom.joinURL(personal, appInstalled: true), personal)
	}

	func testMeetingWindow() {
		let start = date(14)
		let meeting = Meeting(id: "1", title: "Sync", start: start, end: date(14, 30), service: .zoom,
			link: URL(string: "https://zoom.us/j/1")!)
		XCTAssertTrue(meeting.isDue(at: date(13, 59)))		// the example: opened at 1:59
		XCTAssertTrue(meeting.isDue(at: date(13, 45)))
		XCTAssertFalse(meeting.isDue(at: date(13, 44)))
		XCTAssertTrue(meeting.isDue(at: date(14, 10)))
		XCTAssertFalse(meeting.isDue(at: date(14, 11)))
		let short = Meeting(id: "2", title: "Check-in", start: start, end: date(14, 5), service: .zoom,
			link: URL(string: "https://zoom.us/j/1")!)
		XCTAssertFalse(short.isDue(at: date(14, 6)))		// over
		XCTAssertTrue(meeting.when(at: date(13, 59)).hasSuffix(", in 1 min"))
		XCTAssertTrue(meeting.when(at: date(14, 3)).hasSuffix(", 3 min ago"))
	}
}
