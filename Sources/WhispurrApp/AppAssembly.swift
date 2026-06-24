import WhispurrCore
import WhispurrPipeline

/// The wired pipeline plus the concrete pieces the app needs to reconfigure at
/// runtime (hotkey trigger, recognizer phrase bias).
@MainActor struct AppComponents {
    let coordinator: DictationCoordinator
    let hotkey: HotkeyManager
    let engine: AppleSpeechTranscriberEngine
}

/// Composition root: builds the dictation pipeline from a settings snapshot, so
/// the choice of insertion mode / hotkey / phrase bias lives in one place rather
/// than being hardcoded in `applicationDidFinishLaunching`.
@MainActor enum AppAssembly {
    static func make(appState: AppState, settings: AppSettings) -> AppComponents {
        let hotkey = HotkeyManager(detector: PushToTalkEdgeDetector(preset: settings.hotkey))
        let engine = AppleSpeechTranscriberEngine(contextualPhrases: contextualPhrases(for: settings))
        let cleanup = FoundationModelsCleanup()
        let inserter = SystemTextInserter(mode: settings.insertionMode,
                                          restoreClipboard: settings.restoreClipboard)
        let coordinator = DictationCoordinator(appState: appState, hotkey: hotkey,
                                               engine: engine, cleanup: cleanup, inserter: inserter)
        coordinator.updateSettings(settings)
        return AppComponents(coordinator: coordinator, hotkey: hotkey, engine: engine)
    }

    /// Default tech jargon plus the user's vocabulary terms, to bias recognition.
    static func contextualPhrases(for settings: AppSettings) -> [String] {
        var phrases = AppleSpeechTranscriberEngine.defaultTechPhrases
        for rule in settings.vocabulary {
            if !rule.to.isEmpty { phrases.append(rule.to) }
            if !rule.from.isEmpty { phrases.append(rule.from) }
        }
        // De-dupe, preserving order.
        var seen = Set<String>()
        return phrases.filter { seen.insert($0).inserted }
    }
}
