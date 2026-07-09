import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager

    var body: some View {
        NavigationStack {
            Group {
                if let track = playbackManager.currentTrack {
                    VStack(spacing: 20) {
                        artwork(for: track)
                        VStack(spacing: 4) {
                            Text(track.title).font(.title3).bold().multilineTextAlignment(.center)
                            Text(track.artist).foregroundStyle(.secondary)
                        }
                        transport
                    }
                    .padding()
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "play.slash",
                                           description: Text("Pick a track from your Library."))
                }
            }
            .navigationTitle("Now Playing")
        }
    }

    @ViewBuilder
    private func artwork(for track: Track) -> some View {
        if let data = track.artworkData, let img = PlatformImage(data: data) {
            Image(uiImage: img)
                .resizable().scaledToFit()
                .frame(maxWidth: 280, maxHeight: 280)
                .clipShape(RoundedRectangle(cornerRadius: 12))
        } else {
            RoundedRectangle(cornerRadius: 12)
                .fill(.quaternary)
                .frame(width: 280, height: 280)
                .overlay(Image(systemName: "music.note").font(.system(size: 64)).foregroundStyle(.secondary))
        }
    }

    private var transport: some View {
        HStack(spacing: 40) {
            Button { playlistManager.playPreviousTrack() } label: { Image(systemName: "backward.fill").font(.title) }
            Button { playbackManager.togglePlayPause() } label: {
                Image(systemName: playbackManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            Button { playlistManager.playNextTrack() } label: { Image(systemName: "forward.fill").font(.title) }
        }
        .buttonStyle(.plain)
    }
}
