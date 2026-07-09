//
// SpotifyDownloadManager
//
// Drives the "Download from Spotify" feature. Downloads are performed by the
// bundled spotDL binary (which sources audio from YouTube and applies Spotify
// metadata, cover art and lyrics). The Spotify Web API (optional, user-supplied
// client credentials kept in the keychain) is used only to resolve an artist's
// top tracks and most popular album; the plain "full album of this song" mode
// works without any credentials via spotDL's --fetch-albums.
//

import Foundation

@MainActor
final class SpotifyDownloadManager: ObservableObject {
    enum KeychainKeys {
        static let clientId = "com.atavakoli.petrichor.spotify.clientId"
        static let clientSecret = "com.atavakoli.petrichor.spotify.clientSecret"
    }

    enum Phase: Equatable {
        case idle
        case preparingFFmpeg
        case resolving
        case downloading
        case finished(downloadedCount: Int)
        case failed(String)

        var isBusy: Bool {
            switch self {
            case .preparingFFmpeg, .resolving, .downloading: return true
            default: return false
            }
        }
    }

    enum Mode: String, CaseIterable, Identifiable {
        case songAlbum
        case topTracks
        case topAlbum

        var id: String { rawValue }

        var title: String {
            switch self {
            case .songAlbum: return String(localized: "This song's full album")
            case .topTracks: return String(localized: "Artist's top tracks")
            case .topAlbum: return String(localized: "Artist's most popular album")
            }
        }

        var needsCredentials: Bool { self != .songAlbum }
    }

    @Published var phase: Phase = .idle
    @Published var logLines: [String] = []

    private var process: Process?
    /// Distinguishes a user-requested terminate from the process dying on its
    /// own (crash, sandbox kill, …) — only the former should end up as .idle.
    private var userCancelled = false

    var hasCredentials: Bool {
        KeychainManager.retrieve(key: KeychainKeys.clientId)?.isEmpty == false &&
        KeychainManager.retrieve(key: KeychainKeys.clientSecret)?.isEmpty == false
    }

    static func saveCredentials(clientId: String, clientSecret: String) {
        KeychainManager.save(key: KeychainKeys.clientId, value: clientId)
        KeychainManager.save(key: KeychainKeys.clientSecret, value: clientSecret)
    }

    // MARK: - Public entry point

    /// Starts a download for the given query ("Artist - Title" or a Spotify URL)
    /// into `destination`. Calls `onSuccess` on the main actor when spotDL exits
    /// cleanly, so the caller can refresh the library.
    func start(mode: Mode, query: String, destination: URL, onSuccess: @escaping () -> Void) {
        guard !phase.isBusy else { return }
        logLines = []
        userCancelled = false

        Task {
            do {
                let spotdl = try bundledSpotdlURL()
                let ffmpeg = try await ensureFFmpeg(spotdl: spotdl)

                phase = .resolving
                let arguments = try await downloadArguments(for: mode, query: query)

                phase = .downloading
                let downloadedCount = try await runSpotdl(
                    spotdl,
                    arguments: arguments + [
                        "--ffmpeg", ffmpeg.path,
                        "--format", "mp3",
                        "--output", destination.appendingPathComponent("{artists} - {title}.{output-ext}").path
                    ]
                )
                phase = .finished(downloadedCount: downloadedCount)
                onSuccess()
            } catch is CancellationError {
                phase = .idle
            } catch {
                phase = .failed(error.localizedDescription)
            }
        }
    }

    func cancel() {
        userCancelled = true
        process?.terminate()
        process = nil
        phase = .idle
    }

    // MARK: - Mode resolution

    private func downloadArguments(for mode: Mode, query: String) async throws -> [String] {
        switch mode {
        case .songAlbum:
            // spotDL expands the matched song into its full album by itself
            return ["download", query, "--fetch-albums"]

        case .topTracks:
            let artist = try await resolveArtist(from: query)
            appendLog("Matched artist: \(artist.name)")
            // The /artists/{id}/top-tracks endpoint is Forbidden (403) for
            // Client-Credentials apps, so approximate "top tracks" with a
            // relevance-ranked track search scoped to the artist, which is allowed.
            let tracks = try await SpotifyAPI.searchTopTracks(artistName: artist.name, token: try await token())
            guard !tracks.isEmpty else { throw SpotifyDownloadError.nothingFound }
            appendLog("Top tracks: \(tracks.map(\.name).joined(separator: ", "))")
            return ["download"] + tracks.map(\.url)

        case .topAlbum:
            let artist = try await resolveArtist(from: query)
            appendLog("Matched artist: \(artist.name)")
            // Same restriction on /artists/{id}/albums — use album search instead.
            let album = try await SpotifyAPI.searchTopAlbum(artistName: artist.name, token: try await token())
            appendLog("Album: \(album.name)")
            return ["download", album.url]
        }
    }

    private func resolveArtist(from query: String) async throws -> SpotifyAPI.Artist {
        let track = try await SpotifyAPI.searchTrack(query: query, token: try await token())
        appendLog("Matched song: \(track.name) — \(track.artistName)")
        guard let artist = track.artists.first else { throw SpotifyDownloadError.nothingFound }
        return artist
    }

    private func token() async throws -> String {
        guard
            let clientId = KeychainManager.retrieve(key: KeychainKeys.clientId),
            let clientSecret = KeychainManager.retrieve(key: KeychainKeys.clientSecret),
            !clientId.isEmpty, !clientSecret.isEmpty
        else { throw SpotifyDownloadError.missingCredentials }
        return try await SpotifyAPI.accessToken(clientId: clientId, clientSecret: clientSecret)
    }

    // MARK: - spotDL process

    private func bundledSpotdlURL() throws -> URL {
        guard let url = Bundle.main.url(forResource: "spotdl", withExtension: nil) else {
            throw SpotifyDownloadError.spotdlMissing
        }
        return url
    }

    /// spotDL needs ffmpeg for conversion; its own bootstrapper installs a copy
    /// under ~/.spotdl the first time.
    private func ensureFFmpeg(spotdl: URL) async throws -> URL {
        let ffmpeg = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent(".spotdl/ffmpeg")
        if FileManager.default.isExecutableFile(atPath: ffmpeg.path) {
            return ffmpeg
        }

        phase = .preparingFFmpeg
        appendLog("Downloading ffmpeg (one-time setup)…")
        _ = try await runSpotdl(spotdl, arguments: ["--download-ffmpeg"])
        guard FileManager.default.isExecutableFile(atPath: ffmpeg.path) else {
            throw SpotifyDownloadError.ffmpegSetupFailed
        }
        return ffmpeg
    }

    /// Runs spotDL streaming its output into `logLines`; returns the number of
    /// "Downloaded" lines as a rough success count.
    private func runSpotdl(_ spotdl: URL, arguments: [String]) async throws -> Int {
        let process = Process()
        process.executableURL = spotdl
        process.arguments = arguments
        process.environment = ProcessInfo.processInfo.environment

        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        self.process = process

        let accumulator = LineAccumulator { [weak self] line in
            Task { @MainActor [weak self] in
                self?.appendLog(line)
            }
        }

        return try await withCheckedThrowingContinuation { continuation in
            pipe.fileHandleForReading.readabilityHandler = { handle in
                accumulator.append(handle.availableData)
            }

            process.terminationHandler = { [weak self] finished in
                // Stop the handler first, then drain whatever is still buffered
                // in the pipe so the tail of the log isn't lost.
                pipe.fileHandleForReading.readabilityHandler = nil
                accumulator.append((try? pipe.fileHandleForReading.readToEnd()) ?? Data())
                accumulator.flush()

                let signalled = finished.terminationReason == .uncaughtSignal
                let status = finished.terminationStatus
                Task { @MainActor [weak self] in
                    self?.process = nil
                    guard let self else {
                        continuation.resume(throwing: CancellationError())
                        return
                    }
                    if signalled {
                        // SIGTERM from Cancel is expected; anything else means
                        // the process was killed (crash, sandbox, out of memory)
                        // and must surface as a failure, not end silently.
                        if self.userCancelled {
                            continuation.resume(throwing: CancellationError())
                        } else {
                            continuation.resume(throwing: SpotifyDownloadError.spotdlKilled(status))
                        }
                    } else if status == 0 {
                        continuation.resume(returning: accumulator.downloadedCount)
                    } else {
                        continuation.resume(throwing: SpotifyDownloadError.spotdlFailed(status))
                    }
                }
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }

    /// Splits pipe output into lines and counts spotDL's "Downloaded" lines.
    /// Serialized with a lock: readability and termination callbacks arrive on
    /// different queues.
    private final class LineAccumulator: @unchecked Sendable {
        private let lock = NSLock()
        private var buffer = Data()
        private var count = 0
        private let onLine: (String) -> Void

        init(onLine: @escaping (String) -> Void) {
            self.onLine = onLine
        }

        var downloadedCount: Int {
            lock.withLock { count }
        }

        func append(_ data: Data) {
            guard !data.isEmpty else { return }
            lock.withLock {
                buffer.append(data)
                while let newlineRange = buffer.firstRange(of: Data([0x0A])) {
                    let lineData = buffer.subdata(in: buffer.startIndex..<newlineRange.lowerBound)
                    buffer.removeSubrange(buffer.startIndex..<newlineRange.upperBound)
                    emit(lineData)
                }
            }
        }

        func flush() {
            lock.withLock {
                emit(buffer)
                buffer.removeAll()
            }
        }

        private func emit(_ lineData: Data) {
            guard let line = String(data: lineData, encoding: .utf8)?
                .trimmingCharacters(in: .whitespacesAndNewlines),
                !line.isEmpty
            else { return }
            if line.hasPrefix("Downloaded") { count += 1 }
            onLine(line)
        }
    }

    private func appendLog(_ line: String) {
        logLines.append(line)
        if logLines.count > 500 {
            logLines.removeFirst(logLines.count - 500)
        }
    }
}

// MARK: - Errors

enum SpotifyDownloadError: LocalizedError {
    case spotdlMissing
    case ffmpegSetupFailed
    case missingCredentials
    case nothingFound
    case spotdlFailed(Int32)
    case spotdlKilled(Int32)
    case apiFailure(String)

    var errorDescription: String? {
        switch self {
        case .spotdlMissing:
            return String(localized: "The bundled spotdl binary is missing from the app.")
        case .ffmpegSetupFailed:
            return String(localized: "Could not set up ffmpeg.")
        case .missingCredentials:
            return String(localized: "Spotify API credentials are required for this option.")
        case .nothingFound:
            return String(localized: "No match found on Spotify.")
        case .spotdlFailed(let code):
            return String(localized: "spotdl exited with code \(code). See the log for details.")
        case .spotdlKilled(let signal):
            return String(localized: "spotdl was terminated by the system (signal \(signal)).")
        case .apiFailure(let message):
            return String(localized: "Spotify API error: \(message)")
        }
    }
}

// MARK: - Spotify Web API (client credentials)

enum SpotifyAPI {
    struct Artist: Decodable {
        let id: String
        let name: String
    }

    struct Track {
        let name: String
        let url: String
        let artists: [Artist]

        var artistName: String { artists.map(\.name).joined(separator: ", ") }
    }

    struct Album {
        let name: String
        let url: String
    }

    static func accessToken(clientId: String, clientSecret: String) async throws -> String {
        var request = URLRequest(url: URL(string: "https://accounts.spotify.com/api/token")!)
        request.httpMethod = "POST"
        let basic = Data("\(clientId):\(clientSecret)".utf8).base64EncodedString()
        request.setValue("Basic \(basic)", forHTTPHeaderField: "Authorization")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = Data("grant_type=client_credentials".utf8)

        struct TokenResponse: Decodable { let accessToken: String }
        let response: TokenResponse = try await decode(request: request, errorContext: "authentication")
        return response.accessToken
    }

    static func searchTrack(query: String, token: String) async throws -> Track {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: query),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: "1")
        ]

        struct SearchResponse: Decodable {
            struct Tracks: Decodable { let items: [TrackItem] }
            let tracks: Tracks
        }

        let response: SearchResponse = try await decode(
            request: authorizedRequest(url: components.url!, token: token),
            errorContext: "search"
        )
        guard let item = response.tracks.items.first else {
            throw SpotifyDownloadError.nothingFound
        }
        return Track(name: item.name, url: item.externalUrls.spotify, artists: item.artists)
    }

    /// Approximates an artist's top tracks with a relevance-ranked track search
    /// (`q=artist:"Name"`). Spotify orders search results by popularity/relevance,
    /// and unlike `/artists/{id}/top-tracks` this endpoint is available to
    /// Client-Credentials apps.
    static func searchTopTracks(artistName: String, token: String, limit: Int = 10) async throws -> [Track] {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "artist:\(artistName)"),
            URLQueryItem(name: "type", value: "track"),
            URLQueryItem(name: "limit", value: String(limit))
        ]

        struct SearchResponse: Decodable {
            struct Tracks: Decodable { let items: [TrackItem] }
            let tracks: Tracks
        }
        let response: SearchResponse = try await decode(
            request: authorizedRequest(url: components.url!, token: token),
            errorContext: "top tracks"
        )
        return response.tracks.items.map { Track(name: $0.name, url: $0.externalUrls.spotify, artists: $0.artists) }
    }

    /// The artist's most relevant full album via album search (the
    /// `/artists/{id}/albums` + per-album popularity path is Forbidden for
    /// Client-Credentials apps). Prefers a proper album over singles/EPs.
    static func searchTopAlbum(artistName: String, token: String) async throws -> Album {
        var components = URLComponents(string: "https://api.spotify.com/v1/search")!
        components.queryItems = [
            URLQueryItem(name: "q", value: "artist:\(artistName)"),
            URLQueryItem(name: "type", value: "album"),
            URLQueryItem(name: "limit", value: "10")
        ]

        struct SearchResponse: Decodable {
            struct Albums: Decodable { let items: [AlbumItem] }
            let albums: Albums
        }
        struct AlbumItem: Decodable {
            let name: String
            let albumType: String?
            let externalUrls: ExternalUrls
        }
        let response: SearchResponse = try await decode(
            request: authorizedRequest(url: components.url!, token: token),
            errorContext: "albums"
        )
        let items = response.albums.items
        guard let best = items.first(where: { $0.albumType == "album" }) ?? items.first else {
            throw SpotifyDownloadError.nothingFound
        }
        return Album(name: best.name, url: best.externalUrls.spotify)
    }

    // MARK: Shared plumbing

    private struct ExternalUrls: Decodable { let spotify: String }

    private struct TrackItem: Decodable {
        let name: String
        let artists: [Artist]
        let externalUrls: ExternalUrls
    }

    private static func authorizedRequest(url: URL, token: String) -> URLRequest {
        var request = URLRequest(url: url)
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        return request
    }

    private static func decode<T: Decodable>(request: URLRequest, errorContext: String) async throws -> T {
        let (data, response) = try await URLSession.shared.data(for: request)
        guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode) else {
            let status = (response as? HTTPURLResponse)?.statusCode ?? -1
            let body = String(data: data, encoding: .utf8) ?? "<non-utf8>"
            Logger.error("SpotifyAPI \(errorContext) failed: HTTP \(status), url=\(request.url?.absoluteString ?? "?"), body=\(body)")
            throw SpotifyDownloadError.apiFailure("\(errorContext) failed (HTTP \(status))")
        }
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        return try decoder.decode(T.self, from: data)
    }
}
