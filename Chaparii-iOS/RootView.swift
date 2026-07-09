import SwiftUI

/// iOS tab shell. macOS uses its own AppKit window/sidebar UI; this is the
/// iPhone/iPad-native interface built on the shared managers.
struct RootView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @State private var selection = 0
    @State private var showSplash = true

    var body: some View {
        ZStack(alignment: .bottom) {
            TabView(selection: $selection) {
                LibraryListView()
                    .tabItem { Label("Library", systemImage: "music.note.list") }
                    .tag(0)

                BrowseView()
                    .tabItem { Label("Browse", systemImage: "square.grid.2x2") }
                    .tag(1)

                PlaylistsListView()
                    .tabItem { Label("Playlists", systemImage: "music.note.house") }
                    .tag(2)

                SearchView()
                    .tabItem { Label("Search", systemImage: "magnifyingglass") }
                    .tag(3)

                NowPlayingView()
                    .tabItem { Label("Now Playing", systemImage: "play.circle") }
                    .tag(4)
            }

            // Floats just above the tab bar while something is loaded.
            MiniPlayerBar()
                .padding(.bottom, 52)
        }
        // Load the library once at the shell level so every tab (Browse, Search,
        // …) has data regardless of which one is shown first.
        .task { libraryManager.ensureDocumentsFolderAndScan() }
        .overlay {
            if showSplash {
                SplashView()
                    .transition(.opacity)
                    .task {
                        try? await Task.sleep(nanoseconds: 1_900_000_000)
                        withAnimation(.easeOut(duration: 0.45)) { showSplash = false }
                    }
            }
        }
    }
}
