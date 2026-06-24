import Foundation

/// Persists `AppSettings` to UserDefaults (JSON-encoded under one key) and
/// notifies a single observer on change. Kept AppKit-free in Core so it stays
/// unit-testable; the app layer applies side effects (login item, re-wiring).
@MainActor public final class SettingsStore {
    public private(set) var settings: AppSettings
    public var onChange: ((AppSettings) -> Void)?

    private let defaults: UserDefaults
    private let key: String

    public init(defaults: UserDefaults = .standard, key: String = "whispurr.settings.v1") {
        self.defaults = defaults
        self.key = key
        if let data = defaults.data(forKey: key),
           let decoded = try? JSONDecoder().decode(AppSettings.self, from: data) {
            settings = decoded
        } else {
            settings = AppSettings()
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
