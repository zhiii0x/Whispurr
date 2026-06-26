import Foundation
import WhispurrCore

/// One-shot, anonymous check against the project's latest GitHub release.
///
/// This is the app's only outbound network call, so it is deliberately minimal:
/// a single HTTPS GET to GitHub's public API, no identifiers, no telemetry, no
/// payload. It runs ONLY when the user enables automatic checks or taps "Check
/// for Updates" by hand. Any failure collapses to `.failed` so a flaky network
/// never interrupts the app.
public enum UpdateCheck {
    public enum Outcome: Sendable, Equatable {
        case upToDate
        case available(version: String, url: URL)
        case failed
    }

    public static func latest(currentVersion: String,
                              repo: String = "zhiii0x/Whispurr",
                              session: URLSession = .shared) async -> Outcome {
        guard let api = URL(string: "https://api.github.com/repos/\(repo)/releases/latest") else {
            return .failed
        }
        var req = URLRequest(url: api)
        req.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        req.timeoutInterval = 10
        do {
            let (data, resp) = try await session.data(for: req)
            guard let http = resp as? HTTPURLResponse, http.statusCode == 200 else { return .failed }
            let release = try JSONDecoder().decode(Release.self, from: data)
            // `releases/latest` already excludes drafts and pre-releases.
            guard SemVer.isNewer(release.tag_name, than: currentVersion),
                  let url = URL(string: release.html_url) else { return .upToDate }
            let display = SemVer.parse(release.tag_name).map { $0.map(String.init).joined(separator: ".") }
                ?? release.tag_name
            return .available(version: display, url: url)
        } catch {
            return .failed
        }
    }

    private struct Release: Decodable {
        let tag_name: String
        let html_url: String
    }
}
