import XCTest
@testable import WhispurrPipeline

final class PermissionSnapshotTests: XCTestCase {
    func testCanDictateRequiresAllFourGrants() {
        var s = PermissionSnapshot(microphone: true, speech: true,
                                   inputMonitoring: true, accessibility: true,
                                   appleIntelligence: false)
        XCTAssertTrue(s.canDictate)          // cleanup is optional, AI not required
        s.accessibility = false
        XCTAssertFalse(s.canDictate)
    }

    func testCleanupAvailableTracksAppleIntelligence() {
        let s = PermissionSnapshot(microphone: true, speech: true,
                                   inputMonitoring: true, accessibility: true,
                                   appleIntelligence: true)
        XCTAssertTrue(s.cleanupAvailable)
    }

    func testMissingListsUngrantedItems() {
        let s = PermissionSnapshot(microphone: true, speech: false,
                                   inputMonitoring: false, accessibility: true,
                                   appleIntelligence: false)
        XCTAssertEqual(Set(s.missing), Set([.speech, .inputMonitoring]))
    }
}
