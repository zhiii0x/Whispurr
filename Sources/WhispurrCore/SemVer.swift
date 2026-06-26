import Foundation

/// Minimal semantic-version comparison for the update checker. Parses tags like
/// "v0.1.2" or "0.1.2" into numeric components and compares them component-wise
/// (zero-padding the shorter one). Anything it can't parse compares as "not
/// newer", so a malformed or non-numeric tag never nags the user.
public enum SemVer {
    /// "v0.1.2" / "0.1.2" → `[0, 1, 2]`. `nil` if empty or any component isn't a
    /// non-negative integer.
    public static func parse(_ raw: String) -> [Int]? {
        var s = raw.trimmingCharacters(in: .whitespaces)
        if let first = s.first, first == "v" || first == "V" { s.removeFirst() }
        guard !s.isEmpty else { return nil }
        var out: [Int] = []
        for part in s.split(separator: ".", omittingEmptySubsequences: false) {
            guard let n = Int(part), n >= 0 else { return nil }
            out.append(n)
        }
        return out.isEmpty ? nil : out
    }

    /// Is `remote` a strictly higher version than `local`? Unparseable input on
    /// either side → `false` (never prompt on garbage).
    public static func isNewer(_ remote: String, than local: String) -> Bool {
        guard let r = parse(remote), let l = parse(local) else { return false }
        for i in 0..<max(r.count, l.count) {
            let rv = i < r.count ? r[i] : 0
            let lv = i < l.count ? l[i] : 0
            if rv != lv { return rv > lv }
        }
        return false
    }
}
