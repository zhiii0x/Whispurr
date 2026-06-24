import XCTest
import WhispurrCore
@testable import WhispurrPipeline

@MainActor
final class SmokeTests: XCTestCase {
    /// A real smoke check that the inserter constructs for both modes
    /// (replaces the old XCTAssertTrue(true) placeholder).
    func testInserterConstructsForBothModes() {
        _ = SystemTextInserter(mode: .paste, restoreClipboard: true)
        _ = SystemTextInserter(mode: .type, restoreClipboard: false)
    }
}
