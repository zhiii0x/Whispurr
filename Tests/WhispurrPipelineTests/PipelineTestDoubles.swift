import WhispurrPipeline

/// Shared fake hotkey we can fire manually from the coordinator tests.
@MainActor final class FakeHotkey: HotkeySource {
    var onPress: (() -> Void)?
    var onRelease: (() -> Void)?
    func start() throws {}
    func stop() {}
    func firePress() { onPress?() }
    func fireRelease() { onRelease?() }
}

/// No-op cleanup: returns the text unchanged.
@MainActor final class NoopCleanup: TextCleanup {
    func clean(_ text: String) async -> String { text }
}

/// No-op inserter: does nothing.
@MainActor final class NoopInserter: TextInserter {
    func insert(_ text: String) {}
}
