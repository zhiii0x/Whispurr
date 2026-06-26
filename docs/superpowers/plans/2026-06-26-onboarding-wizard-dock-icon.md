# Onboarding Wizard + Persistent Dock Icon — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the single permission window with a 5-step first-run setup wizard (how-it-works → permissions → key settings → try-it → done), and give the app a persistent Dock icon.

**Architecture:** A SwiftUI `OnboardingFlow` container drives `@State step`, rendering one step subview at a time with Back/Next + progress dots. Permissions and key-settings steps reuse the existing `PermissionsViewModel` and `SettingsStore`. The app becomes a regular (Dock-visible) app via `LSUIElement=false`, with a reopen handler that opens Settings and a minimal main menu.

**Tech Stack:** Swift / SwiftUI / AppKit, SwiftPM, XCTest. macOS 26, Apple Silicon. Verify UI by `swift build` (compiles) + render-to-PNG (the project's established approach); verify logic with XCTest.

**Spec:** `docs/superpowers/specs/2026-06-26-onboarding-wizard-and-dock-icon-design.md`

**Conventions in this repo:**
- App sources are flat under `Sources/WhispurrApp/`. Keep new files flat there.
- L10n: add a `case` to `L10n.Key` and a `(English, 中文)` tuple in `pair(_:)`.
- Commits: no AI co-author trailer.
- Cozy onboarding theme: `UIStyle.softBackground`, `UIStyle.accent`, `UIStyle.cardRadius`, `UIStyle.catImage(_:)`, `.environment(\.colorScheme, .light)`.

**Render harness (reused by UI verification steps).** Write `/tmp/render.swift` with the step view inlined (hardcode strings/cat path), compile and open:
```bash
swiftc /tmp/render.swift -o /tmp/render && /tmp/render /tmp/out.png && open /tmp/out.png
```
Pattern: `NSApplication.shared` accessory; `NSHostingView`/`NSWindow` with the view; `win.contentView?.wantsLayer = true; win.orderFrontRegardless(); win.displayIfNeeded()`; `RunLoop.current.run(until: Date().addingTimeInterval(1.8))`; then `contentView.cacheDisplay(in:to:)` → PNG. (Plain `swift file.swift` fails on `@available`; always `swiftc`.)

---

## Task 1: `AppSettings.hasCompletedOnboarding`

**Files:**
- Modify: `Sources/WhispurrCore/AppSettings.swift`
- Test: `Tests/WhispurrCoreTests/AppSettingsOnboardingTests.swift` (create)

- [ ] **Step 1: Write the failing test**

Create `Tests/WhispurrCoreTests/AppSettingsOnboardingTests.swift`:
```swift
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
```

- [ ] **Step 2: Run test to verify it fails**

Run: `swift test --filter AppSettingsOnboardingTests`
Expected: FAIL — `value of type 'AppSettings' has no member 'hasCompletedOnboarding'`.

- [ ] **Step 3: Add the field**

In `Sources/WhispurrCore/AppSettings.swift`, in `struct AppSettings`, after `public var vocabulary: [VocabularyRule]` add:
```swift
    /// Set true when the user finishes the setup wizard; gates first-run display.
    public var hasCompletedOnboarding: Bool
```
Add the parameter to the memberwise `init` (after `vocabulary:`):
```swift
                vocabulary: [VocabularyRule] = [],
                hasCompletedOnboarding: Bool = false) {
```
and inside it: `self.hasCompletedOnboarding = hasCompletedOnboarding`.
In `init(from:)`, after the `vocabulary = ...` line add:
```swift
        hasCompletedOnboarding = try c.decodeIfPresent(Bool.self, forKey: .hasCompletedOnboarding)
            ?? d.hasCompletedOnboarding
```

- [ ] **Step 4: Run test to verify it passes**

Run: `swift test --filter AppSettingsOnboardingTests`
Expected: PASS (3 tests).

- [ ] **Step 5: Commit**
```bash
git add Sources/WhispurrCore/AppSettings.swift Tests/WhispurrCoreTests/AppSettingsOnboardingTests.swift
git commit -m "feat: add AppSettings.hasCompletedOnboarding"
```

---

## Task 2: L10n strings for the wizard

**Files:**
- Modify: `Sources/WhispurrApp/L10n.swift`

- [ ] **Step 1: Add the Key cases**

In `enum Key`, after the existing onboarding cases (the `case obModelDownloading, obStart, obStartBlocked, obWindowTitle` line), add:
```swift
        // Wizard
        case navBack, navNext, navFinish
        case howTitle, howStep1, howStep2, howStep3, howEscTip
        case keySetupTitle
        case tryTitle, tryInstruction, tryPlaceholder
        case doneTitle, doneBody
        case menuAbout
```

- [ ] **Step 2: Add the pairs**

In `pair(_:)`, before the closing brace of the switch (next to the other onboarding pairs), add:
```swift
        case .navBack:        return ("Back", "上一步")
        case .navNext:        return ("Next", "下一步")
        case .navFinish:      return ("Finish", "完成設定")
        case .howTitle:       return ("How it works", "怎麼用")
        case .howStep1:       return ("Hold the fn key", "按住 fn 鍵")
        case .howStep2:       return ("Speak — Mandarin + English", "開口說話(中文 + English 都行)")
        case .howStep3:       return ("Release → text appears at your cursor", "放開 → 文字出現在游標處")
        case .howEscTip:      return ("Mid-sentence? Press Esc to cancel.", "說到一半想取消?按 Esc。")
        case .keySetupTitle:  return ("Quick setup", "快速設定")
        case .tryTitle:       return ("Try it", "試一下")
        case .tryInstruction: return ("Click the box, then hold fn and say something — your words land here.",
                                      "點一下方框,按住 fn 說句話 — 文字會出現在這。")
        case .tryPlaceholder: return ("Your words will appear here…", "你說的話會出現在這…")
        case .doneTitle:      return ("You're all set", "設定完成")
        case .doneBody:       return ("Whispurr lives in your menu bar and Dock. Hold fn anywhere to dictate; open Settings from the menu anytime.",
                                      "Whispurr 在選單列和 Dock 都有。任何地方按住 fn 就能聽寫;之後可從選單打開設定。")
        case .menuAbout:      return ("About Whispurr", "關於 Whispurr")
```

- [ ] **Step 3: Verify it compiles**

Run: `swift build`
Expected: `Build complete!` (no "switch must be exhaustive" error).

- [ ] **Step 4: Commit**
```bash
git add Sources/WhispurrApp/L10n.swift
git commit -m "feat: add L10n strings for the setup wizard"
```

---

## Task 3: Make the app a regular Dock app (plist)

**Files:**
- Modify: `Sources/WhispurrApp/Info.plist`
- Modify: `scripts/package.sh`

- [ ] **Step 1: Flip the static Info.plist**

In `Sources/WhispurrApp/Info.plist`, change:
```xml
    <key>LSUIElement</key>
    <true/>
```
to:
```xml
    <key>LSUIElement</key>
    <false/>
```

- [ ] **Step 2: Flip the generated plist in package.sh**

In `scripts/package.sh`, in the generated Info.plist heredoc, change `<key>LSUIElement</key><true/>` to `<key>LSUIElement</key><false/>`.

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Commit**
```bash
git add Sources/WhispurrApp/Info.plist scripts/package.sh
git commit -m "feat: ship as a regular Dock app (LSUIElement=false)"
```

---

## Task 4: AppDelegate — Dock behavior + main menu

**Files:**
- Create: `Sources/WhispurrApp/MainMenu.swift`
- Modify: `Sources/WhispurrApp/AppDelegate.swift`

- [ ] **Step 1: Create the main menu builder**

Create `Sources/WhispurrApp/MainMenu.swift`:
```swift
import AppKit

/// Minimal main menu for the now-regular app: an App menu (About / Settings /
/// Hide / Quit) and a standard Edit menu so ⌘C/⌘V/⌘A/⌘Z work in text fields.
/// `settingsTarget`/`settingsAction` wire the Settings… item back to AppDelegate.
@MainActor func buildMainMenu(settingsTarget: AnyObject, settingsAction: Selector) -> NSMenu {
    let main = NSMenu()

    let appItem = NSMenuItem()
    main.addItem(appItem)
    let appMenu = NSMenu()
    appItem.submenu = appMenu
    appMenu.addItem(withTitle: L10n.t(.menuAbout),
                    action: #selector(NSApplication.orderFrontStandardAboutPanel(_:)), keyEquivalent: "")
    appMenu.addItem(.separator())
    let settings = NSMenuItem(title: L10n.t(.menuSettings), action: settingsAction, keyEquivalent: ",")
    settings.target = settingsTarget
    appMenu.addItem(settings)
    appMenu.addItem(.separator())
    appMenu.addItem(withTitle: "Hide", action: #selector(NSApplication.hide(_:)), keyEquivalent: "h")
    appMenu.addItem(withTitle: L10n.t(.quit),
                    action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")

    let editItem = NSMenuItem()
    main.addItem(editItem)
    let editMenu = NSMenu(title: "Edit")
    editItem.submenu = editMenu
    editMenu.addItem(withTitle: "Undo", action: Selector(("undo:")), keyEquivalent: "z")
    editMenu.addItem(withTitle: "Redo", action: Selector(("redo:")), keyEquivalent: "Z")
    editMenu.addItem(.separator())
    editMenu.addItem(withTitle: "Cut", action: #selector(NSText.cut(_:)), keyEquivalent: "x")
    editMenu.addItem(withTitle: "Copy", action: #selector(NSText.copy(_:)), keyEquivalent: "c")
    editMenu.addItem(withTitle: "Paste", action: #selector(NSText.paste(_:)), keyEquivalent: "v")
    editMenu.addItem(withTitle: "Select All", action: #selector(NSText.selectAll(_:)), keyEquivalent: "a")

    return main
}
```

- [ ] **Step 2: Wire Dock behavior into AppDelegate**

In `Sources/WhispurrApp/AppDelegate.swift`, at the very start of `applicationDidFinishLaunching(_:)` (before `let settings = settingsStore.settings`) add:
```swift
        NSApp.setActivationPolicy(.regular)               // Dock icon
        NSApp.mainMenu = buildMainMenu(settingsTarget: self,
                                       settingsAction: #selector(openSettingsFromMenu))
```
Add these methods to the `AppDelegate` class (next to `applicationWillTerminate`):
```swift
    @objc func openSettingsFromMenu() { settingsWindow.show() }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false   // keep running in the menu bar / Dock after windows close
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            if settingsStore.settings.hasCompletedOnboarding { settingsWindow.show() }
            else { onboarding.show() }
        }
        return true
    }
```

- [ ] **Step 3: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 4: Verify the Dock icon live**

Run:
```bash
SIGN_IDENTITY="Developer ID Application: Frank Lin (766AZHGT3J)" scripts/package.sh >/dev/null 2>&1
pkill -u "$(id -u)" -f "dist/Whispurr.app/Contents/MacOS/Whispurr"; sleep 1; open dist/Whispurr.app
```
Expected: cat icon appears in the Dock; clicking it opens a window; closing the window leaves the app running (cat still in menu bar).

- [ ] **Step 5: Commit**
```bash
git add Sources/WhispurrApp/MainMenu.swift Sources/WhispurrApp/AppDelegate.swift
git commit -m "feat: Dock-app behavior — reopen opens Settings, keep running, main menu"
```

---

## Task 5: How-it-works step view

**Files:**
- Create: `Sources/WhispurrApp/OnboardingHowItWorks.swift`

- [ ] **Step 1: Create the view**

Create `Sources/WhispurrApp/OnboardingHowItWorks.swift`:
```swift
import SwiftUI

struct OnboardingHowItWorks: View {
    var body: some View {
        VStack(spacing: 15) {
            if let cat = UIStyle.catImage("listening") {
                Image(nsImage: cat).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 78, height: 78)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            VStack(spacing: 4) {
                Text("Whispurr").font(.title2.bold())
                Text(L10n.t(.obTagline)).font(.callout).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            VStack(alignment: .leading, spacing: 13) {
                Text(L10n.t(.howTitle)).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
                stepRow(kind: .fn,   text: L10n.t(.howStep1))
                stepRow(kind: .mic,  text: L10n.t(.howStep2))
                stepRow(kind: .text, text: L10n.t(.howStep3))
            }
            .padding(16)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: UIStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius).strokeBorder(.white.opacity(0.8)))
            .shadow(color: .black.opacity(0.05), radius: 4, y: 2)
            Text(L10n.t(.howEscTip)).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.horizontal, 24).padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private enum Kind { case fn, mic, text }

    @ViewBuilder private func stepRow(kind: Kind, text: String) -> some View {
        HStack(spacing: 13) {
            ZStack {
                Circle().fill(UIStyle.accent.opacity(0.14)).frame(width: 34, height: 34)
                switch kind {
                case .fn:
                    RoundedRectangle(cornerRadius: 5).fill(.white)
                        .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(UIStyle.accent.opacity(0.5)))
                        .overlay(Text("fn").font(.system(size: 11, weight: .semibold)).foregroundStyle(UIStyle.accent))
                        .frame(width: 26, height: 20)
                case .mic:
                    Image(systemName: "waveform").font(.system(size: 15, weight: .semibold)).foregroundStyle(UIStyle.accent)
                case .text:
                    Image(systemName: "text.cursor").font(.system(size: 15, weight: .semibold)).foregroundStyle(UIStyle.accent)
                }
            }
            Text(text).font(.system(size: 13.5))
            Spacer()
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Render to verify visually**

Inline the view into `/tmp/render.swift` per the render harness (wrap in `.frame(width: 420, height: 470).background(UIStyle.softBackground).environment(\.colorScheme, .light)` — substitute the gradient/accent literals since UIStyle isn't importable in the standalone). Run the harness and confirm the cat hero, three steps (fn keycap / waveform / cursor), and Esc tip render.

- [ ] **Step 4: Commit**
```bash
git add Sources/WhispurrApp/OnboardingHowItWorks.swift
git commit -m "feat: onboarding step 1 — how it works"
```

---

## Task 6: Permissions step view (extracted)

**Files:**
- Create: `Sources/WhispurrApp/OnboardingPermissions.swift`

- [ ] **Step 1: Create the view**

This is the permission grid + fn hint + AI status + model progress lifted from the current `OnboardingView` (which Task 11 removes). Create `Sources/WhispurrApp/OnboardingPermissions.swift`:
```swift
import SwiftUI

struct OnboardingPermissions: View {
    @ObservedObject var vm: PermissionsViewModel

    var body: some View {
        VStack(spacing: 14) {
            VStack(spacing: 9) {
                ForEach(PermissionsViewModel.Item.allCases) { item in
                    HStack(spacing: 12) {
                        Image(systemName: vm.granted(item) ? "checkmark.circle.fill" : "circle")
                            .font(.system(size: 16))
                            .foregroundStyle(vm.granted(item) ? Color.green : Color.secondary.opacity(0.5))
                            .contentTransition(.symbolEffect(.replace))
                            .symbolEffect(.bounce, value: vm.granted(item))
                            .animation(.spring(response: 0.3, dampingFraction: 0.6), value: vm.granted(item))
                        VStack(alignment: .leading, spacing: 1) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                            Text(item.why).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                        Spacer()
                        if !vm.granted(item) {
                            Button(L10n.t(.obGrant)) { vm.grant(item) }
                                .controlSize(.small).buttonStyle(.bordered).tint(UIStyle.accent)
                        }
                    }
                    .padding(.horizontal, 14).padding(.vertical, 9)
                    .background(Color.white.opacity(0.66), in: RoundedRectangle(cornerRadius: UIStyle.cardRadius))
                    .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius).strokeBorder(.white.opacity(0.7)))
                    .shadow(color: .black.opacity(0.05), radius: 3, y: 2)
                }
            }

            VStack(spacing: 6) {
                HStack {
                    Text(L10n.t(.obFnHint)).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L10n.t(.obOpenKeyboard)) { vm.openKeyboardSettings() }
                        .controlSize(.small).buttonStyle(.borderless)
                }
                HStack(spacing: 6) {
                    Image(systemName: vm.appleIntelligence ? "sparkles" : "sparkles.slash")
                        .foregroundStyle(vm.appleIntelligence ? UIStyle.accent : .secondary)
                    Text(vm.appleIntelligence ? L10n.t(.obAIOn) : L10n.t(.obAIOff))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                }
            }

            if let p = vm.modelProgress {
                VStack(spacing: 4) {
                    ProgressView(value: p)
                    Text(L10n.t(.obModelDownloading, Int(p * 100)))
                        .font(.system(size: 11)).foregroundStyle(.secondary)
                }
            }
        }
        .padding(.horizontal, 24).padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { vm.startPolling(); vm.downloadModelIfNeeded() }
        .onDisappear { vm.stopPolling() }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Sources/WhispurrApp/OnboardingPermissions.swift
git commit -m "feat: onboarding step 2 — permissions (extracted)"
```

---

## Task 7: Key-settings step view

**Files:**
- Create: `Sources/WhispurrApp/OnboardingKeySettings.swift`

- [ ] **Step 1: Create the view**

Reuses the same pickers/toggle as the Settings window, bound to `SettingsViewModel`. Create `Sources/WhispurrApp/OnboardingKeySettings.swift`:
```swift
import SwiftUI
import WhispurrCore

struct OnboardingKeySettings: View {
    @ObservedObject var vm: SettingsViewModel

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text(L10n.t(.keySetupTitle)).font(.system(size: 12, weight: .bold)).foregroundStyle(.secondary)
            VStack(spacing: 10) {
                row(L10n.t(.fieldLanguage)) {
                    Picker("", selection: $vm.settings.language) {
                        ForEach(Language.allCases) { Text($0.nativeName).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                row(L10n.t(.fieldHotkey)) {
                    Picker("", selection: $vm.settings.hotkey) {
                        ForEach(HotkeyPreset.allCases) { Text(L10n.hotkey($0)).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                row(L10n.t(.fieldInsertion)) {
                    Picker("", selection: $vm.settings.insertionMode) {
                        ForEach(InsertionMode.allCases) { Text(L10n.insertion($0)).tag($0) }
                    }.labelsHidden().fixedSize()
                }
                row(L10n.t(.fieldCleanup)) {
                    Toggle("", isOn: $vm.settings.cleanupEnabled).labelsHidden()
                }
            }
            .padding(16)
            .background(Color.white.opacity(0.72), in: RoundedRectangle(cornerRadius: UIStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius).strokeBorder(.white.opacity(0.8)))
        }
        .padding(.horizontal, 24).padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private func row<Control: View>(_ label: String, @ViewBuilder _ control: () -> Control) -> some View {
        HStack {
            Text(label).font(.system(size: 13))
            Spacer()
            control()
        }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Sources/WhispurrApp/OnboardingKeySettings.swift
git commit -m "feat: onboarding step 3 — key settings"
```

---

## Task 8: Try-it step view

**Files:**
- Create: `Sources/WhispurrApp/OnboardingTryIt.swift`

Approach: a focused `TextEditor`. Because Whispurr inserts dictated text at the
frontmost cursor, holding `fn` while this field is focused lands the text right
here — a real end-to-end test, no coordinator wiring needed.

- [ ] **Step 1: Create the view**

Create `Sources/WhispurrApp/OnboardingTryIt.swift`:
```swift
import SwiftUI

struct OnboardingTryIt: View {
    @State private var text = ""
    @FocusState private var focused: Bool

    var body: some View {
        VStack(spacing: 14) {
            Text(L10n.t(.tryTitle)).font(.title3.bold())
            Text(L10n.t(.tryInstruction))
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center).fixedSize(horizontal: false, vertical: true)
            ZStack(alignment: .topLeading) {
                if text.isEmpty {
                    Text(L10n.t(.tryPlaceholder)).foregroundStyle(.secondary.opacity(0.7))
                        .padding(.horizontal, 8).padding(.vertical, 8).allowsHitTesting(false)
                }
                TextEditor(text: $text)
                    .focused($focused)
                    .font(.system(size: 14))
                    .scrollContentBackground(.hidden)
                    .padding(4)
            }
            .frame(height: 110)
            .background(Color.white.opacity(0.8), in: RoundedRectangle(cornerRadius: UIStyle.cardRadius))
            .overlay(RoundedRectangle(cornerRadius: UIStyle.cardRadius).strokeBorder(.white.opacity(0.8)))
        }
        .padding(.horizontal, 24).padding(.top, 28)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .onAppear { focused = true }
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Sources/WhispurrApp/OnboardingTryIt.swift
git commit -m "feat: onboarding step 4 — try it"
```

---

## Task 9: Done step view

**Files:**
- Create: `Sources/WhispurrApp/OnboardingDone.swift`

- [ ] **Step 1: Create the view**

Create `Sources/WhispurrApp/OnboardingDone.swift`:
```swift
import SwiftUI

struct OnboardingDone: View {
    var body: some View {
        VStack(spacing: 16) {
            if let cat = UIStyle.catImage("idle") {
                Image(nsImage: cat).resizable().aspectRatio(contentMode: .fit)
                    .frame(width: 78, height: 78)
                    .shadow(color: .black.opacity(0.12), radius: 6, y: 3)
            }
            Text(L10n.t(.doneTitle)).font(.title2.bold())
            Text(L10n.t(.doneBody))
                .font(.callout).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .frame(maxWidth: 320)
        }
        .padding(.horizontal, 24).padding(.top, 36)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Sources/WhispurrApp/OnboardingDone.swift
git commit -m "feat: onboarding step 5 — done"
```

---

## Task 10: `OnboardingFlow` container

**Files:**
- Create: `Sources/WhispurrApp/OnboardingFlow.swift`

- [ ] **Step 1: Create the flow**

Create `Sources/WhispurrApp/OnboardingFlow.swift`:
```swift
import SwiftUI

struct OnboardingFlow: View {
    @ObservedObject var perms: PermissionsViewModel
    @ObservedObject var settingsVM: SettingsViewModel
    let onFinish: () -> Void

    @State private var step = 0
    private let total = 5

    private var canAdvance: Bool {
        step == 1 ? perms.canStart : true   // permissions step gates Next
    }

    var body: some View {
        VStack(spacing: 0) {
            Group {
                switch step {
                case 0: OnboardingHowItWorks()
                case 1: OnboardingPermissions(vm: perms)
                case 2: OnboardingKeySettings(vm: settingsVM)
                case 3: OnboardingTryIt()
                default: OnboardingDone()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            Divider().opacity(0.4)

            HStack {
                if step > 0 {
                    Button(L10n.t(.navBack)) { withAnimation { step -= 1 } }
                        .buttonStyle(.borderless)
                }
                Spacer()
                HStack(spacing: 6) {
                    ForEach(0..<total, id: \.self) { i in
                        Circle().fill(i == step ? UIStyle.accent : Color.secondary.opacity(0.3))
                            .frame(width: 7, height: 7)
                    }
                }
                Spacer()
                Button(step == total - 1 ? L10n.t(.navFinish) : L10n.t(.navNext)) {
                    if step == total - 1 { onFinish() } else { withAnimation { step += 1 } }
                }
                .controlSize(.large).buttonStyle(.borderedProminent).tint(UIStyle.accent)
                .keyboardShortcut(.defaultAction)
                .disabled(!canAdvance)
            }
            .padding(.horizontal, 24).padding(.vertical, 14)
        }
        .frame(width: 440, height: 520)
        .background(UIStyle.softBackground)
        .environment(\.colorScheme, .light)
    }
}
```

- [ ] **Step 2: Verify it builds**

Run: `swift build`
Expected: `Build complete!`

- [ ] **Step 3: Commit**
```bash
git add Sources/WhispurrApp/OnboardingFlow.swift
git commit -m "feat: OnboardingFlow — 5-step wizard container + nav"
```

---

## Task 11: Wire the flow into the window + AppDelegate; remove old view

**Files:**
- Modify: `Sources/WhispurrApp/OnboardingWindow.swift`
- Delete: `Sources/WhispurrApp/OnboardingView.swift`
- Modify: `Sources/WhispurrApp/AppDelegate.swift`

- [ ] **Step 1: Rewrite OnboardingWindow to host the flow**

Replace `Sources/WhispurrApp/OnboardingWindow.swift` with:
```swift
import AppKit
import SwiftUI
import WhispurrCore

/// Owns the onboarding NSWindow. Reusable: `show()` brings it forward.
@MainActor final class OnboardingWindow {
    private var window: NSWindow?
    private let vm = PermissionsViewModel()
    private let settingsVM: SettingsViewModel
    private let store: SettingsStore

    /// Forwarded from the permissions VM: fires when Input Monitoring is granted
    /// so the app can re-arm the hotkey without a relaunch.
    var onInputMonitoringGranted: (() -> Void)? {
        didSet { vm.onInputMonitoringGranted = onInputMonitoringGranted }
    }

    init(store: SettingsStore) {
        self.store = store
        self.settingsVM = SettingsViewModel(store: store)
    }

    func show() {
        if let window {
            vm.startPolling()
            window.makeKeyAndOrderFront(nil)
            NSApp.activate(ignoringOtherApps: true)
            return
        }
        let view = OnboardingFlow(perms: vm, settingsVM: settingsVM) { [weak self] in
            self?.store.update { $0.hasCompletedOnboarding = true }
            self?.close()
        }
        let w = NSWindow(contentViewController: NSHostingController(rootView: view))
        w.title = L10n.t(.obWindowTitle)
        w.styleMask = [.titled, .closable]
        w.isReleasedWhenClosed = false
        w.center()
        window = w
        w.makeKeyAndOrderFront(nil)
        NSApp.activate(ignoringOtherApps: true)
    }

    func close() { window?.close() }
}
```

- [ ] **Step 2: Delete the superseded view**

Run: `git rm Sources/WhispurrApp/OnboardingView.swift`

- [ ] **Step 3: Update AppDelegate's onboarding construction + first-run gate**

In `Sources/WhispurrApp/AppDelegate.swift`:
- Change `private lazy var onboarding = OnboardingWindow()` to
  `private lazy var onboarding = OnboardingWindow(store: settingsStore)`.
- Replace the first-run `Task { ... onboarding.show() }` block (the one checking `snap.canDictate`/`modelReady`) with:
```swift
        // First run: show the setup wizard until the user finishes it.
        if !settings.hasCompletedOnboarding { onboarding.show() }
```
(`settings` is the existing `let settings = settingsStore.settings` near the top of `applicationDidFinishLaunching`.)

- [ ] **Step 4: Verify it builds + tests pass**

Run: `swift build && swift test`
Expected: `Build complete!` and all tests pass (including Task 1's).

- [ ] **Step 5: Commit**
```bash
git add Sources/WhispurrApp/OnboardingWindow.swift Sources/WhispurrApp/AppDelegate.swift
git commit -m "feat: host OnboardingFlow; gate first-run on hasCompletedOnboarding"
```

---

## Task 12: Live end-to-end verification

**Files:** none (manual verification)

- [ ] **Step 1: Build a signed preview and reset onboarding**

Run:
```bash
SIGN_IDENTITY="Developer ID Application: Frank Lin (766AZHGT3J)" scripts/package.sh >/dev/null 2>&1
defaults delete nono.today.whispurr whispurr.settings.v1 2>/dev/null || true   # force first-run
pkill -u "$(id -u)" -f "dist/Whispurr.app/Contents/MacOS/Whispurr"; sleep 1; open dist/Whispurr.app
```

- [ ] **Step 2: Walk the wizard**

Confirm, in order: (1) How-it-works renders; Next advances. (2) Permissions step — Next is disabled until all four are granted; grant them. (3) Key settings — change language/hotkey/insertion/cleanup; they persist. (4) Try-it — click the box, hold fn, speak; text lands in the box. (5) Done — Finish closes the window. Relaunch and confirm the wizard does NOT reappear (flag persisted). Confirm the Dock icon is present and clicking it opens Settings.

- [ ] **Step 3: Final commit (if any tweaks were needed)**

```bash
git add -A && git commit -m "chore: onboarding wizard live-verification tweaks"
```

---

## Self-Review

- **Spec coverage:** Steps 1–5 → Tasks 5–11 (how/perms/keysettings/tryit/done + flow + wiring). `hasCompletedOnboarding` → Task 1. Dock icon (LSUIElement, reopen, no-quit, main menu) → Tasks 3–4. "When it appears" → Task 11 Step 3. Advanced-settings-stay-out → honored (KeySettings only has the four). All covered.
- **Placeholder scan:** every code step shows complete code; no TBD/TODO.
- **Type consistency:** `OnboardingWindow(store:)`, `OnboardingFlow(perms:settingsVM:onFinish:)`, `OnboardingPermissions(vm: PermissionsViewModel)`, `OnboardingKeySettings(vm: SettingsViewModel)`, `hasCompletedOnboarding`, `openSettingsFromMenu`, `buildMainMenu(settingsTarget:settingsAction:)` are used consistently across tasks.
- **Note:** Permissions step gates Next on `perms.canStart` (permissions granted); the model download shows progress but doesn't hard-block, matching the current app's behavior.
