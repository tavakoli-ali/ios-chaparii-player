import SwiftUI

/// iOS tab shell. macOS uses its own AppKit window/sidebar UI; this is the
/// iPhone/iPad-native interface built on the shared managers.
struct RootView: View {
    var body: some View {
        TabView {
            LibraryListView()
                .tabItem { Label("Library", systemImage: "music.note.list") }

            PlaylistsListView()
                .tabItem { Label("Playlists", systemImage: "music.note.house") }

            NowPlayingView()
                .tabItem { Label("Now Playing", systemImage: "play.circle") }
        }
    }
}
