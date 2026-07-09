import SwiftUI

struct PlaylistsListView: View {
    @EnvironmentObject var playlistManager: PlaylistManager

    var body: some View {
        NavigationStack {
            List(playlistManager.playlists) { playlist in
                NavigationLink {
                    PlaylistTracksView(playlist: playlist)
                } label: {
                    Label(DefaultPlaylists.displayName(for: playlist), systemImage: "music.note.list")
                }
            }
            .navigationTitle("Playlists")
        }
    }
}

private struct PlaylistTracksView: View {
    let playlist: Playlist
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @State private var tracks: [Track] = []

    var body: some View {
        List(tracks) { track in
            Button {
                playlistManager.playTrack(track, fromTracks: tracks)
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
        }
        .overlay {
            if tracks.isEmpty {
                ContentUnavailableView("Empty Playlist", systemImage: "music.note.list",
                                       description: Text("No tracks in this playlist yet."))
            }
        }
        .navigationTitle(DefaultPlaylists.displayName(for: playlist))
        // Regular-playlist tracks are lazy-loaded from the DB; reading
        // `playlist.tracks` directly returns an empty array until then.
        .task { tracks = playlistManager.getPlaylistTracks(playlist) }
    }
}
