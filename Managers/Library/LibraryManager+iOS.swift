#if os(iOS)
import Foundation

extension LibraryManager {
    /// On iOS the library source is the app's own Documents folder, populated by
    /// the user via File Sharing (Finder / Files app). Registers Documents as a
    /// library folder (once), scans it, then loads tracks into memory. Safe to call
    /// repeatedly (launch + pull-to-refresh).
    func ensureDocumentsFolderAndScan(onScanComplete: (@MainActor () async -> Void)? = nil) {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0].standardizedFileURL

        Task { @MainActor in
            // Self-heal: iOS changes the app's Documents container path on every
            // (re)install, which leaves stale folder rows behind (each pointing at a
            // dead container) and their track rows carrying dead absolute paths.
            // Keep only the folder for the *current* Documents; remove the rest,
            // which cascades their tracks. `folder.url` is the raw stored path (not
            // the resolved bookmark), so this reliably identifies stale rows.
            let stale = folders.filter { $0.url.standardizedFileURL.path != docs.path }
            for folder in stale {
                await withCheckedContinuation { continuation in
                    databaseManager.removeFolder(folder) { _ in continuation.resume() }
                }
            }
            if !stale.isEmpty {
                let staleIds = Set(stale.compactMap { $0.id })
                folders.removeAll { staleIds.contains($0.id ?? -1) }
                Logger.info("iOS: pruned \(stale.count) stale Documents folder(s) from a prior install")
            }

            // Ensure exactly one folder registration for the current Documents.
            let folder: Folder
            if let existing = folders.first(where: { $0.url.standardizedFileURL.path == docs.path }) {
                folder = existing
            } else {
                let bookmark = try? docs.bookmarkData(options: [], includingResourceValuesForKeys: nil, relativeTo: nil)
                let map: [URL: Data] = bookmark.map { [docs: $0] } ?? [:]
                do {
                    let added = try await databaseManager.addFoldersAsync([docs], bookmarkDataMap: map)
                    guard let first = added.first else { return }
                    folder = first
                    folders = added + folders
                } catch {
                    Logger.error("iOS: failed to register Documents folder: \(error)")
                    return
                }
            }

            // Scan the folder (await completion) then load tracks into memory.
            await withCheckedContinuation { continuation in
                databaseManager.refreshFolder(
                    folder,
                    hardRefresh: true,
                    manageActivityIndicator: false,
                    globalScanState: nil
                ) { _ in continuation.resume() }
            }

            await reloadTracksFromDatabase()
            await onScanComplete?()
        }
    }

    /// Force-loads all tracks from the DB into `tracks` (unlike `loadAllTracks`,
    /// which no-ops when `tracks` is already non-empty).
    @MainActor
    func reloadTracksFromDatabase() async {
        let loaded = await Task.detached { self.databaseManager.getAllTracks() }.value
        tracks = loaded
        updateSearchResults()
        refreshLibraryCategories()
    }
}
#endif
