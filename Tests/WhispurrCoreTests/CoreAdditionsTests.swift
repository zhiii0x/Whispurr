import XCTest
@testable import WhispurrCore

final class VocabularyManagerTests: XCTestCase {
    func testCaseInsensitiveReplace() {
        let vm = VocabularyManager(rules: [VocabularyRule(from: "github", to: "GitHub")])
        XCTAssertEqual(vm.apply(to: "把 code push 到 Github 上"), "把 code push 到 GitHub 上")
    }

    func testCaseSensitiveReplace() {
        let vm = VocabularyManager(rules: [VocabularyRule(from: "Api", to: "API", caseSensitive: true)])
        XCTAssertEqual(vm.apply(to: "Api 與 api"), "API 與 api")   // only the exact-case match
    }

    func testRulesAppliedInOrderAndEmptyFromSkipped() {
        let vm = VocabularyManager(rules: [
            VocabularyRule(from: "", to: "X"),                 // skipped
            VocabularyRule(from: "k8s", to: "Kubernetes"),
        ])
        XCTAssertEqual(vm.apply(to: "部署到 k8s"), "部署到 Kubernetes")
    }
}

final class TranscriptJoinerTests: XCTestCase {
    func testSpacesBetweenAsciiWords() {
        XCTAssertEqual(TranscriptJoiner.join("pull", "request"), "pull request")
    }
    func testTightBetweenCJK() {
        XCTAssertEqual(TranscriptJoiner.join("這個", "提交"), "這個提交")
    }
    func testNoDoubleSpaceWhenBoundaryExists() {
        XCTAssertEqual(TranscriptJoiner.join("pull ", "request"), "pull request")
        XCTAssertEqual(TranscriptJoiner.join("pull", " request"), "pull request")
    }
    func testEmptySides() {
        XCTAssertEqual(TranscriptJoiner.join("", "push"), "push")
        XCTAssertEqual(TranscriptJoiner.join("push", ""), "push")
    }
}

final class AppSettingsCodingTests: XCTestCase {
    func testDefaultLanguageIsEnglish() {
        XCTAssertEqual(AppSettings().language, .english)
    }

    func testRoundTrip() throws {
        var s = AppSettings()
        s.language = .chinese
        s.hotkey = .rightOption
        s.insertionMode = .type
        s.cleanupEnabled = false
        s.vocabulary = [VocabularyRule(from: "a", to: "b")]
        let data = try JSONEncoder().encode(s)
        let back = try JSONDecoder().decode(AppSettings.self, from: data)
        XCTAssertEqual(s, back)
    }

    func testTolerantDecodeOfPartialBlob() throws {
        // An older/partial saved blob missing most keys should fall back to defaults.
        let json = #"{"hotkey":"rightCommand"}"#.data(using: .utf8)!
        let s = try JSONDecoder().decode(AppSettings.self, from: json)
        XCTAssertEqual(s.hotkey, .rightCommand)
        XCTAssertEqual(s.insertionMode, AppSettings().insertionMode)
        XCTAssertEqual(s.cleanupEnabled, AppSettings().cleanupEnabled)
    }
}

@MainActor
final class SettingsStoreTests: XCTestCase {
    private func makeDefaults() -> UserDefaults {
        let suite = "whispurr.test.\(UUID().uuidString)"
        return UserDefaults(suiteName: suite)!
    }

    func testPersistsAcrossInstances() {
        let defaults = makeDefaults()
        let store = SettingsStore(defaults: defaults, key: "k")
        store.update { $0.cleanupEnabled = false; $0.hotkey = .rightOption }

        let reopened = SettingsStore(defaults: defaults, key: "k")
        XCTAssertFalse(reopened.settings.cleanupEnabled)
        XCTAssertEqual(reopened.settings.hotkey, .rightOption)
    }

    func testNoOpWriteDoesNotNotify() {
        let store = SettingsStore(defaults: makeDefaults(), key: "k")
        var calls = 0
        store.onChange = { _ in calls += 1 }
        store.update { $0.cleanupEnabled = store.settings.cleanupEnabled }   // unchanged
        XCTAssertEqual(calls, 0)
        store.update { $0.cleanupEnabled.toggle() }
        XCTAssertEqual(calls, 1)
    }
}

final class DictationStateMachineCancelTests: XCTestCase {
    func testCancelFromListeningGoesIdle() {
        var m = DictationStateMachine()
        _ = m.handle(.pushToTalkDown)            // → listening
        XCTAssertEqual(m.handle(.cancel), .idle)
    }
    func testCancelFromProcessingGoesIdle() {
        var m = DictationStateMachine()
        _ = m.handle(.pushToTalkDown)            // → listening
        _ = m.handle(.pushToTalkUp)              // → processing
        XCTAssertEqual(m.handle(.cancel), .idle)
    }
    func testCancelFromIdleIgnored() {
        var m = DictationStateMachine()
        XCTAssertEqual(m.handle(.cancel), .idle)
    }
}
