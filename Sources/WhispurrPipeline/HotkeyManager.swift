import Foundation
import CoreGraphics

/// Global push-to-talk via a listen-only CGEventTap on `flagsChanged`.
/// Requires Input Monitoring. Keep the callback trivial (flip state, dispatch);
/// never do work inline or the tap gets disabled by timeout.
@MainActor public final class HotkeyManager: HotkeySource {
    public var onPress: (() -> Void)?
    public var onRelease: (() -> Void)?

    private var detector: PushToTalkEdgeDetector
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var tapUserInfo: UnsafeMutableRawPointer?

    public init(detector: PushToTalkEdgeDetector = PushToTalkEdgeDetector()) {
        self.detector = detector
    }

    public func start() throws {
        guard tap == nil else { return }            // idempotent: already running

        guard CGPreflightListenEventAccess() else {
            CGRequestListenEventAccess()           // opens Settings; needs relaunch
            throw HotkeyError.inputMonitoringDenied
        }

        let mask: CGEventMask = (1 << CGEventType.flagsChanged.rawValue)
        // Retain self for the tap's lifetime; balanced in stop() (or below on failure).
        let userInfo = Unmanaged.passRetained(self).toOpaque()

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .listenOnly,
            eventsOfInterest: mask,
            callback: { _, type, event, refcon in
                guard let refcon else { return Unmanaged.passUnretained(event) }
                let manager = Unmanaged<HotkeyManager>.fromOpaque(refcon).takeUnretainedValue()
                manager.handle(type: type, event: event)
                return Unmanaged.passUnretained(event)   // listenOnly: never consume
            },
            userInfo: userInfo
        ) else {
            Unmanaged<HotkeyManager>.fromOpaque(userInfo).release()   // balance the retain
            throw HotkeyError.tapCreationFailed
        }

        self.tap = tap
        self.tapUserInfo = userInfo
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        self.runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
    }

    public func stop() {
        guard let tap else { return }
        CGEvent.tapEnable(tap: tap, enable: false)
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes)
        }
        CFMachPortInvalidate(tap)
        if let userInfo = tapUserInfo {
            Unmanaged<HotkeyManager>.fromOpaque(userInfo).release()
            tapUserInfo = nil
        }
        self.tap = nil
        self.runLoopSource = nil
    }

    /// Swap the trigger (e.g. the user picked a different push-to-talk key in
    /// settings), restarting the tap if it was running.
    public func reconfigure(detector newDetector: PushToTalkEdgeDetector) {
        let wasRunning = tap != nil
        stop()
        detector = newDetector
        if wasRunning { try? start() }
    }

    // The CGEventTap callback hops here on the main run loop.
    nonisolated private func handle(type: CGEventType, event: CGEvent) {
        // Re-arm if the system disabled the tap.
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            MainActor.assumeIsolated {
                if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
                // The disabled window may have swallowed a key-up. If we still
                // think the key is held, recover the in-flight cycle with a
                // synthetic release and clear the stuck state so the next press
                // works (otherwise dictation wedges in .listening forever).
                if detector.isHeld { onRelease?() }
                detector.reset()
            }
            return
        }
        guard type == .flagsChanged else { return }
        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let flags = event.flags.rawValue
        MainActor.assumeIsolated {
            switch detector.handleFlagsChanged(keyCode: keyCode, flags: flags) {
            case .press: onPress?()
            case .release: onRelease?()
            case .none: break
            }
        }
    }
}
