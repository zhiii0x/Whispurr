import SwiftUI
import WhispurrCore
import WhispurrPipeline

/// App identity read from the packaged Info.plist.
enum AppInfo {
    /// Marketing version, e.g. "0.1.2". "0.0.0" under `swift run` (no Info.plist),
    /// which makes any real release compare as newer — harmless in dev.
    static var version: String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "0.0.0"
    }
    static var displayVersion: String { "v\(version)" }
}

/// Drives the "Check for Updates" row in Settings. Holds only the transient UI
/// state; the network call lives in `UpdateCheck`.
@MainActor final class UpdateModel: ObservableObject {
    enum State: Equatable {
        case idle, checking, upToDate, failed
        case available(version: String, url: URL)
    }

    @Published private(set) var state: State = .idle

    func check() {
        guard state != .checking else { return }
        state = .checking
        Task {
            switch await UpdateCheck.latest(currentVersion: AppInfo.version) {
            case .upToDate:                 state = .upToDate
            case .available(let v, let u):  state = .available(version: v, url: u)
            case .failed:                   state = .failed
            }
        }
    }
}
