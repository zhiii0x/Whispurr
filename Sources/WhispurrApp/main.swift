import AppKit

// macOS 26 (Tahoe) auto-stamps SF Symbols onto standard menu rows (Settings → gear,
// Quit → …) at *display* time and reads them back through NSMenuItem.image's getter,
// so clearing the image after the fact races and the icon visibly flashes in then out.
// There is no public NSMenuItem opt-out API; disable the feature at its source for this
// app — the programmatic equivalent of
//   defaults write nono.today.whispurr NSMenuEnableActionImages -bool NO
// Written to the app's persistent domain (not the registration domain) so AppKit sees
// it however it reads the key, and set before NSApplication builds any menu.
UserDefaults.standard.set(false, forKey: "NSMenuEnableActionImages")

let app = NSApplication.shared
let delegate = AppDelegate()
app.delegate = delegate
app.setActivationPolicy(.accessory)
app.run()
