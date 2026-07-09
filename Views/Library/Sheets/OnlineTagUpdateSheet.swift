#if os(macOS)
import SwiftUI

/// Identifiable payload driving `.sheet(item:)` presentation of the online tag
/// update sheet.
struct OnlineTagUpdateSession: Identifiable {
    let id = UUID()
    let tracks: [Track]
}

/// Sheet that looks up each selected track online (iTunes Search API), shows
/// the proposed tags next to the current ones, and applies the rows the user
/// keeps checked. Works for a single track or a whole selection.
struct OnlineTagUpdateSheet: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) private var dismiss

    let tracks: [Track]

    private struct Row: Identifiable {
        let id = UUID()
        let track: Track
        var candidates: [OnlineTagLookup.Candidate] = []
        var selectedCandidateId: UUID?
        var include = false
        var failureMessage: String?

        var selectedCandidate: OnlineTagLookup.Candidate? {
            candidates.first { $0.id == selectedCandidateId }
        }
    }

    private enum Stage {
        case searching(done: Int)
        case review
        case applying(done: Int)
        case finished(updated: Int, failed: Int)
    }

    @State private var rows: [Row] = []
    @State private var stage: Stage = .searching(done: 0)
    @State private var updateArtwork = true

    /// Matches at or above this score are preselected for applying.
    private let autoIncludeThreshold = 0.6

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()
            content
            Divider()
            footer
        }
        .frame(width: 720, height: 480)
        .task { await searchAll() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(String(localized: "Update Tags from Internet"))
                .font(.headline)
            Spacer()
            Toggle(String(localized: "Also update artwork"), isOn: $updateArtwork)
                .disabled(isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var content: some View {
        switch stage {
        case .searching(let done):
            VStack(spacing: 8) {
                ProgressView(value: Double(done), total: Double(tracks.count))
                    .frame(width: 300)
                Text(String(localized: "Searching… \(done) of \(tracks.count)"))
                    .foregroundColor(.secondary)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

        case .review, .applying, .finished:
            List {
                ForEach($rows) { $row in
                    rowView($row)
                }
            }
            .listStyle(.inset)
        }
    }

    private func rowView(_ row: Binding<Row>) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Toggle("", isOn: row.include)
                .labelsHidden()
                .disabled(row.wrappedValue.selectedCandidate == nil || isBusy)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(row.wrappedValue.track.artist) — \(row.wrappedValue.track.title)")
                    .fontWeight(.medium)
                    .lineLimit(1)

                if let candidate = row.wrappedValue.selectedCandidate {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.turn.down.right")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        Text(candidate.summary)
                            .font(.callout)
                            .foregroundColor(scoreColor(candidate.score))
                            .lineLimit(1)
                        scoreBadge(candidate.score)
                    }
                } else if let failure = row.wrappedValue.failureMessage {
                    Label(failure, systemImage: "exclamationmark.triangle")
                        .font(.callout)
                        .foregroundColor(.orange)
                } else {
                    Text(String(localized: "No match found"))
                        .font(.callout)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            if row.wrappedValue.candidates.count > 1 {
                Menu {
                    ForEach(row.wrappedValue.candidates) { candidate in
                        Button {
                            row.wrappedValue.selectedCandidateId = candidate.id
                            row.wrappedValue.include = true
                        } label: {
                            Text(candidate.summary)
                        }
                    }
                } label: {
                    Image(systemName: "chevron.up.chevron.down")
                }
                .menuStyle(.borderlessButton)
                .frame(width: 24)
                .disabled(isBusy)
            }
        }
        .padding(.vertical, 2)
    }

    private func scoreBadge(_ score: Double) -> some View {
        Text(score >= autoIncludeThreshold
             ? String(localized: "good match")
             : String(localized: "uncertain"))
            .font(.caption2)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Capsule().fill(scoreColor(score).opacity(0.15)))
            .foregroundColor(scoreColor(score))
    }

    private func scoreColor(_ score: Double) -> Color {
        score >= autoIncludeThreshold ? .green : .orange
    }

    private var footer: some View {
        HStack {
            statusLabel
            Spacer()
            Button(String(localized: "Close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(String(localized: "Apply to \(includedCount) tracks")) {
                Task { await applySelected() }
            }
            .keyboardShortcut(.defaultAction)
            .buttonStyle(.borderedProminent)
            .disabled(includedCount == 0 || isBusy)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var statusLabel: some View {
        switch stage {
        case .searching:
            EmptyView()
        case .review:
            Text(String(localized: "\(matchedCount) of \(tracks.count) matched — review and apply"))
                .foregroundColor(.secondary)
        case .applying(let done):
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Writing tags… \(done) of \(includedCount)"))
                    .foregroundColor(.secondary)
            }
        case .finished(let updated, let failed):
            if failed == 0 {
                Label(String(localized: "Updated \(updated) tracks"), systemImage: "checkmark.circle.fill")
                    .foregroundColor(.green)
            } else {
                Label(String(localized: "Updated \(updated), failed \(failed)"), systemImage: "exclamationmark.triangle.fill")
                    .foregroundColor(.orange)
            }
        }
    }

    // MARK: - Derived

    private var isBusy: Bool {
        switch stage {
        case .searching, .applying: return true
        default: return false
        }
    }

    private var includedCount: Int {
        rows.filter { $0.include && $0.selectedCandidate != nil }.count
    }

    private var matchedCount: Int {
        rows.filter { !$0.candidates.isEmpty }.count
    }

    // MARK: - Search

    private func searchAll() async {
        rows = tracks.map { Row(track: $0) }

        // A few lookups in flight at once; iTunes tolerates small bursts.
        await withTaskGroup(of: (Int, Result<[OnlineTagLookup.Candidate], Error>).self) { group in
            var nextIndex = 0
            var completed = 0

            func addTask(index: Int, track: Track) {
                group.addTask {
                    do {
                        let candidates = try await OnlineTagLookup.candidates(
                            title: track.title,
                            artist: track.artist
                        )
                        return (index, .success(candidates))
                    } catch {
                        return (index, .failure(error))
                    }
                }
            }

            while nextIndex < tracks.count && nextIndex < 3 {
                addTask(index: nextIndex, track: tracks[nextIndex])
                nextIndex += 1
            }

            for await (index, result) in group {
                completed += 1
                stage = .searching(done: completed)

                switch result {
                case .success(let candidates):
                    rows[index].candidates = candidates
                    if let best = candidates.first {
                        rows[index].selectedCandidateId = best.id
                        rows[index].include = best.score >= autoIncludeThreshold
                    }
                case .failure(let error):
                    rows[index].failureMessage = error.localizedDescription
                }

                if nextIndex < tracks.count {
                    addTask(index: nextIndex, track: tracks[nextIndex])
                    nextIndex += 1
                }
            }
        }

        stage = .review
    }

    // MARK: - Apply

    private func applySelected() async {
        let selected = rows.filter { $0.include && $0.selectedCandidate != nil }
        guard !selected.isEmpty else { return }

        stage = .applying(done: 0)
        var updated = 0
        var failed = 0

        for (index, row) in selected.enumerated() {
            guard let candidate = row.selectedCandidate else { continue }

            var edits = MetadataWriter.Edits()
            edits.title = .set(candidate.title)
            edits.artist = .set(candidate.artist)
            if !candidate.album.isEmpty { edits.album = .set(candidate.album) }
            if let albumArtist = candidate.albumArtist { edits.albumArtist = .set(albumArtist) }
            if let genre = candidate.genre { edits.genre = .set(genre) }
            if let year = candidate.year { edits.year = .set(year) }
            if let trackNumber = candidate.trackNumber { edits.trackNumber = .set(trackNumber) }
            if let trackTotal = candidate.trackTotal { edits.trackTotal = .set(trackTotal) }
            if let discNumber = candidate.discNumber { edits.discNumber = .set(discNumber) }

            if updateArtwork, let artwork = await OnlineTagLookup.artworkData(for: candidate) {
                edits.artwork = .set(artwork)
            }

            let url = row.track.url
            let errors = await Task.detached(priority: .userInitiated) {
                MetadataWriter.apply(edits, to: [url])
            }.value

            if errors.isEmpty { updated += 1 } else { failed += 1 }
            stage = .applying(done: index + 1)
        }

        stage = .finished(updated: updated, failed: failed)
        libraryManager.refreshLibrary()
    }
}

#endif
