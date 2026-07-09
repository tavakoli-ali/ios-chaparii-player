import SwiftUI
import AVFoundation

@main
struct Chaparii_iOSApp: App {
    @StateObject private var coordinator = AppCoordinator()

    init() {
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
        }
    }
}
