import SwiftUI

struct PlaylistsListView: View {
    @EnvironmentObject var playlistManager: PlaylistManager

    @State private var showingCreate = false
    @State private var newName = ""
    @State private var renaming: Playlist?
    @State private var renameText = ""

    var body: some View {
        NavigationStack {
            List {
                ForEach(playlistManager.playlists) { playlist in
                    NavigationLink {
                        PlaylistTracksView(playlist: playlist)
                    } label: {
                        Label(DefaultPlaylists.displayName(for: playlist), systemImage: icon(for: playlist))
                    }
                    // Smart playlists (Favorites, Top 25…) are managed by the app and
                    // can't be renamed or deleted; only user playlists get the actions.
                    .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                        if playlist.type != .smart {
                            Button(role: .destructive) {
                                playlistManager.deletePlaylist(playlist)
                            } label: { Label("Delete", systemImage: "trash") }

                            Button {
                                renaming = playlist
                                renameText = playlist.name
                            } label: { Label("Rename", systemImage: "pencil") }
                            .tint(.indigo)
                        }
                    }
                }
            }
            .navigationTitle("Playlists")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        newName = ""
                        showingCreate = true
                    } label: { Image(systemName: "plus") }
                }
            }
            .alert("New Playlist", isPresented: $showingCreate) {
                TextField("Playlist name", text: $newName)
                Button("Cancel", role: .cancel) {}
                Button("Create") {
                    let name = newName.trimmingCharacters(in: .whitespaces)
                    if !name.isEmpty { _ = playlistManager.createPlaylist(name: name) }
                }
            }
            .alert("Rename Playlist", isPresented: Binding(
                get: { renaming != nil },
                set: { if !$0 { renaming = nil } }
            )) {
                TextField("Playlist name", text: $renameText)
                Button("Cancel", role: .cancel) { renaming = nil }
                Button("Rename") {
                    if let playlist = renaming {
                        let name = renameText.trimmingCharacters(in: .whitespaces)
                        if !name.isEmpty { playlistManager.renamePlaylist(playlist, newName: name) }
                    }
                    renaming = nil
                }
            }
        }
    }

    private func icon(for playlist: Playlist) -> String {
        if playlist.type == .smart {
            return playlist.name == DefaultPlaylists.favorites ? "heart.fill" : "sparkles"
        }
        return "music.note.list"
    }
}

private struct PlaylistTracksView: View {
    let playlist: Playlist
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var tracks: [Track] = []

    private var isSmart: Bool { playlist.type == .smart }

    var body: some View {
        List {
            if !tracks.isEmpty {
                Section {
                    HStack(spacing: 12) {
                        Button { playAll(shuffled: false) } label: {
                            Label("Play", systemImage: "play.fill").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.borderedProminent)

                        Button { playAll(shuffled: true) } label: {
                            Label("Shuffle", systemImage: "shuffle").frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                    }
                    .listRowInsets(EdgeInsets(top: 4, leading: 16, bottom: 8, trailing: 16))
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }
            }

            ForEach(tracks) { track in
                Button {
                    playlistManager.playTrack(track, fromTracks: tracks)
                } label: {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(track.title).lineLimit(1)
                            Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                        Spacer()
                        if track.isFavorite {
                            Image(systemName: "heart.fill").font(.caption).foregroundStyle(.pink)
                        }
                        if playbackManager.currentTrack?.trackId == track.trackId {
                            Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                        }
                    }
                }
                .buttonStyle(.plain)
                .swipeActions(edge: .leading) {
                    Button {
                        playlistManager.toggleFavorite(for: track, currentState: track.isFavorite)
                        Task { await reload() }
                    } label: {
                        Label(track.isFavorite ? "Unfavorite" : "Favorite",
                              systemImage: track.isFavorite ? "heart.slash" : "heart")
                    }
                    .tint(.pink)
                }
                .swipeActions(edge: .trailing) {
                    if !isSmart {
                        Button(role: .destructive) {
                            playlistManager.removeTrackFromPlaylist(track: track, playlistID: playlist.id)
                            tracks.removeAll { $0.id == track.id }
                        } label: { Label("Remove", systemImage: "minus.circle") }
                    }
                }
            }
        }
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView("Empty Playlist", systemImage: "music.note.list",
                                       description: Text("No tracks in this playlist yet."))
            }
        }
        .navigationTitle(DefaultPlaylists.displayName(for: playlist))
        .task { await reload() }
    }

    /// Play the whole playlist. `shuffled` turns on shuffle mode (reflected in Now
    /// Playing) and starts from a random track; otherwise plays in order from the top.
    private func playAll(shuffled: Bool) {
        guard !tracks.isEmpty else { return }
        playlistManager.isShuffleEnabled = shuffled
        let start = shuffled ? (tracks.randomElement() ?? tracks[0]) : tracks[0]
        playlistManager.playTrack(start, fromTracks: tracks)
    }

    @MainActor
    private func reload() async {
        if isSmart {
            // Smart playlists (Favorites, Top 25…) materialize their tracks lazily.
            await playlistManager.loadSmartPlaylistTracks(playlist)
            tracks = playlistManager.playlists.first { $0.id == playlist.id }?.tracks ?? []
        } else {
            tracks = playlistManager.getPlaylistTracks(playlist)
        }
    }
}
