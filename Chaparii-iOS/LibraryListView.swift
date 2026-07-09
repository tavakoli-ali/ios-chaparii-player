import SwiftUI

struct LibraryListView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackManager: PlaybackManager

    var body: some View {
        NavigationStack {
            Group {
                if libraryManager.isScanning && libraryManager.tracks.isEmpty {
                    VStack(spacing: 14) {
                        ProgressView()
                        Text(libraryManager.scanStatusMessage.isEmpty
                             ? "Processing shared folder…" : libraryManager.scanStatusMessage)
                            .foregroundStyle(.secondary)
                    }
                } else if libraryManager.tracks.isEmpty {
                    ContentUnavailableView(
                        "No Music",
                        systemImage: "music.note",
                        description: Text("Add audio files to Chaparii via Finder → your iPhone → Files, then pull to refresh.")
                    )
                } else {
                    List(libraryManager.tracks) { track in
                        Button {
                            playlistManager.playTrack(track, fromTracks: libraryManager.tracks)
                        } label: {
                            HStack {
                                VStack(alignment: .leading, spacing: 2) {
                                    Text(track.title).lineLimit(1)
                                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                                }
                                Spacer()
                                if playbackManager.currentTrack?.trackId == track.trackId {
                                    Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                                }
                            }
                        }
                        .buttonStyle(.plain)
                        .contextMenu { trackMenu(for: track) }
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { resync() } label: { Image(systemName: "arrow.clockwise") }
                        .disabled(libraryManager.isScanning)
                }
            }
            .refreshable { resync() }
        }
    }

    /// Explicit user-triggered re-sync: forces a fresh scan of the shared folder
    /// and re-imports playlists.
    private func resync() {
        libraryManager.ensureDocumentsFolderAndScan(forceRescan: true) {
            await playlistManager.autoImportDocumentsPlaylists()
        }
    }

    /// Shared row actions: favorite toggle + add to any user playlist.
    @ViewBuilder
    private func trackMenu(for track: Track) -> some View {
        Button {
            playlistManager.toggleFavorite(for: track, currentState: track.isFavorite)
        } label: {
            Label(track.isFavorite ? "Remove from Favorites" : "Favorite",
                  systemImage: track.isFavorite ? "heart.slash" : "heart")
        }

        let userPlaylists = playlistManager.playlists.filter { $0.type != .smart }
        if userPlaylists.isEmpty {
            Text("No playlists yet")
        } else {
            Menu("Add to Playlist") {
                ForEach(userPlaylists) { playlist in
                    Button(playlist.name) {
                        Task { await playlistManager.addTracksToPlaylist(tracks: [track], playlistID: playlist.id) }
                    }
                }
            }
        }
    }
}
