import Foundation
import Combine

class PlaybackProgressState: ObservableObject {
    @Published var currentTime: Double = 0
}
