import Foundation

/// Describes which image frames represent each dictation state, plus an
/// SF Symbol fallback used until real pixel-art PNGs are bundled.
public struct CatSpriteSet: Sendable {
    public init() {}

    /// Ordered frame file names (without extension) for a state.
    /// Multiple names mean an animation loop; a single name is static.
    public func frames(for state: DictationState) -> [String] {
        switch state {
        case .idle:       return ["idle"]
        case .listening:  return ["listening"]
        case .processing: return ["processing"]
        case .error:      return ["idle"] // reuse idle art + a badge until a dedicated frame exists
        }
    }

    /// Whether the state needs an animation timer (more than one frame).
    public func shouldAnimate(_ state: DictationState) -> Bool {
        frames(for: state).count > 1
    }

    /// SF Symbol name shown when no PNG frame is bundled yet.
    public func sfSymbolFallback(for state: DictationState) -> String {
        switch state {
        case .idle:       return "cat"
        case .listening:  return "headphones"
        case .processing: return "waveform"
        case .error:      return "exclamationmark.triangle"
        }
    }
}
