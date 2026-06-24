import Foundation
import os

/// Centralized logging. Diagnostic breadcrumbs use the unified log via os.Logger;
/// content-bearing logs (recognized/inserted text) are NEVER emitted publicly —
/// they are marked `.private` and only built in DEBUG, honoring the product's
/// "nothing leaves the Mac" promise (plain NSLog %@ would persist them publicly).
public enum Log {
    public static let subsystem = "tw.digilog.whispurr"

    public static let app      = Logger(subsystem: subsystem, category: "app")
    public static let pipeline = Logger(subsystem: subsystem, category: "pipeline")
    public static let audio    = Logger(subsystem: subsystem, category: "audio")
    public static let hotkey   = Logger(subsystem: subsystem, category: "hotkey")
    public static let cleanup  = Logger(subsystem: subsystem, category: "cleanup")

    /// Log user content (transcripts/partials). In release this records only a
    /// length so the spoken text never lands in the unified log; in DEBUG it is
    /// emitted but redacted as `.private` (hidden from `log show` without a
    /// profile). Use this for ANYTHING derived from what the user said.
    public static func content(_ label: String, _ text: String, to logger: Logger) {
        #if DEBUG
        logger.debug("\(label, privacy: .public): \(text, privacy: .private)")
        #else
        logger.debug("\(label, privacy: .public): <\(text.count, privacy: .public) chars>")
        #endif
    }
}
