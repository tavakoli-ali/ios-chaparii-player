#if os(iOS)
import Foundation

extension LibraryManager {
    /// On iOS the library source is the app's own Documents folder, populated by
    /// the user via File Sharing (Finder / Files app). Registers Documents as a
    /// library folder (once), scans it, then loads tracks into memory. Safe to call
    /// repeatedly (launch + pull-to-refresh).
    func ensureDocumentsFolderAndScan() {
        let docs = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]

        Task { @MainActor in
            let folder: Folder
            if let existing = folders.first(where: { $0.url.standardizedFileURL == docs.standardizedFileURL }) {
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
