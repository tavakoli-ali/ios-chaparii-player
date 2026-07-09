import SwiftUI
import AVFoundation

@main
struct Chaparii_iOSApp: App {
    @StateObject private var coordinator = AppCoordinator()
    @Environment(\.scenePhase) private var scenePhase

    init() {
        // Hide duplicate tracks by default on iOS. File Sharing tends to leave
        // multiple physical copies of the same song in Documents; the scan's
        // quality-scored duplicate detection already flags all but the best copy
        // (`isDuplicate`). Enabling this key makes every query (library, browse,
        // search) surface only the primary copy. `register` is a fallback, so it
        // never overrides a value the user has explicitly toggled.
        UserDefaults.standard.register(defaults: ["hideDuplicateTracks": true])

        // Playback audio session + background audio.
        let session = AVAudioSession.sharedInstance()
        try? session.setCategory(.playback, mode: .default)
        try? session.setActive(true)
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(coordinator)
                .environmentObject(coordinator.libraryManager)
                .environmentObject(coordinator.playlistManager)
                .environmentObject(coordinator.playbackManager)
                .environmentObject(coordinator.playbackManager.playbackProgressState)
        }
        // Persist playback (current track, queue, position) when leaving the app,
        // so the next launch resumes where it left off. iOS has no quit hook like
        // macOS, so scene backgrounding is the save point.
        .onChange(of: scenePhase) { _, phase in
            if phase == .background || phase == .inactive {
                coordinator.savePlaybackState()
            }
        }
    }
}
