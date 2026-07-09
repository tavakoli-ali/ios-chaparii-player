import SwiftUI

/// Browse the library by Artist / Album / Genre. Groupings are derived from the
/// in-memory `libraryManager.tracks` (already loaded on iOS), so they stay in
/// sync with rescans without touching the lazy DB entity caches.
struct BrowseView: View {
    @State private var mode: BrowseMode = .artists

    enum BrowseMode: String, CaseIterable, Identifiable {
        case artists = "Artists"
        case albums = "Albums"
        case genres = "Genres"
        case folders = "Folders"
        var id: String { rawValue }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                Picker("Browse by", selection: $mode) {
                    ForEach(BrowseMode.allCases) { Text($0.rawValue).tag($0) }
                }
                .pickerStyle(.segmented)
                .padding(.horizontal)
                .padding(.bottom, 8)

                switch mode {
                case .artists: BrowseList(field: .artist)
                case .albums:  BrowseList(field: .album)
                case .genres:  BrowseList(field: .genre)
                case .folders: FolderBrowseView(components: [])
                }
            }
            .navigationTitle("Browse")
        }
    }
}

/// A grouped list for one field. Rows drill into the matching tracks.
private struct BrowseList: View {
    enum Field { case artist, album, genre }

    @EnvironmentObject var libraryManager: LibraryManager
    let field: Field

    private func key(_ t: Track) -> String {
        let raw: String
        switch field {
        case .artist: raw = t.artist
        case .album:  raw = t.album
        case .genre:  raw = t.genre
        }
        let trimmed = raw.trimmingCharacters(in: .whitespaces)
        if !trimmed.isEmpty { return trimmed }
        switch field {
        case .artist: return "Unknown Artist"
        case .album:  return "Unknown Album"
        case .genre:  return "Unknown Genre"
        }
    }

    private var groups: [(name: String, tracks: [Track])] {
        Dictionary(grouping: libraryManager.tracks, by: key)
            .map { (name: $0.key, tracks: $0.value) }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    var body: some View {
        let groups = groups
        if groups.isEmpty {
            ContentUnavailableView("Nothing to Browse", systemImage: "square.stack",
                                   description: Text("Add music to your library first."))
        } else {
            List(groups, id: \.name) { group in
                NavigationLink {
                    EntityTracksView(title: group.name, tracks: group.tracks)
                } label: {
                    HStack(spacing: 12) {
                        BrowseArtwork(data: group.tracks.first(where: { $0.albumArtworkData != nil })?.albumArtworkData,
                                      isArtist: field == .artist)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(group.name).lineLimit(1)
                            Text(subtitle(for: group))
                                .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                        }
                    }
                }
            }
        }
    }

    private func subtitle(for group: (name: String, tracks: [Track])) -> String {
        let songs = "\(group.tracks.count) song\(group.tracks.count == 1 ? "" : "s")"
        if field == .album {
            let artists = Set(group.tracks.map(\.artist)).filter { !$0.isEmpty }
            if artists.count == 1, let only = artists.first { return "\(only) · \(songs)" }
        }
        return songs
    }
}

private struct BrowseArtwork: View {
    let data: Data?
    let isArtist: Bool

    var body: some View {
        Group {
            if let data, let img = PlatformImage(data: data) {
                Image(uiImage: img).resizable().scaledToFill()
            } else {
                RoundedRectangle(cornerRadius: isArtist ? 22 : 6).fill(.quaternary)
                    .overlay(Image(systemName: isArtist ? "person.fill" : "opticaldisc")
                        .foregroundStyle(.secondary))
            }
        }
        .frame(width: 44, height: 44)
        .clipShape(RoundedRectangle(cornerRadius: isArtist ? 22 : 6))
    }
}

/// Track list for a chosen artist/album/genre; taps play in-context.
struct EntityTracksView: View {
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackManager: PlaybackManager
    let title: String
    let tracks: [Track]

    var body: some View {
        List(tracks) { track in
            Button {
                playlistManager.playTrack(track, fromTracks: tracks)
            } label: {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(track.title).lineLimit(1)
                        Text(track.artist).font(.caption).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    if playbackManager.currentTrack?.trackId == track.trackId {
                        Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                    }
                }
            }
            .buttonStyle(.plain)
        }
        .navigationTitle(title)
        .navigationBarTitleDisplayMode(.inline)
    }
}

/// Filesystem-style browser over the library's Documents tree. Shows the folders
/// (languages → albums → …) and any tracks directly at the current level, derived
/// from each track's on-disk path. Drilling in pushes deeper into the same stack.
struct FolderBrowseView: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @EnvironmentObject var playlistManager: PlaylistManager
    @EnvironmentObject var playbackManager: PlaybackManager

    /// Path prefix (relative to Documents) of the folder being shown.
    let components: [String]

    private static let docsPath: String =
        (FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .standardizedFileURL.path ?? "")

    /// Track's path components relative to Documents (last element is the filename).
    private func relative(_ track: Track) -> [String] {
        let base = Self.docsPath
        let path = track.url.standardizedFileURL.path
        guard !base.isEmpty, path.hasPrefix(base) else { return [] }
        return path.dropFirst(base.count).split(separator: "/").map(String.init)
    }

    /// Tracks whose path sits at or below the current folder.
    private var descendants: [Track] {
        libraryManager.tracks.filter { track in
            let r = relative(track)
            return r.count > components.count && Array(r.prefix(components.count)) == components
        }
    }

    private var subfolders: [String] {
        var seen = Set<String>()
        var ordered: [String] = []
        for track in descendants {
            let r = relative(track)
            if r.count > components.count + 1 {   // a folder, not a file, at this level
                let name = r[components.count]
                if seen.insert(name).inserted { ordered.append(name) }
            }
        }
        return ordered.sorted { $0.localizedCaseInsensitiveCompare($1) == .orderedAscending }
    }

    private var tracksHere: [Track] {
        descendants
            .filter { relative($0).count == components.count + 1 }
            .sorted { $0.title.localizedCaseInsensitiveCompare($1.title) == .orderedAscending }
    }

    var body: some View {
        Group {
            if subfolders.isEmpty && tracksHere.isEmpty {
                ContentUnavailableView("Empty Folder", systemImage: "folder",
                                       description: Text("No tracks here."))
            } else {
                List {
                    if !subfolders.isEmpty {
                        Section {
                            ForEach(subfolders, id: \.self) { folder in
                                NavigationLink {
                                    FolderBrowseView(components: components + [folder])
                                        .navigationTitle(folder)
                                        .navigationBarTitleDisplayMode(.inline)
                                } label: {
                                    Label(folder, systemImage: "folder.fill")
                                }
                            }
                        }
                    }
                    if !tracksHere.isEmpty {
                        Section {
                            ForEach(tracksHere) { track in
                                Button {
                                    playlistManager.playTrack(track, fromTracks: tracksHere)
                                } label: {
                                    HStack {
                                        Image(systemName: "music.note").foregroundStyle(.secondary)
                                        VStack(alignment: .leading, spacing: 2) {
                                            Text(track.title).lineLimit(1)
                                            Text(track.artist).font(.caption)
                                                .foregroundStyle(.secondary).lineLimit(1)
                                        }
                                        Spacer()
                                        if playbackManager.currentTrack?.trackId == track.trackId {
                                            Image(systemName: "speaker.wave.2.fill").foregroundStyle(.tint)
                                        }
                                    }
                                }
                                .buttonStyle(.plain)
                            }
                        }
                    }
                }
            }
        }
    }
}
