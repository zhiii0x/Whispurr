import XCTest
@testable import WhispurrCore

final class LanguageDefaultTests: XCTestCase {
    func testTraditionalChineseTop() {
        XCTAssertEqual(Language.from(preferredLanguages: ["zh-Hant-TW", "en-US"]), .chinese)
    }

    func testSimplifiedChineseTop() {
        XCTAssertEqual(Language.from(preferredLanguages: ["zh-Hans-CN"]), .chinese)
    }

    func testEnglishTop() {
        XCTAssertEqual(Language.from(preferredLanguages: ["en-US", "zh-Hant"]), .english)
    }

    func testOtherLanguageFallsBackToEnglish() {
        XCTAssertEqual(Language.from(preferredLanguages: ["ja-JP", "en"]), .english)
    }

    func testEmptyFallsBackToEnglish() {
        XCTAssertEqual(Language.from(preferredLanguages: []), .english)
    }
}
