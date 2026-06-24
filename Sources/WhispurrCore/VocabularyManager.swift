import Foundation

/// Applies the user's deterministic find/replace rules to cleaned text, so
/// recurring jargon / proper nouns the recognizer keeps getting wrong can be
/// fixed without touching the model. Pure + Sendable for easy unit testing.
public struct VocabularyManager: Sendable {
    public let rules: [VocabularyRule]

    public init(rules: [VocabularyRule]) {
        self.rules = rules
    }

    /// Apply each rule in order. Empty `from` rules are skipped.
    public func apply(to text: String) -> String {
        var out = text
        for rule in rules where !rule.from.isEmpty {
            let options: String.CompareOptions = rule.caseSensitive ? [] : [.caseInsensitive]
            out = out.replacingOccurrences(of: rule.from, with: rule.to, options: options)
        }
        return out
    }
}
