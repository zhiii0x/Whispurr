import SwiftUI
import AppKit

/// Shared visual tokens so the HUD + onboarding stay consistent.
/// Cozy / cute direction with a blue signature accent (= the cat's headphones).
enum UIStyle {
    static let accent = Color(red: 0.231, green: 0.510, blue: 0.965)   // #3b82f6

    static let hudRadius: CGFloat = 18
    static let cardRadius: CGFloat = 14

    /// HUD card — soft dark plum gradient.
    static var hudBackground: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.357, green: 0.290, blue: 0.420),   // #5b4a6b
                     Color(red: 0.278, green: 0.227, blue: 0.341)],  // #473a57
            startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// Onboarding backdrop — warm pink → cool blue.
    static var softBackground: LinearGradient {
        LinearGradient(
            colors: [Color(red: 0.937, green: 0.913, blue: 0.965),   // #efe9f6
                     Color(red: 0.914, green: 0.933, blue: 0.969)],  // #e9eef7
            startPoint: .top, endPoint: .bottom)
    }

    /// Load a bundled cat frame as an NSImage (e.g. "listening", "menubar-listening").
    static func catImage(_ name: String) -> NSImage? {
        guard let url = Bundle.module.url(forResource: name, withExtension: "png",
                                          subdirectory: "CatFrames") else { return nil }
        return NSImage(contentsOf: url)
    }
}
