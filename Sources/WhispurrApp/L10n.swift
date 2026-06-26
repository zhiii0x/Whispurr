import Foundation
import WhispurrCore

/// Lightweight in-app localization driven by the user's Language setting (NOT
/// the system locale), defaulting to English. Set `L10n.lang` once at launch and
/// whenever the setting changes; SwiftUI views re-read it on the next render and
/// the menu is re-titled explicitly.
@MainActor enum L10n {
    static var lang: Language = .english

    enum Key {
        // Menu
        case recentNone, recentPrefix, copyLast, cleanupOn, cleanupOff
        case pause, resume, menuSettings, menuPermissions, quit
        // HUD
        case hudListening, hudProcessing, hudHeardNothing
        // Settings
        case settingsTitle, secInput, fieldLanguage, fieldHotkey, fieldInsertion
        case fieldRestoreClipboard, secCleanup, fieldCleanup, noteCleanup
        case secBehavior, fieldSoundCues, fieldLaunchAtLogin, fieldMaxListen
        case secVocab, vocabFrom, vocabTo, caseSensitive, addRule
        case secAbout, aboutMadeBy
        case fieldAutoUpdate, checkUpdates, upToDate, updateFailed, downloadUpdate
        case menuUpdateAvailable
        // Onboarding
        case obTagline, obGrant, obFnHint, obOpenKeyboard, obAIOn, obAIOff
        case obModelDownloading, obStart, obStartBlocked, obWindowTitle
        // Permissions
        case permInputTitle, permInputWhy, permMicTitle, permMicWhy
        case permSpeechTitle, permSpeechWhy, permAxTitle, permAxWhy
    }

    static func t(_ k: Key) -> String {
        let p = pair(k)
        return lang == .english ? p.0 : p.1
    }

    /// Format string variant (e.g. download percent).
    static func t(_ k: Key, _ args: CVarArg...) -> String {
        String(format: t(k), arguments: args)
    }

    static func hotkey(_ preset: HotkeyPreset) -> String {
        switch (preset, lang) {
        case (.fn, _):                    return "fn"
        case (.rightOption, .english):    return "Right Option (⌥)"
        case (.rightOption, .chinese):    return "右 Option（⌥）"
        case (.rightCommand, .english):   return "Right Command (⌘)"
        case (.rightCommand, .chinese):   return "右 Command（⌘）"
        }
    }

    static func insertion(_ mode: InsertionMode) -> String {
        switch (mode, lang) {
        case (.paste, .english): return "Paste (⌘V, most compatible)"
        case (.paste, .chinese): return "貼上（⌘V，相容性最好）"
        case (.type, .english):  return "Simulate typing (no clipboard, IME-safe)"
        case (.type, .chinese):  return "模擬輸入（不碰剪貼簿，適合 IME 欄位）"
        }
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    private static func pair(_ k: Key) -> (String, String) {
        switch k {
        // Menu
        case .recentNone:     return ("Recent: (none)", "最近辨識：（尚未）")
        case .recentPrefix:   return ("Recent: ", "最近辨識：")
        case .copyLast:       return ("Copy last result", "拷貝最近辨識")
        case .cleanupOn:      return ("Cleanup: on (Apple Intelligence)", "整稿：開啟（Apple Intelligence）")
        case .cleanupOff:     return ("Cleanup: off — inserting raw", "整稿：未啟用 → 插入原始稿")
        case .pause:          return ("Pause dictation", "暫停聽寫")
        case .resume:         return ("Resume dictation", "啟用聽寫")
        case .menuSettings:   return ("Settings…", "設定…")
        case .menuPermissions:return ("Permissions…", "權限…")
        case .quit:           return ("Quit Whispurr", "結束 Whispurr")
        // HUD
        case .hudListening:   return ("Listening…", "聆聽中…")
        case .hudProcessing:  return ("Cleaning up…", "整理中…")
        case .hudHeardNothing:return ("Didn't catch that", "沒聽到聲音")
        // Settings
        case .settingsTitle:  return ("Whispurr Settings", "Whispurr 設定")
        case .secInput:       return ("Input", "輸入")
        case .fieldLanguage:  return ("Language", "語言")
        case .fieldHotkey:    return ("Hotkey", "熱鍵")
        case .fieldInsertion: return ("Insertion", "插入方式")
        case .fieldRestoreClipboard: return ("Restore clipboard after paste", "插入後還原剪貼簿")
        case .secCleanup:     return ("Cleanup", "整稿")
        case .fieldCleanup:   return ("Polish with Apple Intelligence", "用 Apple Intelligence 自動順稿")
        case .noteCleanup:    return ("When off, the raw transcript is inserted (faster, no LLM).",
                                      "關閉時直接插入原始辨識稿（較快、不經過 LLM）。")
        case .secBehavior:    return ("Behavior", "行為")
        case .fieldSoundCues: return ("Play a sound on start / stop", "開始/結束時播放提示音")
        case .fieldLaunchAtLogin: return ("Launch at login", "開機時自動啟動")
        case .fieldMaxListen: return ("Max recording length", "單次最長錄音")
        case .secVocab:       return ("Custom vocabulary (applied after cleanup)", "自訂詞彙（整稿後套用的取代規則）")
        case .vocabFrom:      return ("heard as…", "聽成…")
        case .vocabTo:        return ("replace with…", "改成…")
        case .caseSensitive:  return ("case-sensitive", "區分大小寫")
        case .addRule:        return ("Add rule", "新增規則")
        case .secAbout:       return ("About", "關於")
        case .aboutMadeBy:    return ("Designed by", "設計者")
        case .fieldAutoUpdate: return ("Check for updates automatically", "自動檢查更新")
        case .checkUpdates:   return ("Check for Updates", "檢查更新")
        case .upToDate:       return ("You're up to date", "已是最新版")
        case .updateFailed:   return ("Couldn't check", "無法檢查")
        case .downloadUpdate: return ("Download %@ →", "下載 %@ →")
        case .menuUpdateAvailable: return ("Update available: %@", "有新版本：%@")
        // Onboarding
        case .obTagline:      return ("Hold fn and speak — clean text appears at your cursor.",
                                      "按住 fn 說話，乾淨的文字直接出現在游標處。")
        case .obGrant:        return ("Grant…", "前往授權")
        case .obFnHint:       return ("Set “Press 🌐 to” → “Do Nothing” so fn isn't hijacked.",
                                      "把『按下 🌐 鍵時』設成「不執行任何動作」，fn 才不會被系統搶走。")
        case .obOpenKeyboard: return ("Open Keyboard Settings", "開啟鍵盤設定")
        case .obAIOn:         return ("Apple Intelligence is on — transcripts are auto-polished.",
                                      "Apple Intelligence 已啟用 — 會自動順稿。")
        case .obAIOff:        return ("Apple Intelligence is off — the raw transcript is inserted.",
                                      "Apple Intelligence 未啟用 — 會插入未整理的原始稿。")
        case .obModelDownloading: return ("Downloading speech model… %ld%% (one-time)",
                                          "下載語音模型中… %ld%%（一次性）")
        case .obStart:        return ("Get started", "開始使用")
        case .obStartBlocked: return ("Grant the required permissions first", "請先完成必要權限")
        case .obWindowTitle:  return ("Welcome to Whispurr", "歡迎使用 Whispurr")
        // Permissions
        case .permInputTitle: return ("Input Monitoring", "輸入監控")
        case .permInputWhy:   return ("Detect the fn hotkey (hold to talk)", "偵測 fn 熱鍵（按住說話）")
        case .permMicTitle:   return ("Microphone", "麥克風")
        case .permMicWhy:     return ("Record your voice", "錄下你的聲音")
        case .permSpeechTitle:return ("Speech Recognition", "語音辨識")
        case .permSpeechWhy:  return ("Transcribe speech on-device", "在本機把語音轉成文字")
        case .permAxTitle:    return ("Accessibility", "輔助使用")
        case .permAxWhy:      return ("Insert text at your cursor", "把文字插入到游標所在的 app")
        }
    }
}
