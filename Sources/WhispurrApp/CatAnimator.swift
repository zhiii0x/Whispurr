import AppKit
import WhispurrCore

/// Drives an `NSStatusItem` button's image to reflect the current state.
/// Loads bundled PNG frames when present; otherwise uses an SF Symbol.
/// The animation timer only runs for multi-frame states and is invalidated
/// the instant the cat returns to a static state (zero idle wakeups).
@MainActor final class CatAnimator {
    private weak var button: NSStatusBarButton?
    private let sprites = CatSpriteSet()
    private var timer: Timer?
    private var frames: [NSImage] = []
    private var index = 0
    private static let fps = 10.0
    private static let iconHeight: CGFloat = 18
    private var blinkTask: Task<Void, Never>?

    init(button: NSStatusBarButton) {
        self.button = button
    }

    func update(to state: DictationState) {
        timer?.invalidate()
        timer = nil
        blinkTask?.cancel()
        blinkTask = nil
        frames = loadFrames(for: state)
        index = 0
        button?.image = frames.first

        if sprites.shouldAnimate(state) && frames.count > 1 {
            let t = Timer(timeInterval: 1.0 / Self.fps, repeats: true) { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.advance()
                }
            }
            RunLoop.main.add(t, forMode: .common)
            timer = t
        } else if case .idle = state {
            scheduleIdleBlink()
        }
    }

    /// Occasional ambient blink while idle (~every 5s) — a touch of life with
    /// negligible wakeups. Cancelled the instant the state changes.
    private func scheduleIdleBlink() {
        guard let idleImage = frames.first, let blink = loadPNG("blink") else { return }
        blinkTask = Task { @MainActor [weak self] in
            while !Task.isCancelled {
                try? await Task.sleep(for: .seconds(5))
                if Task.isCancelled { return }
                self?.button?.image = blink
                try? await Task.sleep(for: .milliseconds(150))
                if Task.isCancelled { return }
                self?.button?.image = idleImage
            }
        }
    }

    private func advance() {
        guard !frames.isEmpty else { return }
        index = (index + 1) % frames.count
        button?.image = frames[index]
    }

    private func loadFrames(for state: DictationState) -> [NSImage] {
        let pngs = sprites.frames(for: state).compactMap(loadPNG)
        if !pngs.isEmpty { return pngs }
        return [symbolImage(for: state)]
    }

    private func loadPNG(_ name: String) -> NSImage? {
        // Menu bar uses the head-crop frames ("menubar-*") so the state (ears /
        // blue headphones / closed eyes) is legible at ~18 px. Full-body frames
        // are kept for the HUD + onboarding hero.
        guard let url = Bundle.module.url(
            forResource: "menubar-\(name)", withExtension: "png", subdirectory: "CatFrames"
        ), let image = NSImage(contentsOf: url) else { return nil }
        image.isTemplate = false
        // Preserve the cat's aspect ratio, sized to fit the menu bar height.
        if image.size.height > 0 {
            let width = (Self.iconHeight * image.size.width / image.size.height).rounded()
            image.size = NSSize(width: width, height: Self.iconHeight)
        }
        return image
    }

    private func symbolImage(for state: DictationState) -> NSImage {
        let name = sprites.sfSymbolFallback(for: state)
        let image = NSImage(systemSymbolName: name, accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "pawprint", accessibilityDescription: nil)
            ?? NSImage(systemSymbolName: "circle.fill", accessibilityDescription: nil)!
        image.isTemplate = true
        return image
    }
}
