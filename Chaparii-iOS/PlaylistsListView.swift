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

    var body: some View {
        List(playlist.tracks) { track in
            Button {
                if let index = playlist.tracks.firstIndex(where: { $0.id == track.id }) {
                    playlistManager.playTrackFromPlaylist(playlist, at: index)
                }
            } label: {
                VStack(alignment: .leading, spacing: 2) {
                    Text(track.title).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(DefaultPlaylists.displayName(for: playlist))
    }
}
