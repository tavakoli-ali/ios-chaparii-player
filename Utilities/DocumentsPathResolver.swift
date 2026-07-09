import Foundation

/// Rebases stored library paths onto the app's *current* Documents directory.
///
/// On iOS the app's data-container UUID changes across installs (and can differ
/// between simulator runs), so absolute paths persisted in the database — e.g.
/// `…/Application/<OLD-UUID>/Documents/Album/Track.mp3` — stop resolving after a
/// reinstall, breaking file existence checks and playback. Since every library
/// file lives under Documents, we recover the live path by taking the portion
/// after the last `/Documents/` and rebasing it onto the current Documents URL.
///
/// On macOS paths are stable, so this is a no-op.
enum DocumentsPathResolver {
    static func resolve(_ path: String) -> String {
        #if os(iOS)
        guard let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
        else { return path }

        let marker = "/Documents/"
        guard let range = path.range(of: marker, options: .backwards) else { return path }

        let relative = String(path[range.upperBound...])
        // Already correct — avoid rebuilding an identical URL.
        if path.hasPrefix(docs.path + "/") { return path }
        return docs.appendingPathComponent(relative).path
        #else
        return path
        #endif
    }
}
