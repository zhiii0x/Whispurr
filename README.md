<a id="english"></a>

<p align="center">
  <img src="assets/logo.png" width="150" alt="Whispurr logo">
</p>

<h1 align="center">Whispurr</h1>

<p align="center">
  A local, <strong>offline</strong> macOS menu-bar dictation app — Mandarin&nbsp;+&nbsp;English —<br>
  with a pixel tuxedo-cat that wears headphones while it listens.
</p>

<p align="center">
  <strong>English</strong> · <a href="#traditional-chinese">繁體中文</a>
</p>

<p align="center">
  <a href="https://github.com/zhiii0x/whispurr/releases/latest"><img alt="Latest release" src="https://img.shields.io/github/v/release/zhiii0x/whispurr?color=3b82f6"></a>
  <a href="https://github.com/zhiii0x/whispurr/releases/latest"><img alt="Requires macOS 26 Tahoe" src="https://img.shields.io/badge/macOS-26%20Tahoe-7c6aa6"></a>
</p>

<p align="center">
  <a href="https://buymeacoffee.com/nono.today"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="44" alt="Buy Me a Coffee"></a>
</p>

<p align="center">
  <img src="assets/hud.png" width="540" alt="Live dictation HUD showing mixed Mandarin + English">
</p>

Hold **`fn`**, speak Mandarin with English tech terms mixed in, release — your words are
recognised **on-device** and inserted at your cursor in whatever app is focused. Optionally,
**on-device** Apple Intelligence tidies them up (punctuation, sentence breaks, fillers removed —
English terms kept, Traditional Chinese out). Nothing — no audio, no text — ever leaves your Mac.

---

## Quickstart

1. **[Download the latest `.dmg`](https://github.com/zhiii0x/whispurr/releases/latest)** → open it → drag **Whispurr** into Applications.
2. Launch **Whispurr** — it lives in your menu bar. The welcome window walks you through four permissions (Input Monitoring, Microphone, Speech Recognition, Accessibility).
3. **Hold `fn`, talk, release.** Clean text lands at your cursor. Press **`Esc`** to cancel a take.

> Tip: In **System Settings → Keyboard → "Press Globe key to"**, choose **Do Nothing** so macOS doesn't hijack `fn`. Prefer another key? Pick Right Option or Right Command in Settings.

The app is **Developer-ID signed and notarized by Apple**, so the DMG opens with no Gatekeeper warning.

<p align="center">
  <img src="assets/states.png" width="640" alt="Cat states: idle, listening, cleaning up">
</p>

---

## Why Whispurr

- **Fully local / offline.** On-device speech recognition + on-device LLM cleanup. No cloud, no account, no telemetry. The recognised text is never even written to the system log.
- **Mandarin + English code-switching**, first-class. *"幫我 push 這個 commit"* stays exactly that — Traditional Chinese with English tech terms intact.
- **Optional polish (opt-in).** Turn on Apple Intelligence cleanup to remove fillers (嗯/呃/um/uh), add punctuation, and split run-on sentences (斷句) — edit-only, never inventing. Off by default, so dictation works immediately even without Apple Intelligence (the raw transcript is inserted).
- **Push-to-talk.** Hold a key, release to insert. A floating HUD shows the live transcript while you speak.
- **A delightful menu-bar cat** that puts on headphones to listen and closes its eyes to think.
- **English / 中文 UI**, switchable in Settings (defaults to English).

---

## Screenshots

<table>
<tr>
<td width="50%" valign="top">
  <img src="assets/onboarding.png" alt="First-run permissions window">
  <p align="center"><em>Guided setup — permissions + optional Apple Intelligence</em></p>
</td>
<td width="50%" valign="top">
  <img src="assets/settings.png" alt="Settings window">
  <p align="center"><em>One settings window — dictation, cleanup, vocabulary, permissions</em></p>
</td>
</tr>
</table>

---

## How it works

```
fn > AudioCapture > SpeechTranscriber > TextCleanup > Vocabulary > TextInserter
 |       (mic)        (Apple, zh-TW)     (Foundation   (your rules)  (paste/type)
 |                                        Models)
 +------------- DictationCoordinator (state machine) ----------------+
                              |
                     menu-bar cat + floating HUD
```

- **Recognition** — Apple `SpeechAnalyzer` / `SpeechTranscriber` (macOS 26), biased toward your tech vocabulary via contextual strings. Runs on the Neural Engine.
- **Cleanup** — Apple `FoundationModels` on-device LLM, with a strict edit-only prompt, a length guardrail (so it never "answers" your dictation), and a graceful fall-back to the raw transcript.
- **Insertion** — pasteboard + synthetic Command-V by default (the dictated text is tagged transient/concealed so it isn't synced via Universal Clipboard or grabbed by clipboard managers), with a simulate-typing mode for IME-sensitive fields.
- **Hotkey** — a listen-only `CGEventTap`, so it fires even inside self-drawn apps (VS Code, Zed, Electron).

---

## Settings

| | |
|---|---|
| **Language** | English / 中文 (UI only — dictation output stays Traditional Chinese) |
| **Hotkey** | fn, Right Option, or Right Command |
| **Insertion** | Paste (Command-V), or Simulate typing (no clipboard, IME-safe) |
| **Cleanup** | Off by default — opt in to polish with Apple Intelligence (punctuation, 斷句, filler removal) |
| **Vocabulary** | Find/replace rules applied after cleanup (and fed back as recognizer hints) |
| **Also** | sound cues, launch-at-login, max recording length, restore-clipboard |

---

## Requirements

**Required**
- **macOS 26 (Tahoe)** on an **Apple Silicon** Mac (M1 or later)
- Microphone, Speech Recognition, Input Monitoring (for `fn`), and Accessibility (to insert text) permissions

**Recommended**
- **Apple Intelligence** enabled for the optional on-device cleanup (punctuation, 斷句, filler removal). Off by default — the app works without it.
- For snappy cleanup, an **M4-class** Mac. Cleanup runs on the Neural Engine, which is roughly the same across M1 / M1 Pro / M1 Max but ~3× faster on M4 — so the chip **generation** matters more than the tier. M1–M3 work fine, but cleanup adds noticeable latency.
- The zh-TW speech model downloads once on first run (one-time, with a progress bar).

---

## Build from source

```sh
git clone https://github.com/zhiii0x/whispurr.git
cd whispurr
swift test           # run the unit tests
swift run Whispurr   # launch the menu-bar app (hold fn to dictate)
```

Diagnostics go to the unified log (no transcript content):
`log stream --predicate 'subsystem == "nono.today.whispurr"'`

## Package a release

```sh
# ad-hoc, local:
scripts/package.sh                            # -> dist/Whispurr.app

# Developer-ID signed + notarized + stapled, styled DMG:
SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=... \
MAKE_DMG=1 VERSION=0.1.0 scripts/package.sh   # -> dist/Whispurr-0.1.0.dmg
```

`scripts/make-icon.sh` builds the app icon, `scripts/make-dmg.sh` the styled install DMG, and `scripts/make-readme-assets.swift` renders the images above. Hardened-Runtime entitlements are in `Whispurr.entitlements`; the app is intentionally **not** sandboxed (the hotkey + text injection need it).

---

## Architecture

Three layers, dependency-injected behind protocols and unit-tested:

- **`WhispurrCore`** — pure logic: state machine, settings, vocabulary, transcript joining, logging.
- **`WhispurrPipeline`** — system integration: hotkey, permissions, audio, recognition, cleanup, insertion, coordinator.
- **`WhispurrApp`** — AppKit menu bar + SwiftUI panels, wired from a settings snapshot in `AppAssembly`.

---

<a id="traditional-chinese"></a>

<p align="center">
  <img src="assets/logo.png" width="150" alt="Whispurr logo">
</p>

<h1 align="center">Whispurr</h1>

<p align="center">
  一款在本機、<strong>完全離線</strong>的 macOS 選單列語音聽寫工具——中文&nbsp;+&nbsp;英文——<br>
  還有一隻會戴上耳機聆聽的像素燕尾貓。
</p>

<p align="center">
  <a href="#english">English</a> · <strong>繁體中文</strong>
</p>

<p align="center">
  <a href="https://github.com/zhiii0x/whispurr/releases/latest"><img alt="最新版本" src="https://img.shields.io/github/v/release/zhiii0x/whispurr?color=3b82f6"></a>
  <a href="https://github.com/zhiii0x/whispurr/releases/latest"><img alt="需要 macOS 26 Tahoe" src="https://img.shields.io/badge/macOS-26%20Tahoe-7c6aa6"></a>
</p>

<p align="center">
  <a href="https://buymeacoffee.com/nono.today"><img src="https://cdn.buymeacoffee.com/buttons/v2/default-yellow.png" height="44" alt="Buy Me a Coffee"></a>
</p>

<p align="center">
  <img src="assets/hud.png" width="540" alt="即時聽寫 HUD，顯示中英混用">
</p>

按住 **`fn`**，用中文夾雜英文技術詞彙說話，放開——你說的話會在**本機**辨識，然後插入到目前游標所在的任何 app。
另可選擇開啟**本機** Apple Intelligence 整稿（補標點、斷句、移除口頭禪；英文詞彙原樣保留、輸出繁體中文）。
沒有任何聲音或文字會離開你的 Mac。

---

## 快速開始

1. **[下載最新的 `.dmg`](https://github.com/zhiii0x/whispurr/releases/latest)** → 打開 → 把 **Whispurr** 拖進 Applications。
2. 啟動 **Whispurr**——它住在選單列。歡迎視窗會帶你完成四項權限（輸入監控、麥克風、語音辨識、輔助使用）。
3. **按住 `fn` 說話、放開。** 乾淨的文字會出現在游標處。按 **`Esc`** 取消這一次。

> 小技巧：到 **系統設定 → 鍵盤 →「按下 Globe 鍵時」**，選「**不執行任何動作**」，fn 才不會被 macOS 搶走。想用別的鍵？在設定裡選「右 Option」或「右 Command」。

本 app 經過 **Developer ID 簽章並由 Apple 公證**，所以 DMG 打開不會跳 Gatekeeper 警告。

<p align="center">
  <img src="assets/states.png" width="640" alt="貓咪狀態：閒置、聆聽、整理中">
</p>

---

## 為什麼用 Whispurr

- **完全本機 / 離線。** 本機語音辨識 + 本機 LLM 整稿。無雲端、無帳號、無遙測。辨識出來的文字連系統 log 都不會寫入。
- **中英 code-switching 一等公民。** 「幫我 push 這個 commit」就是這樣——繁體中文，英文技術詞彙原樣保留。
- **選用的自動整稿。** 開啟 Apple Intelligence 整稿即可移除口頭禪（嗯／呃／um／uh）、補上標點、把長句斷句——只做編輯、絕不杜撰。**預設關閉**,所以沒開 Apple Intelligence 也能直接用（插入原始稿）。
- **按住說話（push-to-talk）。** 按住一個鍵、放開即插入。說話時浮動 HUD 顯示即時逐字稿。
- **討喜的選單列貓咪**，聆聽時戴上耳機、思考時閉上眼睛。
- **英文 / 中文介面**，可在設定切換（預設英文）。

---

## 螢幕截圖

<table>
<tr>
<td width="50%" valign="top">
  <img src="assets/onboarding.png" alt="首次啟動的權限視窗">
  <p align="center"><em>首次啟動的設定引導——權限 + 選用的 Apple Intelligence</em></p>
</td>
<td width="50%" valign="top">
  <img src="assets/settings.png" alt="設定視窗">
  <p align="center"><em>單一設定視窗——聽寫、整稿、詞彙、權限</em></p>
</td>
</tr>
</table>

---

## 運作方式

```
fn > AudioCapture > SpeechTranscriber > TextCleanup > Vocabulary > TextInserter
 |      (麥克風)      (Apple, zh-TW)     (Foundation   (你的規則)    (貼上/輸入)
 |                                        Models)
 +------------- DictationCoordinator（狀態機）----------------+
                              |
                     選單列貓咪 + 浮動 HUD
```

- **辨識** — Apple `SpeechAnalyzer` / `SpeechTranscriber`（macOS 26），透過 contextual strings 偏向你的技術詞彙，跑在 Neural Engine 上。
- **整稿** — Apple `FoundationModels` 本機 LLM，使用嚴格的「只編輯」prompt、長度護欄（避免它「回答」你的口述），失敗時優雅退回原始稿。
- **插入** — 預設用剪貼簿 + 合成 Command-V（口述文字會標記為 transient/concealed，不會被 Universal Clipboard 同步、也不會被剪貼簿管理員收錄）；IME 敏感欄位可改用模擬輸入。
- **熱鍵** — 監聽用的 `CGEventTap`，所以即使在自繪 app（VS Code、Zed、Electron）裡也能觸發。

---

## 設定

| | |
|---|---|
| **語言** | 英文 / 中文（僅介面——口述輸出維持繁體中文）|
| **熱鍵** | fn、右 Option、右 Command |
| **插入方式** | 貼上（Command-V），或模擬輸入（不碰剪貼簿、適合 IME）|
| **整稿** | 預設關閉——可選擇開啟，用 Apple Intelligence 補標點、斷句、去贅字 |
| **詞彙** | 整稿後套用的 find/replace 規則（同時回饋給辨識器當提示）|
| **其他** | 提示音、開機自動啟動、單次最長錄音、插入後還原剪貼簿 |

---

## 系統需求

**必要**
- **macOS 26（Tahoe）**，且為 **Apple Silicon** Mac（M1 以上）
- 麥克風、語音辨識、輸入監控（fn 熱鍵）、輔助使用（插入文字）權限

**建議**
- 開啟 **Apple Intelligence** 以使用選用的本機整稿（補標點、斷句、去贅字）。**預設關閉**——沒開也能用。
- 想要整稿夠順,建議 **M4 世代** 的 Mac。整稿跑在 Neural Engine 上,而 ANE 在 M1／M1 Pro／M1 Max 其實差不多,到 M4 才約快 3 倍——所以**晶片世代**比等級（Max/Ultra）更重要。M1～M3 能用,但整稿延遲較明顯。
- 繁中語音模型於首次使用時下載一次（一次性,有進度條）。

---

## 從原始碼建置

```sh
git clone https://github.com/zhiii0x/whispurr.git
cd whispurr
swift test           # 跑單元測試
swift run Whispurr   # 啟動選單列 app（按住 fn 聽寫）
```

診斷訊息會寫到統一日誌（不含逐字稿內容）：
`log stream --predicate 'subsystem == "nono.today.whispurr"'`

## 打包發行

```sh
# 本機 ad-hoc 簽章：
scripts/package.sh                            # -> dist/Whispurr.app

# Developer-ID 簽章 + 公證 + staple、含美化的 DMG：
SIGN_IDENTITY="Developer ID Application: ..." NOTARY_PROFILE=... \
MAKE_DMG=1 VERSION=0.1.0 scripts/package.sh   # -> dist/Whispurr-0.1.0.dmg
```

`scripts/make-icon.sh` 產生 app icon、`scripts/make-dmg.sh` 產生美化的安裝 DMG、`scripts/make-readme-assets.swift` 算出上面這些圖。Hardened-Runtime entitlements 在 `Whispurr.entitlements`；本 app **刻意不沙盒**（熱鍵與文字插入需要）。

---

## 架構

三層，透過 protocol 注入並有單元測試：

- **`WhispurrCore`** — 純邏輯：狀態機、設定、詞彙、逐字稿接合、logging。
- **`WhispurrPipeline`** — 系統整合：熱鍵、權限、音訊、辨識、整稿、插入、coordinator。
- **`WhispurrApp`** — AppKit 選單列 + SwiftUI 面板，從設定快照在 `AppAssembly` 組裝。

