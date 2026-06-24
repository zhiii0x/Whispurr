<p align="center">
  <img src="assets/logo.png" width="150" alt="Whispurr logo">
</p>

<h1 align="center">Whispurr</h1>

<p align="center">
  A local, <strong>offline</strong> macOS menu-bar dictation app — Mandarin&nbsp;+&nbsp;English —<br>
  with a pixel tuxedo-cat that wears headphones while it listens. 🐱🎧
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-26%20Tahoe-7c6aa6">
  <img src="https://img.shields.io/badge/Apple%20Silicon-arm64-555">
  <img src="https://img.shields.io/badge/Swift-6-f05138">
  <img src="https://img.shields.io/github/v/release/zhiii0x/whispurr?color=3b82f6">
  <img src="https://img.shields.io/badge/notarized-%E2%9C%93-2ea44f">
</p>

<p align="center">
  <img src="assets/hud.png" width="540" alt="Live dictation HUD showing mixed Mandarin + English">
</p>

Hold **`fn`**, speak Mandarin with English tech terms mixed in, release — your words are
recognised **on-device**, tidied up **on-device** (fillers removed, punctuation fixed,
English terms kept, Traditional Chinese out), and inserted at your cursor in whatever app
is focused. Nothing — no audio, no text — ever leaves your Mac.

---

## ⚡️ Quickstart

1. **[Download the latest `.dmg`](https://github.com/zhiii0x/whispurr/releases/latest)** → open it → drag **Whispurr** into Applications.
2. Launch **Whispurr** — it lives in your menu bar. The welcome window walks you through four permissions (Input Monitoring, Microphone, Speech Recognition, Accessibility).
3. **Hold `fn`, talk, release.** Clean text lands at your cursor. Press **`Esc`** to cancel a take.

> 💡 In **System Settings → Keyboard → "Press 🌐 key to"**, choose **Do Nothing** so macOS doesn't hijack `fn`. Prefer another key? Pick Right ⌥ / Right ⌘ in Settings.

The app is **Developer-ID signed and notarized by Apple**, so the DMG opens with no Gatekeeper warning.

<p align="center">
  <img src="assets/states.png" width="640" alt="Cat states: idle, listening, cleaning up">
</p>

---

## Why Whispurr

- 🔒 **Fully local / offline.** On-device speech recognition + on-device LLM cleanup. No cloud, no account, no telemetry. The recognised text is never even written to the system log.
- 🀄️ **Mandarin + English code-switching**, first-class. *"幫我 push 這個 commit"* stays exactly that — Traditional Chinese with English tech terms intact.
- ✨ **Always-polished output.** Apple Intelligence removes fillers (嗯/呃/um/uh), fixes punctuation, tidies grammar — edit-only, never inventing. (If Apple Intelligence is off, the raw transcript is inserted instead.)
- 🎙 **Push-to-talk.** Hold a key, release to insert. A floating HUD shows the live transcript while you speak.
- 🐱 **A delightful menu-bar cat** that puts on headphones to listen and closes its eyes to think.
- 🌐 **English / 中文 UI**, switchable in Settings (defaults to English).

---

## Screenshots

<table>
<tr>
<td width="50%" valign="top">
  <img src="assets/onboarding.png" alt="First-run permissions window">
  <p align="center"><em>Guided first-run permissions</em></p>
</td>
<td width="50%" valign="top">
  <img src="assets/settings.png" alt="Settings window">
  <p align="center"><em>Settings — hotkey, insertion, cleanup, vocabulary, language</em></p>
</td>
</tr>
</table>

---

## How it works

```
fn ▶ AudioCapture ▶ SpeechTranscriber ▶ TextCleanup ▶ Vocabulary ▶ TextInserter
 │       (mic)        (Apple, zh-TW)     (Foundation    (your rules)  (⌘V / type)
 │                                        Models)
 └────────────── DictationCoordinator (state machine) ───────────────┘
                              │
                     menu-bar cat + floating HUD
```

- **Recognition** — Apple `SpeechAnalyzer` / `SpeechTranscriber` (macOS 26), biased toward your tech vocabulary via contextual strings. Runs on the Neural Engine.
- **Cleanup** — Apple `FoundationModels` on-device LLM, with a strict edit-only prompt, a length guardrail (so it never "answers" your dictation), and a graceful fall-back to the raw transcript.
- **Insertion** — pasteboard + synthetic ⌘V by default (the dictated text is tagged transient/concealed so it isn't synced via Universal Clipboard or grabbed by clipboard managers), with a simulate-typing mode for IME-sensitive fields.
- **Hotkey** — a listen-only `CGEventTap`, so it fires even inside self-drawn apps (VS Code, Zed, Electron).

---

## Settings

| | |
|---|---|
| **Language** | English / 中文 (UI only — dictation output stays Traditional Chinese) |
| **Hotkey** | `fn` · Right ⌥ · Right ⌘ |
| **Insertion** | Paste (⌘V) · Simulate typing (no clipboard, IME-safe) |
| **Cleanup** | On (Apple Intelligence) / Off (raw, faster) |
| **Vocabulary** | Find/replace rules applied after cleanup (and fed back as recognizer hints) |
| **Also** | sound cues · launch-at-login · max recording length · restore-clipboard |

---

## Requirements

- **macOS 26 (Tahoe)** on **Apple Silicon**
- **Apple Intelligence** enabled for on-device cleanup *(optional — without it, the raw transcript is inserted)*
- The zh-TW speech model downloads once on first run (with a progress bar)

---

## Build from source

```sh
git clone https://github.com/zhiii0x/whispurr.git
cd whispurr
swift test           # run the unit tests
swift run Whispurr   # launch the menu-bar app (hold fn to dictate)
```

Diagnostics go to the unified log (no transcript content):
`log stream --predicate 'subsystem == "tw.digilog.whispurr"'`

## Package a release

```sh
# ad-hoc, local:
scripts/package.sh                            # → dist/Whispurr.app

# Developer-ID signed + notarized + stapled, styled DMG:
SIGN_IDENTITY="Developer ID Application: …" NOTARY_PROFILE=… \
MAKE_DMG=1 VERSION=0.1.0 scripts/package.sh   # → dist/Whispurr-0.1.0.dmg
```

`scripts/make-icon.sh` builds the app icon, `scripts/make-dmg.sh` the styled install DMG, and `scripts/make-readme-assets.swift` renders the images above. Hardened-Runtime entitlements are in `Whispurr.entitlements`; the app is intentionally **not** sandboxed (the hotkey + text injection need it).

---

## Architecture

Three layers, dependency-injected behind protocols and unit-tested:

- **`WhispurrCore`** — pure logic: state machine, settings, vocabulary, transcript joining, logging.
- **`WhispurrPipeline`** — system integration: hotkey, permissions, audio, recognition, cleanup, insertion, coordinator.
- **`WhispurrApp`** — AppKit menu bar + SwiftUI panels, wired from a settings snapshot in `AppAssembly`.

---

<p align="center"><sub>Made with 🐱 on an Apple M4 · Not yet open-source-licensed — please ask before reuse.</sub></p>
