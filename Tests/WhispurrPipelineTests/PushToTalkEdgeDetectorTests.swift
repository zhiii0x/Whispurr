import XCTest
@testable import WhispurrPipeline

final class PushToTalkEdgeDetectorTests: XCTestCase {
    // fn / Globe: keyCode 63, CGEventFlags.maskSecondaryFn == 0x00800000
    let fnFlag: UInt64 = 0x00800000

    func testPressThenRelease() {
        var d = PushToTalkEdgeDetector()           // defaults to fn / Globe
        XCTAssertEqual(d.handleFlagsChanged(keyCode: 63, flags: fnFlag), .press)
        XCTAssertEqual(d.handleFlagsChanged(keyCode: 63, flags: 0), .release)
    }

    func testIgnoresOtherKeyCodes() {
        var d = PushToTalkEdgeDetector()
        // right Option (61) must not trigger the fn-default detector
        XCTAssertEqual(d.handleFlagsChanged(keyCode: 61, flags: fnFlag), .none)
    }

    func testNoDuplicatePressOnRepeat() {
        var d = PushToTalkEdgeDetector()
        XCTAssertEqual(d.handleFlagsChanged(keyCode: 63, flags: fnFlag), .press)
        // a second flagsChanged with the flag still set is not a new press
        XCTAssertEqual(d.handleFlagsChanged(keyCode: 63, flags: fnFlag), .none)
    }

    func testReleaseOnlyAfterPress() {
        var d = PushToTalkEdgeDetector()
        XCTAssertEqual(d.handleFlagsChanged(keyCode: 63, flags: 0), .none)
    }
}
