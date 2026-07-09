import SwiftUI

// MARK: - Sort Field Enum

enum TrackSortField: String, CaseIterable {
    case trackNumber
    case discNumber
    case favorite
    case title
    case artist
    case album
    case genre
    case year
    case composer
    case filename
    case duration
    case dateAdded
    case playCount
    case lastPlayedDate
    case custom

    var displayName: String {
        switch self {
        case .trackNumber:    return String(localized: "Track number (#)")
        case .discNumber:     return String(localized: "Disc number")
        case .favorite:       return String(localized: "Favorite")
        case .title:          return String(localized: "Title")
        case .artist:         return String(localized: "Artist")
        case .album:          return String(localized: "Album")
        case .genre:          return String(localized: "Genre")
        case .year:           return String(localized: "Year")
        case .composer:       return String(localized: "Composer")
        case .filename:       return String(localized: "Filename")
        case .duration:       return String(localized: "Duration")
        case .dateAdded:      return String(localized: "Date added")
        case .playCount:      return String(localized: "Play count")
        case .lastPlayedDate: return String(localized: "Last played")
        case .custom:         return String(localized: "Custom")
        }
    }

    func getComparator(ascending: Bool) -> KeyPathComparator<Track> {
        let sortComparators: [TrackSortField: KeyPathComparator<Track>] = [
            .trackNumber: KeyPathComparator(\Track.sortableTrackNumber, order: ascending ? .forward : .reverse),
            .discNumber: KeyPathComparator(\Track.sortableDiscNumber, order: ascending ? .forward : .reverse),
            .favorite: KeyPathComparator(\Track.sortableIsFavorite, order: ascending ? .forward : .reverse),
            .title: KeyPathComparator(\Track.title, order: ascending ? .forward : .reverse),
            .artist: KeyPathComparator(\Track.artist, order: ascending ? .forward : .reverse),
            .album: KeyPathComparator(\Track.album, order: ascending ? .forward : .reverse),
            .genre: KeyPathComparator(\Track.genre, order: ascending ? .forward : .reverse),
            .year: KeyPathComparator(\Track.year, order: ascending ? .forward : .reverse),
            .composer: KeyPathComparator(\Track.composer, order: ascending ? .forward : .reverse),
            .filename: KeyPathComparator(\Track.filename, order: ascending ? .forward : .reverse),
            .duration: KeyPathComparator(\Track.duration, order: ascending ? .forward : .reverse),
            .dateAdded: KeyPathComparator(\Track.dateAdded, order: ascending ? .forward : .reverse),
            .playCount: KeyPathComparator(\Track.playCount, order: ascending ? .forward : .reverse),
            .lastPlayedDate: KeyPathComparator(\Track.sortableLastPlayedDate, order: ascending ? .forward : .reverse),
            .custom: KeyPathComparator(\Track.sortableDateAdded, order: .forward)
        ]

        return sortComparators[self] ?? KeyPathComparator(\Track.title, order: ascending ? .forward : .reverse)
    }

    /// User-selectable sort fields. Hidden smart-playlist sort keys like play count and
    /// last played remain supported internally, but are omitted because the table has no
    /// matching visible columns for them.
    static var sortFields: [TrackSortField] {
        [
            .trackNumber, .discNumber, .favorite, .title, .artist, .album, .genre,
            .year, .composer, .filename, .duration, .dateAdded
        ]
    }

    // MARK: - Comparator Parsing

    /// Map of KeyPathComparator description substrings to sort fields.
    private static let comparatorKeyMap: [(String, TrackSortField)] = [
        ("sortableTrackNumber", .trackNumber),
        ("sortableDiscNumber", .discNumber),
        ("sortableIsFavorite", .favorite),
        ("sortableDateAdded", .dateAdded),
        ("sortableLastPlayedDate", .lastPlayedDate),
        ("dateAdded", .dateAdded),
        ("playCount", .playCount),
        ("lastPlayedDate", .lastPlayedDate),
        ("title", .title),
        ("artist", .artist),
        ("album", .album),
        ("genre", .genre),
        ("year", .year),
        ("composer", .composer),
        ("filename", .filename),
        ("duration", .duration),
    ]

    /// Detect the sort field from a KeyPathComparator array by parsing its description.
    static func detect(from sortOrder: [KeyPathComparator<Track>]) -> TrackSortField {
        guard let firstSort = sortOrder.first else { return .title }
        let sortString = String(describing: firstSort)
        for (key, field) in comparatorKeyMap where sortString.contains(key) {
            return field
        }
        return .title
    }

    /// Detect whether the sort order is ascending from a KeyPathComparator array.
    static func isAscending(from sortOrder: [KeyPathComparator<Track>]) -> Bool {
        guard let firstSort = sortOrder.first else { return true }
        return String(describing: firstSort).contains("forward")
    }

    /// The UserDefaults storage key (matches rawValue).
    var storageKey: String { rawValue }

    /// Look up a sort field from its storage key.
    static func from(storageKey: String) -> TrackSortField? {
        TrackSortField(rawValue: storageKey)
    }
}

extension Track {
    var sortableTrackNumber: Int {
        trackNumber ?? Int.max
    }
    
    var sortableDiscNumber: Int {
        discNumber ?? Int.max
    }
    
    var sortableDateAdded: Date {
        dateAdded ?? Date.distantPast
    }
    
    var sortableIsFavorite: Int {
        isFavorite ? 0 : 1
    }
}
