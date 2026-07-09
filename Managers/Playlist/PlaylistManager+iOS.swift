#if os(iOS)
import Foundation

extension PlaylistManager {
    /// Auto-imports `.m3u8` / `.m3u` playlists found anywhere in the app's
    /// Documents folder (populated via File Sharing). Idempotent: only imports
    /// files whose playlist name isn't already present, so repeated launches /
    /// rescans don't create duplicates. Entry matching falls back to filename,
    /// so it survives the iOS container-path changes handled elsewhere.
    func autoImportDocumentsPlaylists() async {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
        guard let enumerator = FileManager.default.enumerator(
            at: docs,
            includingPropertiesForKeys: nil,
            options: [.skipsHiddenFiles]
        ) else { return }

        var playlistURLs: [URL] = []
        for case let url as URL in enumerator {
            let ext = url.pathExtension.lowercased()
            if ext == "m3u8" || ext == "m3u" { playlistURLs.append(url) }
        }
        guard !playlistURLs.isEmpty else { return }

        let existing = Set(playlists.map { $0.name.lowercased() })
        let toImport = playlistURLs.filter {
            !existing.contains($0.deletingPathExtension().lastPathComponent.lowercased())
        }
        guard !toImport.isEmpty else {
            Logger.info("iOS: \(playlistURLs.count) playlist file(s) present, all already imported")
            return
        }

        Logger.info("iOS: auto-importing \(toImport.count) playlist file(s) from Documents")
        _ = await importPlaylists(from: toImport)
    }
}
#endif
