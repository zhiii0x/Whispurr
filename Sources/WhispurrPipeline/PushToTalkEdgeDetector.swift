import Foundation
import WhispurrCore

/// Derives press/release of a modifier-key push-to-talk trigger from
/// `flagsChanged` events (modifiers never emit keyDown/keyUp).
public struct PushToTalkEdgeDetector {
    public enum Edge: Equatable { case press, release, none }

    private let triggerKeyCode: Int64
    private let triggerFlag: UInt64
    private var isDown = false

    /// Defaults to the fn / 🌐 Globe key (keyCode 63, `maskSecondaryFn`).
    /// (Right Option would be keyCode 61, flag `0x00080000`.)
    public init(triggerKeyCode: Int64 = 63, triggerFlag: UInt64 = 0x00800000) {
        self.triggerKeyCode = triggerKeyCode
        self.triggerFlag = triggerFlag
    }

    /// Build from a user-chosen preset.
    public init(preset: HotkeyPreset) {
        self.init(triggerKeyCode: preset.keyCode, triggerFlag: preset.flag)
    }

    /// Whether the trigger is currently considered held.
    public var isHeld: Bool { isDown }

    public mutating func handleFlagsChanged(keyCode: Int64, flags: UInt64) -> Edge {
        guard keyCode == triggerKeyCode else { return .none }
        let flagSet = (flags & triggerFlag) != 0
        if flagSet, !isDown { isDown = true; return .press }
        if !flagSet, isDown { isDown = false; return .release }
        return .none
    }

    /// Clear the held state. Used when the event tap is re-armed after the system
    /// disabled it: any key-up edge during the disabled window was lost, so the
    /// detector must not stay stuck "down" (which would wedge dictation forever).
    public mutating func reset() { isDown = false }
}
