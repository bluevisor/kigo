// The ported matcher and calculator behave like the Haiku originals.
import XCTest
@testable import Kigo

final class CoreTests: XCTestCase {
	func testFuzzyOrder() {
		XCTAssertEqual(fuzzyScore("safari", "Safari"), 1000)
		let prefix = fuzzyScore("saf", "Safari")
		let wordStart = fuzzyScore("studio", "Visual Studio Code")
		let acronym = fuzzyScore("vsc", "Visual Studio Code")
		let substring = fuzzyScore("ari", "Safari")
		let subsequence = fuzzyScore("sfr", "Safari")
		XCTAssertGreaterThan(prefix, wordStart)
		XCTAssertGreaterThan(wordStart, acronym)
		XCTAssertGreaterThan(acronym, substring)
		XCTAssertGreaterThan(substring, subsequence)
		XCTAssertGreaterThan(subsequence, 0)
		XCTAssertEqual(fuzzyScore("xyz", "Safari"), 0)
		XCTAssertGreaterThan(fuzzyScore("sys set", "System Settings"), 0)
		XCTAssertEqual(fuzzyScore("sys xyz", "System Settings"), 0)
		XCTAssertGreaterThan(fuzzyScore("pos", "WebPositive"), 700)
	}

	func testCalculator() {
		XCTAssertEqual(calculate("2+2"), "4")
		XCTAssertEqual(calculate("sqrt(2)*10^3"), "1414.213562")
		XCTAssertEqual(calculate("= 10/4"), "2.5")
		XCTAssertEqual(calculate("2pi"), nil)	// letters need an operator
		XCTAssertEqual(calculate("2*pi"), "6.283185307")
		XCTAssertEqual(calculate("5!"), "120")
		XCTAssertEqual(calculate("3(4+5)"), "27")
		XCTAssertEqual(calculate("1/0"), nil)
		XCTAssertEqual(calculate("-5"), nil)
		XCTAssertEqual(calculate("safari"), nil)
		XCTAssertEqual(calculate("2e3+1"), "2001")
	}

	func testURLs() {
		XCTAssertEqual(urlFor("haiku-os.org"), "https://haiku-os.org")
		XCTAssertEqual(urlFor("github.com/bluevisor/kigo"), "https://github.com/bluevisor/kigo")
		XCTAssertEqual(urlFor("https://x.y"), "https://x.y")
		XCTAssertNil(urlFor("hello world.com"))
		XCTAssertNil(urlFor("v1.2"))
		XCTAssertNil(urlFor("readme.md5"))
	}

	func testVersions() {
		XCTAssertTrue(Updater.isNewer("0.1.10", than: "0.1.9"))
		XCTAssertTrue(Updater.isNewer("0.2", than: "0.1.12"))
		XCTAssertFalse(Updater.isNewer("0.1.12", than: "0.1.12"))
		XCTAssertFalse(Updater.isNewer("0.1.5", than: "0.1.12"))
	}

	func testCommands() {
		XCTAssertEqual(searchCommands("lock", all: true).first?.id, "cmd:lock")
		XCTAssertEqual(searchCommands("reboot", all: true).first?.id, "cmd:restart")
		XCTAssertEqual(searchCommands("sleep", all: false).count, 0)
		XCTAssertEqual(searchCommands("kigo set", all: false).first?.id, "cmd:settings")
	}
}
