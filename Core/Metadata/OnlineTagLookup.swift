//
// OnlineTagLookup
//
// Looks up canonical tag data for local tracks using the iTunes Search API
// (no API key required) and scores candidates against the track's current
// title/artist so callers can preselect trustworthy matches. Artwork URLs are
// upgraded to 600x600.
//

import Foundation

enum OnlineTagLookup {
    struct Candidate: Identifiable, Equatable {
        let id = UUID()
        let title: String
        let artist: String
        let album: String
        let albumArtist: String?
        let genre: String?
        let year: String?
        let trackNumber: Int?
        let trackTotal: Int?
        let discNumber: Int?
        let artworkURL: URL?
        /// 0…1 similarity against the local track's current title + artist
        let score: Double

        var summary: String {
            var parts = ["\(artist) — \(title)"]
            if !album.isEmpty { parts.append(album) }
            if let year { parts.append(year) }
            return parts.joined(separator: " · ")
        }
    }

    enum LookupError: LocalizedError {
        case badResponse(Int)

        var errorDescription: String? {
            switch self {
            case .badResponse(let code):
                return String(localized: "Lookup failed (HTTP \(code))")
            }
        }
    }

    /// Searches for candidates matching the track's current tags, best first.
    static func candidates(title: String, artist: String, limit: Int = 5) async throws -> [Candidate] {
        let hasArtist = !artist.isEmpty && artist.lowercased() != "unknown artist"
        let term = hasArtist ? "\(artist) \(title)" : title

        var components = URLComponents(string: "https://itunes.apple.com/search")!
        components.queryItems = [
            URLQueryItem(name: "term", value: term),
            URLQueryItem(name: "media", value: "music"),
            URLQueryItem(name: "entity", value: "song"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        let (data, response) = try await URLSession.shared.data(from: components.url!)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            throw LookupError.badResponse((response as? HTTPURLResponse)?.statusCode ?? -1)
        }

        struct SearchResponse: Decodable {
            struct Item: Decodable {
                let trackName: String?
                let artistName: String?
                let collectionName: String?
                let collectionArtistName: String?
                let primaryGenreName: String?
                let releaseDate: String?
                let trackNumber: Int?
                let trackCount: Int?
                let discNumber: Int?
                let artworkUrl100: String?
            }
            let results: [Item]
        }

        let decoded = try JSONDecoder().decode(SearchResponse.self, from: data)

        return decoded.results.compactMap { item -> Candidate? in
            guard let trackName = item.trackName, let artistName = item.artistName else { return nil }
            return Candidate(
                title: trackName,
                artist: artistName,
                album: item.collectionName ?? "",
                albumArtist: item.collectionArtistName,
                genre: item.primaryGenreName,
                year: item.releaseDate.flatMap { MetadataMapping.year(fromDateString: $0) },
                trackNumber: item.trackNumber,
                trackTotal: item.trackCount,
                discNumber: item.discNumber,
                artworkURL: item.artworkUrl100.flatMap { highResArtworkURL(from: $0) },
                score: matchScore(
                    localTitle: title, localArtist: artist,
                    remoteTitle: trackName, remoteArtist: artistName
                )
            )
        }
        .sorted { $0.score > $1.score }
    }

    static func artworkData(for candidate: Candidate) async -> Data? {
        guard let url = candidate.artworkURL else { return nil }
        guard let (data, response) = try? await URLSession.shared.data(from: url),
              (response as? HTTPURLResponse)?.statusCode == 200
        else { return nil }
        return data
    }

    // MARK: - Scoring

    /// iTunes serves artwork at any square size by rewriting the size segment.
    private static func highResArtworkURL(from urlString: String) -> URL? {
        URL(string: urlString.replacingOccurrences(of: "100x100", with: "600x600"))
    }

    static func matchScore(
        localTitle: String, localArtist: String,
        remoteTitle: String, remoteArtist: String
    ) -> Double {
        let titleScore = similarity(localTitle, remoteTitle)
        guard !localArtist.isEmpty, localArtist.lowercased() != "unknown artist" else {
            return titleScore
        }
        return titleScore * 0.6 + similarity(localArtist, remoteArtist) * 0.4
    }

    /// Token-based similarity of normalized strings: the fraction of the
    /// smaller token set found in the larger, so "Hello" vs "Hello (Remix)"
    /// still scores 1.0 while unrelated titles score near 0.
    private static func similarity(_ lhs: String, _ rhs: String) -> Double {
        let lhsTokens = tokens(lhs)
        let rhsTokens = tokens(rhs)
        guard !lhsTokens.isEmpty, !rhsTokens.isEmpty else { return 0 }

        let smaller = lhsTokens.count <= rhsTokens.count ? lhsTokens : rhsTokens
        let larger = lhsTokens.count <= rhsTokens.count ? rhsTokens : lhsTokens
        let overlap = smaller.intersection(larger).count
        return Double(overlap) / Double(smaller.count)
    }

    private static func tokens(_ string: String) -> Set<String> {
        let normalized = string
            .folding(options: [.diacriticInsensitive, .caseInsensitive], locale: nil)
            .lowercased()
        let separators = CharacterSet.alphanumerics.inverted
        return Set(normalized.components(separatedBy: separators).filter { !$0.isEmpty })
    }
}
