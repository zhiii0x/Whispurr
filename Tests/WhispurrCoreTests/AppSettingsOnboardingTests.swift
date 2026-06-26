import XCTest
@testable import WhispurrCore

final class AppSettingsOnboardingTests: XCTestCase {
    func testDefaultIsFalse() {
        XCTAssertFalse(AppSettings().hasCompletedOnboarding)
    }

    func testMissingKeyDecodesToFalse() throws {
        // An older saved blob without the new key.
        let json = #"{"language":"en"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertFalse(s.hasCompletedOnboarding)
    }

    func testRoundTripsTrue() throws {
        var s = AppSettings()
        s.hasCompletedOnboarding = true
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertTrue(back.hasCompletedOnboarding)
    }
}
