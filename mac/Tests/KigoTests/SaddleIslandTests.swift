// Kigo's results as Saddle Island's search rows.
import XCTest
@testable import Kigo

final class SaddleIslandTests: XCTestCase {
	private func app(_ name: String) -> Result {
		Result(kind: .app, title: name, subtitle: "/Applications", id: "app:/Applications/\(name).app",
			section: "Applications", path: "/Applications/\(name).app")
	}

	/// At most nine rows, and the fallbacks (web, Terminal) always make it.
	func testKeepsTheFallbacks() {
		var results = (1...12).map { app("App\($0)") }
		results.append(Result(kind: .web, title: "Search the web", id: "web", section: "Use \u{201C}a\u{201D} with…", payload: "https://x"))
		results.append(Result(kind: .shell, title: "Run \u{201C}a\u{201D}", id: "shell", section: "Use \u{201C}a\u{201D} with…", payload: "a"))
		let rows = SaddleIslandLink.rows(results, confirming: nil)
		XCTAssertEqual(rows.count, SaddleIslandLink.rowLimit)
		XCTAssertEqual(rows.suffix(2).map(\.id), ["web", "shell"])
		XCTAssertEqual(rows.first?.iconPath, "/Applications/App1.app")
		XCTAssertEqual(rows.first?.reveal, true)
		XCTAssertEqual(rows.first?.copy, "/Applications/App1.app")
		XCTAssertEqual(rows[7].browser, true)
	}

	func testCalculatorIsAnAnswerAndCommandsKeepTheirSymbol() {
		let calc = Result(kind: .calculator, title: "= 4", subtitle: "2+2", id: "calc", payload: "4")
		let row = SaddleIslandLink.row(calc, confirming: false)
		XCTAssertEqual(row.answer, true)
		XCTAssertEqual(row.copy, "4")
		XCTAssertNil(row.reveal)

		let restart = Result(kind: .command, title: "Restart", subtitle: "System", id: "cmd:restart",
			payload: "restart", needsConfirm: true, symbol: "power")
		XCTAssertEqual(SaddleIslandLink.row(restart, confirming: false).symbol, "power")
		XCTAssertEqual(SaddleIslandLink.row(restart, confirming: true).subtitle, "Press Return again to restart")
	}
}
