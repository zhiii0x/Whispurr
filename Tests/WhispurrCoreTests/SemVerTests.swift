import XCTest
@testable import WhispurrCore

final class SemVerTests: XCTestCase {
    func testParse() {
        XCTAssertEqual(SemVer.parse("v0.1.2"), [0, 1, 2])
        XCTAssertEqual(SemVer.parse("0.1.2"), [0, 1, 2])
        XCTAssertEqual(SemVer.parse("V1"), [1])
        XCTAssertEqual(SemVer.parse(" 2.0.0 "), [2, 0, 0])
        XCTAssertNil(SemVer.parse(""))
        XCTAssertNil(SemVer.parse("v"))
        XCTAssertNil(SemVer.parse("nightly"))
        XCTAssertNil(SemVer.parse("0.1.x"))
    }

    func testNewer() {
        XCTAssertTrue(SemVer.isNewer("v0.1.2", than: "0.1.1"))
        XCTAssertTrue(SemVer.isNewer("0.2.0", than: "0.1.9"))
        XCTAssertTrue(SemVer.isNewer("1.0", than: "0.9.9"))
        XCTAssertFalse(SemVer.isNewer("0.1.1", than: "0.1.1"))
        XCTAssertFalse(SemVer.isNewer("0.1.0", than: "0.1.1"))
        XCTAssertFalse(SemVer.isNewer("v0.1.1", than: "v0.1.2"))
    }

    func testZeroPadding() {
        XCTAssertTrue(SemVer.isNewer("0.1.1.1", than: "0.1.1"))
        XCTAssertFalse(SemVer.isNewer("0.1.0", than: "0.1.0.0"))
        XCTAssertFalse(SemVer.isNewer("1.0", than: "1.0.0"))
    }

    func testUnparseableNeverPrompts() {
        XCTAssertFalse(SemVer.isNewer("garbage", than: "0.1.1"))
        XCTAssertFalse(SemVer.isNewer("0.1.1", than: "nightly"))
    }
}
