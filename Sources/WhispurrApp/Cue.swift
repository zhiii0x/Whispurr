import AppKit

/// Subtle audible cues for recording start/stop. The start cue is kept short and
/// quiet so it doesn't bleed into the captured audio; the stop cue plays after
/// the mic is already closed.
@MainActor enum Cue {
    static func recordingStarted() { play("Tink") }
    static func recordingStopped() { play("Pop") }

    private static func play(_ name: String) {
        NSSound(named: NSSound.Name(name))?.play()
    }
}
