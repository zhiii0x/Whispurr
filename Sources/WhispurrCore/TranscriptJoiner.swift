import Foundation

/// Joins consecutive finalized recognizer segments. The recognizer can deliver
/// a transcript as several `onFinal` chunks; naive `+=` can glue two English
/// tokens ("pull"+"request" → "pullrequest"). This inserts a single space ONLY
/// at an ASCII-word↔ASCII-word boundary, keeping CJK joins tight and never
/// introducing double spaces.
public enum TranscriptJoiner {
    public static func join(_ accumulated: String, _ next: String) -> String {
        guard let last = accumulated.last, let first = next.first else {
            return accumulated + next            // either side empty → nothing to space
        }
        if last.isWhitespace || first.isWhitespace {
            return accumulated + next            // a side already provides the boundary
        }
        if isASCIIWord(last) && isASCIIWord(first) {
            return accumulated + " " + next
        }
        return accumulated + next
    }

    private static func isASCIIWord(_ c: Character) -> Bool {
        c.isASCII && (c.isLetter || c.isNumber)
    }
}
