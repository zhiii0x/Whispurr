import XCTest
@testable import WhispurrCore

final class CatSpriteSetTests: XCTestCase {
    let sprites = CatSpriteSet()

    func testEveryStateHasAtLeastOneFrame() {
        let states: [DictationState] = [.idle, .listening, .processing, .error("x")]
        for state in states {
            XCTAssertFalse(sprites.frames(for: state).isEmpty, "\(state) has no frames")
        }
    }

    func testIdleIsStatic() {
        XCTAssertFalse(sprites.shouldAnimate(.idle))
    }

    func testListeningFrameDiffersFromIdle() {
        XCTAssertNotEqual(sprites.frames(for: .listening), sprites.frames(for: .idle))
    }

    func testFallbackSymbolForListeningIsHeadphones() {
        XCTAssertEqual(sprites.sfSymbolFallback(for: .listening), "headphones")
    }
}
