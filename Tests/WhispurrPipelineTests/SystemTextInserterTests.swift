import XCTest
@testable import WhispurrPipeline

@MainActor
final class SystemTextInserterTests: XCTestCase {
    // The pure clipboard-restore decision (documented clipboard-race risk).
    func testRestoresWhenOurTextStillOnPasteboard() {
        XCTAssertTrue(SystemTextInserter.shouldRestore(currentChangeCount: 7, stamp: 7, savedIsEmpty: false))
    }
    func testDoesNotRestoreWhenClipboardChangedUnderUs() {
        XCTAssertFalse(SystemTextInserter.shouldRestore(currentChangeCount: 8, stamp: 7, savedIsEmpty: false))
    }
    func testDoesNotRestoreWhenNothingWasSaved() {
        XCTAssertFalse(SystemTextInserter.shouldRestore(currentChangeCount: 7, stamp: 7, savedIsEmpty: true))
    }
}
