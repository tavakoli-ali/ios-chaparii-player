#if os(macOS)
import SwiftUI

/// Identifiable payload driving `.sheet(item:)` presentation of the tag editor.
struct TagEditSession: Identifiable {
    let id = UUID()
    let tracks: [Track]
}

/// Sheet for editing the tags of one or more tracks. Values are read from the
/// files themselves (not the database), and only fields the user actually
/// changed are written back, so multi-track edits touch just the shared fields
/// that were modified. After a save the library refresh picks up the changed
/// files via their modification dates.
struct TagEditorSheet: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) private var dismiss

    let tracks: [Track]

    private enum ArtworkState {
        case unchanged
        case replaced(Data)
        case removed
    }

    @State private var isLoading = true
    @State private var isSaving = false

    // Field values and the initial values they're compared against on save
    @State private var fields: [Field: String] = [:]
    @State private var initialFields: [Field: String] = [:]
    @State private var lyrics: String = ""
    @State private var initialLyrics: String = ""
    @State private var artworkState: ArtworkState = .unchanged
    @State private var currentArtwork: Data?

    @State private var writeErrors: [MetadataWriter.WriteError] = []
    @State private var showingErrors = false

    private var isMultiTrack: Bool { tracks.count > 1 }

    enum Field: CaseIterable {
        case title, artist, album, albumArtist, composer, genre, year
        case trackNumber, trackTotal, discNumber, discTotal, comment

        var label: String {
            switch self {
            case .title: return String(localized: "Title")
            case .artist: return String(localized: "Artist")
            case .album: return String(localized: "Album")
            case .albumArtist: return String(localized: "Album Artist")
            case .composer: return String(localized: "Composer")
            case .genre: return String(localized: "Genre")
            case .year: return String(localized: "Year")
            case .trackNumber: return String(localized: "Track #")
            case .trackTotal: return String(localized: "of")
            case .discNumber: return String(localized: "Disc #")
            case .discTotal: return String(localized: "of")
            case .comment: return String(localized: "Comment")
            }
        }

        /// Fields that only make sense when editing a single file
        var isPerTrack: Bool {
            switch self {
            case .title, .trackNumber, .trackTotal, .discNumber, .discTotal:
                return true
            default:
                return false
            }
        }

        var isNumeric: Bool {
            switch self {
            case .trackNumber, .trackTotal, .discNumber, .discTotal:
                return true
            default:
                return false
            }
        }
    }

    // MARK: - Body

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if isLoading {
                ProgressView()
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    VStack(alignment: .leading, spacing: 16) {
                        HStack(alignment: .top, spacing: 16) {
                            artworkWell
                            textFieldsGrid
                        }
                        if !isMultiTrack {
                            lyricsEditor
                        }
                    }
                    .padding(16)
                }
            }

            Divider()
            footer
        }
        .frame(width: 560, height: isMultiTrack ? 420 : 560)
        .onAppear { loadTags() }
        .alert(String(localized: "Some files could not be updated"), isPresented: $showingErrors) {
            Button(String(localized: "OK")) { finish() }
        } message: {
            Text(writeErrors.map(\.message).joined(separator: "\n"))
        }
    }

    private var header: some View {
        HStack {
            Text(isMultiTrack
                 ? String(localized: "Edit Tags (\(tracks.count) tracks)")
                 : String(localized: "Edit Tags"))
                .font(.headline)
            Spacer()
            if !isMultiTrack, let track = tracks.first {
                Text(track.url.lastPathComponent)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var footer: some View {
        HStack {
            if isMultiTrack {
                Text("Only fields you change are applied to all tracks")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            Spacer()
            Button(String(localized: "Cancel")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(String(localized: "Save")) { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(isLoading || isSaving || !hasChanges)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    // MARK: - Fields

    private var visibleFields: [Field] {
        Field.allCases.filter { !isMultiTrack || !$0.isPerTrack }
    }

    private var textFieldsGrid: some View {
        Grid(alignment: .leading, horizontalSpacing: 8, verticalSpacing: 8) {
            ForEach(rowLayout, id: \.self) { row in
                GridRow {
                    ForEach(row, id: \.self) { field in
                        Text(field.label)
                            .foregroundColor(.secondary)
                            .gridColumnAlignment(.trailing)
                        fieldEditor(for: field)
                            .gridCellColumns(row.count == 1 ? 3 : 1)
                    }
                }
            }
        }
        .frame(maxWidth: .infinity)
    }

    /// Numeric pairs (track x of y) share a row; everything else gets its own.
    private var rowLayout: [[Field]] {
        var rows: [[Field]] = []
        var pendingPair: [Field] = []
        for field in visibleFields {
            if field.isNumeric {
                pendingPair.append(field)
                if pendingPair.count == 2 {
                    rows.append(pendingPair)
                    pendingPair = []
                }
            } else {
                rows.append([field])
            }
        }
        if !pendingPair.isEmpty { rows.append(pendingPair) }
        return rows
    }

    private func fieldEditor(for field: Field) -> some View {
        TextField(
            "",
            text: Binding(
                get: { fields[field] ?? "" },
                set: { fields[field] = $0 }
            ),
            prompt: isMultiTrack && initialFields[field] == nil ? Text("Mixed") : nil
        )
        .textFieldStyle(.roundedBorder)
        .frame(minWidth: field.isNumeric ? 50 : 120)
    }

    private var lyricsEditor: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Lyrics"))
                .foregroundColor(.secondary)
            TextEditor(text: $lyrics)
                .font(.body)
                .frame(height: 100)
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .stroke(Color(nsColor: .separatorColor))
                )
        }
    }

    // MARK: - Artwork

    private var artworkWell: some View {
        VStack(spacing: 8) {
            Group {
                if let data = displayedArtwork, let image = NSImage(data: data) {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    ZStack {
                        Rectangle().fill(Color(nsColor: .quaternaryLabelColor))
                        Image(systemName: "music.note")
                            .font(.system(size: 32))
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(width: 140, height: 140)
            .clipShape(RoundedRectangle(cornerRadius: 8))

            HStack(spacing: 8) {
                Button(String(localized: "Choose…")) { chooseArtwork() }
                Button(String(localized: "Remove")) { artworkState = .removed }
                    .disabled(displayedArtwork == nil)
            }
            .controlSize(.small)
        }
    }

    private var displayedArtwork: Data? {
        switch artworkState {
        case .unchanged: return currentArtwork
        case .replaced(let data): return data
        case .removed: return nil
        }
    }

    private func chooseArtwork() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.image]
        panel.allowsMultipleSelection = false
        panel.message = String(localized: "Choose album artwork")
        if panel.runModal() == .OK, let url = panel.url, let data = try? Data(contentsOf: url) {
            artworkState = .replaced(data)
        }
    }

    // MARK: - Load / Save

    private var hasChanges: Bool {
        if case .unchanged = artworkState {} else { return true }
        if lyrics != initialLyrics { return true }
        return visibleFields.contains { (fields[$0] ?? "") != (initialFields[$0] ?? "") }
    }

    private func loadTags() {
        let urls = tracks.map(\.url)
        Task.detached(priority: .userInitiated) {
            let allTags = urls.compactMap { MetadataWriter.readTags(from: $0) }

            await MainActor.run {
                var loaded: [Field: String] = [:]
                for field in Field.allCases {
                    let values = allTags.map { value(for: field, in: $0) ?? "" }
                    // A field prefills only when every selected file agrees on it;
                    // otherwise it stays empty and shows the "Mixed" prompt.
                    if let first = values.first, values.allSatisfy({ $0 == first }), !first.isEmpty {
                        loaded[field] = first
                    }
                }
                initialFields = loaded
                fields = loaded

                initialLyrics = allTags.count == 1 ? (allTags[0].lyrics ?? "") : ""
                lyrics = initialLyrics

                let artworks = allTags.map(\.artworkData)
                if let first = artworks.first ?? nil, artworks.allSatisfy({ $0 == first }) {
                    currentArtwork = first
                }

                isLoading = false
            }
        }
    }

    private func value(for field: Field, in tags: MetadataWriter.CurrentTags) -> String? {
        switch field {
        case .title: return tags.title
        case .artist: return tags.artist
        case .album: return tags.album
        case .albumArtist: return tags.albumArtist
        case .composer: return tags.composer
        case .genre: return tags.genre
        case .year: return tags.year
        case .trackNumber: return tags.trackNumber.map(String.init)
        case .trackTotal: return tags.trackTotal.map(String.init)
        case .discNumber: return tags.discNumber.map(String.init)
        case .discTotal: return tags.discTotal.map(String.init)
        case .comment: return tags.comment
        }
    }

    private func buildEdits() -> MetadataWriter.Edits {
        var edits = MetadataWriter.Edits()

        func stringEdit(_ field: Field) -> TagEdit<String> {
            let current = (fields[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard current != (initialFields[field] ?? "") else { return .keep }
            return .set(current.isEmpty ? nil : current)
        }

        func intEdit(_ field: Field) -> TagEdit<Int> {
            let current = (fields[field] ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard current != (initialFields[field] ?? "") else { return .keep }
            return .set(Int(current))
        }

        edits.title = stringEdit(.title)
        edits.artist = stringEdit(.artist)
        edits.album = stringEdit(.album)
        edits.albumArtist = stringEdit(.albumArtist)
        edits.composer = stringEdit(.composer)
        edits.genre = stringEdit(.genre)
        edits.year = stringEdit(.year)
        edits.comment = stringEdit(.comment)
        edits.trackNumber = intEdit(.trackNumber)
        edits.trackTotal = intEdit(.trackTotal)
        edits.discNumber = intEdit(.discNumber)
        edits.discTotal = intEdit(.discTotal)

        if !isMultiTrack && lyrics != initialLyrics {
            edits.lyrics = .set(lyrics.isEmpty ? nil : lyrics)
        }

        switch artworkState {
        case .unchanged: break
        case .replaced(let data): edits.artwork = .set(data)
        case .removed: edits.artwork = .set(nil)
        }

        return edits
    }

    private func save() {
        let edits = buildEdits()
        guard !edits.isEmpty else {
            dismiss()
            return
        }

        isSaving = true
        let urls = tracks.map(\.url)

        Task.detached(priority: .userInitiated) {
            let errors = MetadataWriter.apply(edits, to: urls)

            await MainActor.run {
                isSaving = false
                if errors.isEmpty {
                    finish()
                } else {
                    writeErrors = errors
                    showingErrors = true
                }
            }
        }
    }

    /// Refresh picks up edited files through their changed modification dates
    /// and reruns normalization (albums, artists, FTS) for them.
    private func finish() {
        libraryManager.refreshLibrary()
        dismiss()
    }
}

#endif
