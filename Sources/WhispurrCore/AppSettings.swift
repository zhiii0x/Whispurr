import Foundation

/// UI language. Independent of the system locale — user-selectable in Settings,
/// defaults to English. (Dictation output stays Traditional Chinese regardless.)
public enum Language: String, CaseIterable, Sendable, Codable, Identifiable {
    case english = "en"
    case chinese = "zh"
    public var id: String { rawValue }
    /// Always shown in its own script in the language picker.
    public var nativeName: String {
        switch self {
        case .english: return "English"
        case .chinese: return "中文"
        }
    }
}

/// A push-to-talk trigger preset. Modifier keys only emit `flagsChanged`, so a
/// preset is the (keyCode, flag) pair the edge detector watches.
public enum HotkeyPreset: String, CaseIterable, Sendable, Codable, Identifiable {
    case fn            // 🌐 / Globe
    case rightOption
    case rightCommand

    public var id: String { rawValue }

    public var keyCode: Int64 {
        switch self {
        case .fn:          return 63
        case .rightOption: return 61
        case .rightCommand: return 54
        }
    }

    /// The CGEventFlags bit set while the key is held.
    public var flag: UInt64 {
        switch self {
        case .fn:          return 0x00800000   // maskSecondaryFn
        case .rightOption: return 0x00080000   // maskAlternate (right)
        case .rightCommand: return 0x00100000  // maskCommand
        }
    }
}

/// How cleaned text is delivered into the focused app.
public enum InsertionMode: String, CaseIterable, Sendable, Codable, Identifiable {
    case paste   // copy → synthetic ⌘V → restore clipboard
    case type    // simulate Unicode keystrokes (IME-heavy fields; never touches clipboard)

    public var id: String { rawValue }
}

/// One deterministic find/replace applied after cleanup (e.g. a recurring name).
public struct VocabularyRule: Codable, Equatable, Sendable, Identifiable {
    public var id: UUID
    public var from: String
    public var to: String
    public var caseSensitive: Bool

    public init(id: UUID = UUID(), from: String, to: String, caseSensitive: Bool = false) {
        self.id = id
        self.from = from
        self.to = to
        self.caseSensitive = caseSensitive
    }
}

/// All user-tunable preferences. Value type so it can be snapshotted, persisted
/// (Codable), and passed across actors (Sendable).
public struct AppSettings: Codable, Equatable, Sendable {
    public var language: Language
    public var hotkey: HotkeyPreset
    public var insertionMode: InsertionMode
    public var cleanupEnabled: Bool
    public var soundCues: Bool
    public var launchAtLogin: Bool
    public var restoreClipboard: Bool
    /// Hard cap on a single utterance so a stuck-down key can't record forever.
    public var maxListenSeconds: Double
    public var vocabulary: [VocabularyRule]
    /// Set true when the user finishes the setup wizard; gates first-run display.
    public var hasCompletedOnboarding: Bool
    /// Opt-in: when on, the app makes a single anonymous GitHub request on launch
    /// to see if a newer release exists. Off by default (privacy-first); a manual
    /// "Check for Updates" button in Settings works regardless.
    public var checkForUpdatesAutomatically: Bool

    public init(language: Language = .english,
                hotkey: HotkeyPreset = .fn,
                insertionMode: InsertionMode = .paste,
                cleanupEnabled: Bool = true,
                soundCues: Bool = true,
                launchAtLogin: Bool = false,
                restoreClipboard: Bool = true,
                maxListenSeconds: Double = 60,
                vocabulary: [VocabularyRule] = [],
                hasCompletedOnboarding: Bool = false,
                checkForUpdatesAutomatically: Bool = false) {
        self.language = language
        self.hotkey = hotkey
        self.insertionMode = insertionMode
        self.cleanupEnabled = cleanupEnabled
        self.soundCues = soundCues
        self.launchAtLogin = launchAtLogin
        self.restoreClipboard = restoreClipboard
        self.maxListenSeconds = maxListenSeconds
        self.vocabulary = vocabulary
        self.hasCompletedOnboarding = hasCompletedOnboarding
        self.checkForUpdatesAutomatically = checkForUpdatesAutomatically
    }

    /// Decode tolerantly: missing keys (older saved blobs) fall back to defaults.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = AppSettings()
        language = try c.decodeIfPresent(Language.self, forKey: .language) ?? d.language
        hotkey = try c.decodeIfPresent(HotkeyPreset.self, forKey: .hotkey) ?? d.hotkey
        insertionMode = try c.decodeIfPresent(InsertionMode.self, forKey: .insertionMode) ?? d.insertionMode
        cleanupEnabled = try c.decodeIfPresent(Bool.self, forKey: .cleanupEnabled) ?? d.cleanupEnabled
        soundCues = try c.decodeIfPresent(Bool.self, forKey: .soundCues) ?? d.soundCues
        launchAtLogin = try c.decodeIfPresent(Bool.self, forKey: .launchAtLogin) ?? d.launchAtLogin
        restoreClipboard = try c.decodeIfPresent(Bool.self, forKey: .restoreClipboard) ?? d.restoreClipboard
        maxListenSeconds = try c.decodeIfPresent(Double.self, forKey: .maxListenSeconds) ?? d.maxListenSeconds
        vocabulary = try c.decodeIfPresent([VocabularyRule].self, forKey: .vocabulary) ?? d.vocabulary
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? d.hasCompletedOnboarding
        checkForUpdatesAutomatically = try c.decodeIfPresent(Bool.self, forKey: .checkForUpdatesAutomatically)
            ?? d.checkForUpdatesAutomatically
    }
}
