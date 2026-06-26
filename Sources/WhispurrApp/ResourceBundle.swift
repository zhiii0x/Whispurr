import Foundation

extension Bundle {
    /// The SwiftPM resource bundle ("Whispurr_WhispurrApp.bundle") holding the
    /// CatFrames PNGs, resolved so it works in BOTH layouts:
    ///
    ///   • `swift run` / `swift build`  → bundle sits next to the bare binary
    ///   • the packaged `.app`          → bundle lives in `Contents/Resources/`
    ///
    /// We can't use the generated `Bundle.module`: for an *executable* target
    /// SwiftPM emits an accessor that only checks `Bundle.main.bundleURL`, which
    /// becomes the `.app` root once packaged — and a bundle placed there can't be
    /// code-signed ("unsealed contents present in the bundle root"). So it would
    /// only ever be found via a hard-coded dev `.build` path baked into the
    /// binary, crashing on every machine but the one that built it.
    ///
    /// `Bundle.main.resourceURL` is `Contents/Resources/` in the packaged app and
    /// the binary's own directory under `swift run`, so it covers both cases.
    /// Falls back to `.main` (assets simply won't resolve → SF Symbol fallback)
    /// rather than trapping.
    static let whispurrResources: Bundle = {
        let name = "Whispurr_WhispurrApp.bundle"
        let bases = [Bundle.main.resourceURL, Bundle.main.bundleURL]
        for base in bases {
            if let url = base?.appendingPathComponent(name), let bundle = Bundle(url: url) {
                return bundle
            }
        }
        return .main
    }()
}
