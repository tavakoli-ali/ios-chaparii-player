import SwiftUI

/// iOS tab shell. macOS uses its own AppKit window/sidebar UI; this is the
/// iPhone/iPad-native interface built on the shared managers.
struct RootView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @State private var selection = 0
    @State private var showSplash = true

    private let nowPlayingTab = 4

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

            // Floats just above the tab bar while something is loaded — except on
            // the Now Playing tab, where the full player replaces it. Tapping it
            // opens the player; leaving the player brings it back. Both animate.
            if selection != nowPlayingTab {
                MiniPlayerBar {
                    withAnimation(.spring(response: 0.4, dampingFraction: 0.85)) {
                        selection = nowPlayingTab
                    }
                }
                .padding(.bottom, 52)
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
        }
        .animation(.spring(response: 0.4, dampingFraction: 0.85), value: selection)
        // Load the library once at the shell level so every tab (Browse, Search,
        // …) has data regardless of which one is shown first, then auto-import any
        // .m3u8 playlists that were copied into Documents alongside the audio.
        .task {
            libraryManager.ensureDocumentsFolderAndScan {
                await playlistManager.autoImportDocumentsPlaylists()
            }
        }
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
