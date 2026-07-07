//
// MetadataWriter
//
// The write-side counterpart to SFBMetadataReader. Reads a file's current tags
// for the tag editor UI and applies user edits back to the file through
// SFBAudioEngine, which delegates to TagLib for all supported formats.
//

import Foundation
import SFBAudioEngine

/// A single editable tag change. `keep` leaves the file's current value
/// untouched (used when a field wasn't modified, e.g. in multi-track editing);
/// `set(nil)` clears the tag from the file.
enum TagEdit<Value> {
    case keep
    case set(Value?)
}

enum MetadataWriter {
    // MARK: - Edits

    struct Edits {
        var title: TagEdit<String> = .keep
        var artist: TagEdit<String> = .keep
        var album: TagEdit<String> = .keep
        var albumArtist: TagEdit<String> = .keep
        var composer: TagEdit<String> = .keep
        var genre: TagEdit<String> = .keep
        var year: TagEdit<String> = .keep
        var comment: TagEdit<String> = .keep
        var lyrics: TagEdit<String> = .keep
        var trackNumber: TagEdit<Int> = .keep
        var trackTotal: TagEdit<Int> = .keep
        var discNumber: TagEdit<Int> = .keep
        var discTotal: TagEdit<Int> = .keep
        var bpm: TagEdit<Int> = .keep
        var compilation: TagEdit<Bool> = .keep
        var artwork: TagEdit<Data> = .keep

        var isEmpty: Bool {
            for edit in [title, artist, album, albumArtist, composer, genre, year, comment, lyrics] {
                if case .set = edit { return false }
            }
            for edit in [trackNumber, trackTotal, discNumber, discTotal, bpm] {
                if case .set = edit { return false }
            }
            if case .set = compilation { return false }
            if case .set = artwork { return false }
            return true
        }
    }

    struct WriteError: Identifiable {
        let id = UUID()
        let url: URL
        let underlying: Error

        var message: String {
            "\(url.lastPathComponent): \(underlying.localizedDescription)"
        }
    }

    // MARK: - Current Tags (editor prefill)

    struct CurrentTags {
        var title: String?
        var artist: String?
        var album: String?
        var albumArtist: String?
        var composer: String?
        var genre: String?
        var year: String?
        var comment: String?
        var lyrics: String?
        var trackNumber: Int?
        var trackTotal: Int?
        var discNumber: Int?
        var discTotal: Int?
        var artworkData: Data?
    }

    /// Reads the file's current tags directly (not from the database) so the
    /// editor always shows what is actually in the file.
    static func readTags(from url: URL) -> CurrentTags? {
        guard let audioFile = try? AudioFile(readingPropertiesAndMetadataFrom: url) else {
            Logger.error("MetadataWriter: failed to read \(url.lastPathComponent)")
            return nil
        }

        let metadata = audioFile.metadata
        var tags = CurrentTags()
        tags.title = metadata.title
        tags.artist = metadata.artist
        tags.album = metadata.albumTitle
        tags.albumArtist = metadata.albumArtist
        tags.composer = metadata.composer
        tags.genre = metadata.genre
        tags.year = metadata.releaseDate.flatMap { MetadataMapping.year(fromDateString: $0) } ?? metadata.releaseDate
        tags.comment = metadata.comment
        tags.lyrics = metadata.lyrics
        tags.trackNumber = metadata.trackNumber
        tags.trackTotal = metadata.trackTotal
        tags.discNumber = metadata.discNumber
        tags.discTotal = metadata.discTotal

        let pictures = metadata.attachedPictures
        if let cover = pictures.first(where: { $0.type == .frontCover }) ?? pictures.first {
            tags.artworkData = cover.imageData
        }

        return tags
    }

    // MARK: - Writing

    /// Applies the edits to every file, returning per-file failures. Writing is
    /// synchronous and should be called off the main actor.
    static func apply(_ edits: Edits, to urls: [URL]) -> [WriteError] {
        var errors: [WriteError] = []

        for url in urls {
            do {
                let audioFile = try AudioFile(url: url)
                try audioFile.readPropertiesAndMetadata()
                apply(edits, to: audioFile.metadata)
                try audioFile.writeMetadata()
            } catch {
                Logger.error("MetadataWriter: failed to write \(url.lastPathComponent): \(error)")
                errors.append(WriteError(url: url, underlying: error))
            }
        }

        return errors
    }

    private static func apply(_ edits: Edits, to metadata: AudioMetadata) {
        if case .set(let value) = edits.title { metadata.title = value }
        if case .set(let value) = edits.artist { metadata.artist = value }
        if case .set(let value) = edits.album { metadata.albumTitle = value }
        if case .set(let value) = edits.albumArtist { metadata.albumArtist = value }
        if case .set(let value) = edits.composer { metadata.composer = value }
        if case .set(let value) = edits.genre { metadata.genre = value }
        if case .set(let value) = edits.year { metadata.releaseDate = value }
        if case .set(let value) = edits.comment { metadata.comment = value }
        if case .set(let value) = edits.lyrics { metadata.lyrics = value }
        if case .set(let value) = edits.trackNumber { metadata.trackNumber = value }
        if case .set(let value) = edits.trackTotal { metadata.trackTotal = value }
        if case .set(let value) = edits.discNumber { metadata.discNumber = value }
        if case .set(let value) = edits.discTotal { metadata.discTotal = value }
        if case .set(let value) = edits.bpm { metadata.bpm = value }
        if case .set(let value) = edits.compilation { metadata.isCompilation = value }

        if case .set(let value) = edits.artwork {
            metadata.removeAllAttachedPictures()
            if let data = value {
                metadata.attachPicture(AttachedPicture(imageData: data, type: .frontCover))
            }
        }
    }
}
