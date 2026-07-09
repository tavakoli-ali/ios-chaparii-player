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

        let fileNames = Set(playlistURLs.map { $0.deletingPathExtension().lastPathComponent.lowercased() })

        // Decide what to (re)import. A regular playlist that already has tracks is
        // left alone. A regular playlist that exists but is EMPTY and matches an
        // incoming file is stale — its track links were cascade-removed when the
        // iOS container changed and the library was re-scanned under new track IDs.
        // Delete those so the import rebuilds them from the .m3u8 (otherwise a
        // name-only "already imported" check leaves them permanently empty).
        var populated = Set<String>()
        var staleEmpty: [Playlist] = []
        if let db = libraryManager?.databaseManager {
            for playlist in playlists where playlist.type != .smart {
                let nameKey = playlist.name.lowercased()
                if !db.loadTracksForPlaylist(playlist.id).isEmpty {
                    populated.insert(nameKey)
                } else if fileNames.contains(nameKey) {
                    staleEmpty.append(playlist)
                }
            }
        }
        for playlist in staleEmpty {
            Logger.info("iOS: rebuilding empty playlist '\(playlist.name)' from its file")
            deletePlaylist(playlist)
        }

        let toImport = playlistURLs.filter {
            !populated.contains($0.deletingPathExtension().lastPathComponent.lowercased())
        }
        guard !toImport.isEmpty else {
            Logger.info("iOS: \(playlistURLs.count) playlist file(s) present, all already populated")
            return
        }

        Logger.info("iOS: auto-importing \(toImport.count) playlist file(s) from Documents")
        _ = await importPlaylists(from: toImport)
    }
}
#endif
