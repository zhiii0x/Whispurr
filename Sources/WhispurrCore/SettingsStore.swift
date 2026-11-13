import Foundation

/// Persists `AppSettings` to UserDefaults (JSON-encoded under one key) and
/// notifies observers on change. Kept AppKit-free in Core so it stays
/// unit-testable; the app layer applies side effects (login item, re-wiring).
@MainActor public final class SettingsStore {
    public private(set) var settings: AppSettings
    /// The app's side-effect applier (login item, pipeline re-wiring).
    public var onChange: ((AppSettings) -> Void)?
    /// Further observers — e.g. the Settings window's view model — so anything
    /// holding a settings copy sees writes made elsewhere (the menu's cleanup
    /// toggle, onboarding completion) instead of later overwriting them with a
    /// stale snapshot.
    private var observers: [(AppSettings) -> Void] = []

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "whispurr.settings.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            // First run: start in the user's system language (Chinese for a zh
            // system, English otherwise) so onboarding reads in their language.
            settings = AppSettings(language: .systemDefault)
        }
    }

    /// Mutate, persist, and notify in one step.
    public func update(_ mutate: (inout AppSettings) -> Void) {
        var next = settings
        mutate(&next)
        guard next != settings else { return }   // no-op writes don't notify
        settings = next
        persist()
        onChange?(next)
        observers.forEach { $0(next) }
    }

    /// Register an additional change observer (lives as long as the store).
    public func addObserver(_ observer: @escaping (AppSettings) -> Void) {
        observers.append(observer)
    }

    /// Replace wholesale (e.g. from a settings form binding).
    public func replace(_ next: AppSettings) {
        update { $0 = next }
    }

    private func persist() {
        if let data = try? JSONEncoder().encode(settings) {
            defaults.set(data, forKey: key)
        }
    }
}
