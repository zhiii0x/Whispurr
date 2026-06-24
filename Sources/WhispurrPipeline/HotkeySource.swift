import Foundation

/// A source of push-to-talk press/release events. The coordinator depends on
/// this so it can be driven by a fake in tests.
@MainActor public protocol HotkeySource: AnyObject {
    var onPress: (() -> Void)? { get set }
    var onRelease: (() -> Void)? { get set }
    /// Throws if Input Monitoring is not granted / the tap cannot be created.
    func start() throws
    func stop()
}

public enum HotkeyError: Error { case inputMonitoringDenied, tapCreationFailed }
