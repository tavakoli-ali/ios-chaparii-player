import SwiftUI

struct NowPlayingView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playbackManager: PlaybackManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackProgressState: PlaybackProgressState

    @State private var isScrubbing = false
    @State private var scrubValue: Double = 0
    @State private var isFavorite = false
    @State private var destination: Destination?

    /// Drill-in target chosen from the "•••" menu.
    private enum Destination: Identifiable, Hashable {
        case artist(String)
        case album(String)
        var id: String {
            switch self {
            case .artist(let a): return "artist:\(a)"
            case .album(let a): return "album:\(a)"
            }
        }
        var title: String {
            switch self { case .artist(let a): return a; case .album(let a): return a }
        }
    }

    var body: some View {
        NavigationStack {
            Group {
                if let track = playbackManager.currentTrack {
                    content(for: track)
                } else {
                    ContentUnavailableView("Nothing Playing", systemImage: "play.slash",
                                           description: Text("Pick a track from your Library."))
                }
            }
            .navigationTitle("Now Playing")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { toolbar }
            .navigationDestination(item: $destination) { dest in
                EntityTracksView(title: dest.title, tracks: tracks(for: dest))
            }
        }
    }

    // MARK: - Content

    private func content(for track: Track) -> some View {
        VStack(spacing: 22) {
            Spacer(minLength: 0)
            artwork(for: track)
            VStack(spacing: 6) {
                Text(track.title)
                    .font(.title3.weight(.semibold))
                    .multilineTextAlignment(.center)
                    .lineLimit(2)
                Text(track.artist)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            seekBar(for: track)
            transport
            secondaryControls
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 32)
        .onAppear { isFavorite = track.isFavorite }
        .onChange(of: track.trackId) { _, _ in isFavorite = track.isFavorite }
    }

    @ViewBuilder
    private func artwork(for track: Track) -> some View {
        Group {
            if let data = track.artworkData, let img = PlatformImage(data: data) {
                Image(uiImage: img).resizable().scaledToFit()
            } else {
                RoundedRectangle(cornerRadius: 12)
                    .fill(.quaternary)
                    .overlay(Image(systemName: "music.note").font(.system(size: 56)).foregroundStyle(.secondary))
            }
        }
        .frame(maxWidth: 280, maxHeight: 280)
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .shadow(color: .black.opacity(0.15), radius: 8, y: 4)
    }

    // MARK: - Seek bar

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
                Text("-" + HelperUtils.formattedDuration(max(duration - current, 0)))
            }
            .font(.caption2).monospacedDigit().foregroundStyle(.secondary)
        }
    }

    // MARK: - Transport

    private var transport: some View {
        HStack(spacing: 48) {
            Button { playlistManager.playPreviousTrack() } label: {
                Image(systemName: "backward.fill").font(.title)
            }
            Button { playbackManager.togglePlayPause() } label: {
                Image(systemName: playbackManager.isPlaying ? "pause.circle.fill" : "play.circle.fill")
                    .font(.system(size: 64))
            }
            Button { playlistManager.playNextTrack() } label: {
                Image(systemName: "forward.fill").font(.title)
            }
        }
        .buttonStyle(.plain)
        .foregroundStyle(.primary)
    }

    private var secondaryControls: some View {
        HStack {
            Button { playlistManager.toggleShuffle() } label: {
                Image(systemName: "shuffle")
                    .foregroundStyle(playlistManager.isShuffleEnabled ? Color.accentColor : .secondary)
            }
            Spacer()
            Button { playlistManager.toggleRepeatMode() } label: {
                Image(systemName: playlistManager.repeatMode == .one ? "repeat.1" : "repeat")
                    .foregroundStyle(playlistManager.repeatMode == .off ? .secondary : Color.accentColor)
            }
        }
        .font(.title3)
        .buttonStyle(.plain)
        .padding(.horizontal, 24)
    }

    // MARK: - Toolbar (favorite + "•••" go-to menu)

    @ToolbarContentBuilder
    private var toolbar: some ToolbarContent {
        if let track = playbackManager.currentTrack {
            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    playlistManager.toggleFavorite(for: track, currentState: isFavorite)
                    isFavorite.toggle()
                } label: {
                    Image(systemName: isFavorite ? "heart.fill" : "heart")
                        .foregroundStyle(.pink)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    Button {
                        destination = .artist(track.artist)
                    } label: { Label("Go to Artist", systemImage: "music.mic") }

                    if !track.album.trimmingCharacters(in: .whitespaces).isEmpty {
                        Button {
                            destination = .album(track.album)
                        } label: { Label("Go to Album", systemImage: "opticaldisc") }
                    }
                } label: {
                    Image(systemName: "ellipsis.circle")
                }
            }
        }
    }

    // MARK: - Helpers

    private func tracks(for dest: Destination) -> [Track] {
        switch dest {
        case .artist(let a): return libraryManager.tracks.filter { $0.artist == a }
        case .album(let a): return libraryManager.tracks.filter { $0.album == a }
        }
    }
}
