import SwiftUI

/// iOS tab shell. macOS uses its own AppKit window/sidebar UI; this is the
/// iPhone/iPad-native interface built on the shared managers.
struct RootView: View {
    var body: some View {
        ZStack(alignment: .bottom) {
            TabView {
                LibraryListView()
                    .tabItem { Label("Library", systemImage: "music.note.list") }

                PlaylistsListView()
                    .tabItem { Label("Playlists", systemImage: "music.note.house") }

                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }

                NowPlayingView()
                    .tabItem { Label("Now Playing", systemImage: "play.circle") }
            }

            // Floats just above the tab bar while something is loaded.
            MiniPlayerBar()
                .padding(.bottom, 52)
        }
    }
}
