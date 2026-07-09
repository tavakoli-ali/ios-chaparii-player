import Foundation
import CoreTransferable
import UniformTypeIdentifiers

/// Custom drag type so track drags (onto playlists) are distinct from the
/// sidebar's playlist-reorder drags (which use plain text).
extension UTType {
    static let chapariiTrackList = UTType(exportedAs: "com.atavakoli.chaparii.tracklist")
}

/// Marker payload for `.draggable`. Carries no data itself — the actual tracks
/// live in `TrackDragCoordinator` (set at drag start). Declaring the content type
/// as `.chapariiTrackList` lets the playlist rows' `.onDrop(of: [.chapariiTrackList])`
/// recognize the drop.
struct TrackDragMarker: Transferable {
    static var transferRepresentation: some TransferRepresentation {
        DataRepresentation(contentType: .chapariiTrackList) { _ in
            Data()
        } importing: { _ in
            TrackDragMarker()
        }
    }
}

/// Holds the tracks being dragged for an in-app drag from the track table onto a
/// playlist, so the drop target doesn't need to resolve IDs back to Track objects.
/// Touched only from the main thread (drag start / drop).
final class TrackDragCoordinator {
    static let shared = TrackDragCoordinator()
    private init() {}

    private(set) var draggedTracks: [Track] = []

    /// Records the tracks for the drag that's starting, and returns the marker
    /// payload for `.draggable`.
    func stage(_ tracks: [Track]) -> TrackDragMarker {
        draggedTracks = tracks
        return TrackDragMarker()
    }

    /// Reads and clears the staged tracks (called by the drop target).
    func take() -> [Track] {
        let t = draggedTracks
        draggedTracks = []
        return t
    }
}
