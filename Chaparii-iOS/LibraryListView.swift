import SwiftUI

struct LibraryListView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackManager: PlaybackManager

    var body: some View {
        NavigationStack {
            Group {
                if libraryManager.tracks.isEmpty {
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
                    }
                }
            }
            .navigationTitle("Library")
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Button { libraryManager.refreshLibrary() } label: { Image(systemName: "arrow.clockwise") }
                }
            }
        }
    }
}
