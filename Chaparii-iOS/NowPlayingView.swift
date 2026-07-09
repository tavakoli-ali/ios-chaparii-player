import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackProgressState: PlaybackProgressState

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var isFavorite = false

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
                        favoriteButton(for: track)
                        seekBar(for: track)
                        transport
                    }
                    .padding()
                    .onAppear { isFavorite = track.isFavorite }
                    .onChange(of: track.trackId) { _, _ in isFavorite = track.isFavorite }
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "play.slash",
                                           description: Text("Pick a track from your Library."))
                }
            }
            .navigationTitle("Now Playing")
        }
    }

    private func favoriteButton(for track: Track) -> some View {
        Button {
            playlistManager.toggleFavorite(for: track, currentState: isFavorite)
            isFavorite.toggle()
        } label: {
            Label(isFavorite ? "Favorited" : "Favorite",
                  systemImage: isFavorite ? "heart.fill" : "heart")
                .foregroundStyle(.pink)
        }
        .buttonStyle(.bordered)
        .tint(.pink)
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

    /// Scrubbable seek bar. Shows live progress while playing; on drag it tracks
    /// the finger and commits the new position to the engine on release.
    @ViewBuilder
    private func seekBar(for track: Track) -> some View {
        let duration = max(track.duration, 0.01)
        let current = min(isScrubbing ? scrubValue : playbackProgressState.currentTime, duration)
        VStack(spacing: 2) {
            Slider(
                value: Binding(get: { current }, set: { scrubValue = $0 }),
                in: 0...duration
            ) { editing in
                if editing {
                    scrubValue = min(playbackProgressState.currentTime, duration)
                } else {
                    playbackManager.seekTo(time: scrubValue)
                }
                isScrubbing = editing
            }
            HStack {
                Text(HelperUtils.formattedDuration(current))
                Spacer()
                Text(HelperUtils.formattedDuration(duration))
            }
            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
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
