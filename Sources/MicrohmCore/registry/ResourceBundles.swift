import Foundation

/// SwiftPM resource bundles, found without `Bundle.module`. The generated accessor looks
/// only beside the main bundle and in the build folder it was compiled in, and traps when
/// neither has it: in the .app that `scripts/build-app.sh` makes, the bundles sit in
/// Contents/Resources, so `Bundle.module` crashes on every machine but the one that built
/// it. This looks in Contents/Resources, beside the executable (`swift run`, the e2e
/// tests) and beside the code's own bundle (`swift test`).
public enum ResourceBundles {

    private final class Marker {}

    /// The bundle named `name` (for example `Microhm_MicrohmCore.bundle`), or nil.
    public static func find(_ name: String) -> Bundle? {
        for url in candidates(name) where FileManager.default.fileExists(atPath: url.path) {
            if let bundle = Bundle(url: url) { return bundle }
        }
        return nil
    }

    /// Where `name` is looked for, in order.
    static func candidates(_ name: String) -> [URL] {
        var dirs: [URL?] = []
        for bundle in [Bundle.main, Bundle(for: Marker.self)] {
            let exeDir = bundle.executableURL?.resolvingSymlinksInPath().deletingLastPathComponent()
            dirs += [
                bundle.resourceURL,
                bundle.bundleURL,
                bundle.bundleURL.deletingLastPathComponent(),
                exeDir,
                exeDir?.deletingLastPathComponent().appendingPathComponent("Resources"),
            ]
        }
        var seen = Set<String>()
        return dirs.compactMap { $0?.appendingPathComponent(name) }
            .filter { seen.insert($0.standardizedFileURL.path).inserted }
    }

    /// A file or folder inside the bundle named `name`, if it exists.
    public static func url(_ name: String, _ relativePath: String) -> URL? {
        guard let bundle = find(name) else { return nil }
        let url = (bundle.resourceURL ?? bundle.bundleURL).appendingPathComponent(relativePath)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
