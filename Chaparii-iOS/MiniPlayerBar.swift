import SwiftUI

/// Persistent now-playing strip shown above the tab bar whenever something is loaded.
struct MiniPlayerBar: View {
    @EnvironmentObject var playbackManager: PlaybackManager

    var body: some View {
        if let track = playbackManager.currentTrack {
            HStack(spacing: 12) {
                artwork(for: track)
                VStack(alignment: .leading, spacing: 1) {
                    Text(track.title).font(.subheadline).lineLimit(1)
                    Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer()
                Button { playbackManager.togglePlayPause() } label: {
                    Image(systemName: playbackManager.isPlaying ? "pause.fill" : "play.fill")
                        .font(.title3)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.plain)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(.ultraThinMaterial)
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .shadow(radius: 4, y: 2)
            .padding(.horizontal, 8)
        }
    }

    @ViewBuilder
    private func artwork(for track: Track) -> some View {
        if let data = track.artworkData, let img = PlatformImage(data: data) {
            Image(uiImage: img).resizable().scaledToFill()
                .frame(width: 40, height: 40).clipShape(RoundedRectangle(cornerRadius: 6))
        } else {
            RoundedRectangle(cornerRadius: 6).fill(.quaternary)
                .frame(width: 40, height: 40)
                .overlay(Image(systemName: "music.note").foregroundStyle(.secondary))
        }
    }
}
