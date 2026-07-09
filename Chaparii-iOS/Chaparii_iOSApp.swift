import SwiftUI
import AVFoundation

@main
struct Chaparii_iOSApp: App {
    @StateObject private var coordinator = AppCoordinator()

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
    }
}
