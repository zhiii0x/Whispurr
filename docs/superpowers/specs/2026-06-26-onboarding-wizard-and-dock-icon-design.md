# Onboarding setup wizard + persistent Dock icon

Date: 2026-06-26
Status: approved (pending spec review)

## Goal

A new user currently can't tell how to use Whispurr, and the menu-bar-only app
gives no Dock presence. Replace the single permission window with a **step-by-step
setup wizard** that teaches the core gesture, requests permissions in context, and
captures the key settings — so a first-run user is fully set up in one guided flow.
Also give the app a **persistent Dock icon** for discoverability.

## A. Setup wizard

A paged wizard (5 steps) replaces the current `OnboardingView`. Order is
deliberate: teach value first so the (scary-sounding) permissions feel justified —
better grant rate than asking cold.

1. **How it works** — cat hero + tagline, then a "怎麼用" card with three steps:
   `fn` keycap → hold fn · waveform → speak (Mandarin + English) · cursor → release,
   text appears at the cursor. A note: press `Esc` to cancel. (Mockup approved.)
   Next always enabled.
2. **Permissions** — the four TCC permissions (Input Monitoring, Microphone, Speech
   Recognition, Accessibility) with per-row "Grant" buttons + green checkmarks, plus
   the one-time zh-TW model download with a progress bar. **Next is gated until all
   are granted and the model is ready** (the existing `canStart`).
3. **Key settings** — Language, Hotkey, Insertion mode, Cleanup toggle. Bound to the
   same `SettingsStore`, so choices persist. Next always enabled.
4. **Try it** — "Hold fn and say something." The live coordinator runs; the
   recognized + cleaned text is shown inline so the user sees it work. Skippable
   (Next always enabled).
5. **Done** — "You're all set," a reminder that the cat lives in the menu bar / Dock
   and where to change settings later. Finish closes the wizard.

Navigation: Back / Next, a 5-dot progress indicator. Steps 2's Next is disabled
until ready; all others are always enabled.

### When it appears
- New `AppSettings.hasCompletedOnboarding` (Bool, default false; tolerant decode).
- On launch: show the wizard when `!hasCompletedOnboarding`.
- Finishing step 5 sets the flag true.
- The menu item that today opens permissions (and the Dock-icon click when nothing
  is set up) reopens the wizard at any time.
- If permissions are revoked later we do NOT auto-pop the wizard every launch; the
  hotkey simply no-ops and the menu/Dock give access to re-open it.

### Advanced settings stay out
Vocabulary, sound cues, launch-at-login, and max recording length remain in the
Settings window only — not in the wizard.

## B. Persistent Dock icon

- `LSUIElement` → false (static `Info.plist` + the plist `package.sh` generates), so
  the app is a regular Dock app: the cat icon shows in **both** Dock and menu bar.
- `applicationShouldHandleReopen(_:hasVisibleWindows:)` → when no window is visible,
  open Settings (or the wizard if `!hasCompletedOnboarding`); return true.
- `applicationShouldTerminateAfterLastWindowClosed` → false (keep running in the
  background after windows close; the menu-bar cat and hotkey stay live).
- Provide a minimal `NSApp.mainMenu`: an App menu (About Whispurr, Settings… ⌘,,
  Quit ⌘Q) and a standard Edit menu (so ⌘C/⌘V/⌘A/⌘Z work in the wizard/Settings text
  fields). Today, as an accessory app, there is no main menu.
- No functional regression: the `CGEventTap` hotkey and the status-item cat are
  unaffected by the activation-policy change.

## Architecture

- **New** `OnboardingFlow` view: owns `@State step`, renders the current step
  subview, and the Back/Next + progress-dots chrome.
- **New** step subviews: `HowItWorksStep`, `KeySettingsStep`, `TryItStep`,
  `DoneStep`. The **permissions** step reuses the current permission grid — extract
  it from `OnboardingView` into a reusable `PermissionsStep` view over the existing
  `PermissionsViewModel`.
- **Reuse** `PermissionsViewModel` (permissions + model download) and
  `SettingsViewModel`/`SettingsStore` (key settings) unchanged.
- **Modify** `OnboardingWindow` to host `OnboardingFlow`; size the window for the
  wizard (~420 wide, taller than today).
- **Modify** `AppDelegate`: activation policy, reopen handler,
  terminate-after-last-window, build the main menu, and the first-run logic keyed on
  `hasCompletedOnboarding`. The Try-it step needs the coordinator, which already
  exists in `AppDelegate`.
- **Modify** `AppSettings` (+ `hasCompletedOnboarding`), `L10n` (step copy, nav,
  try-it, done), `Info.plist` + `scripts/package.sh` (`LSUIElement` false).
- The current `OnboardingView` is superseded by the flow + extracted permissions
  step.

## Testing

- Unit: `AppSettings` tolerant-decode test for the new `hasCompletedOnboarding`
  field (missing key → false). Existing `PermissionsViewModel`/settings logic
  unchanged.
- The wizard UI is verified by rendering each step to PNG and by running the signed
  build live (the project's established approach).

## Out of scope / non-goals

- No change to the dictation pipeline, recognition, or cleanup.
- No "skip permissions" — they remain required to pass step 2.
- Advanced settings are not duplicated into the wizard.
