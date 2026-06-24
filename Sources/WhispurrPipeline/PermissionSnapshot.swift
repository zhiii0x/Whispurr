import Foundation

public enum Permission: CaseIterable, Sendable {
    case microphone, speech, inputMonitoring, accessibility
}

/// Pure aggregation of the app's permission state. `canDictate` is the gate
/// for starting a dictation cycle; AI cleanup is optional.
public struct PermissionSnapshot: Sendable {
    public var microphone: Bool
    public var speech: Bool
    public var inputMonitoring: Bool
    public var accessibility: Bool
    public var appleIntelligence: Bool

    public init(microphone: Bool, speech: Bool, inputMonitoring: Bool,
                accessibility: Bool, appleIntelligence: Bool) {
        self.microphone = microphone
        self.speech = speech
        self.inputMonitoring = inputMonitoring
        self.accessibility = accessibility
        self.appleIntelligence = appleIntelligence
    }

    public var canDictate: Bool { missing.isEmpty }

    public var cleanupAvailable: Bool { appleIntelligence }

    public var missing: [Permission] {
        var out: [Permission] = []
        if !microphone { out.append(.microphone) }
        if !speech { out.append(.speech) }
        if !inputMonitoring { out.append(.inputMonitoring) }
        if !accessibility { out.append(.accessibility) }
        return out
    }
}
