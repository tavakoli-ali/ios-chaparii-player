import SwiftUI

/// Identifiable payload driving `.sheet(item:)` presentation of the Spotify
/// download sheet.
struct SpotifyDownloadSession: Identifiable {
    let id = UUID()
    let track: Track
}

/// Sheet for downloading more music related to a library track: the song's full
/// album, the artist's top tracks, or the artist's most popular album. Work is
/// done by the bundled spotDL; see SpotifyDownloadManager.
struct SpotifyDownloadSheet: View {
    @EnvironmentObject var libraryManager: LibraryManager
    @Environment(\.dismiss) private var dismiss
    @StateObject private var manager = SpotifyDownloadManager()

    let track: Track

    @State private var query: String
    @State private var mode: SpotifyDownloadManager.Mode = .songAlbum
    @AppStorage("spotifyDownloadFolder")
    private var savedDownloadFolder = ""
    @State private var destination: URL?

    @State private var credentialsAvailable = false
    @State private var showingCredentials = false
    @State private var clientId = ""
    @State private var clientSecret = ""

    init(track: Track) {
        self.track = track
        let artist = track.artist.isEmpty ? "" : "\(track.artist) - "
        _query = State(initialValue: "\(artist)\(track.title)")
    }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    querySection
                    modeSection
                    destinationSection
                    if showingCredentials {
                        credentialsSection
                    }
                    if !manager.logLines.isEmpty {
                        logSection
                    }
                }
                .padding(16)
            }

            Divider()
            footer
        }
        .frame(width: 560, height: 520)
        .onAppear {
            credentialsAvailable = manager.hasCredentials
            destination = defaultDestination
        }
        .onDisappear { manager.cancel() }
    }

    // MARK: - Sections

    private var header: some View {
        HStack {
            Text(String(localized: "Download from Spotify"))
                .font(.headline)
            Spacer()
            Text("Audio is sourced from YouTube — personal use only")
                .font(.caption)
                .foregroundColor(.secondary)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    private var querySection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Song to match"))
                .foregroundColor(.secondary)
            TextField("", text: $query, prompt: Text("Artist - Title, or a Spotify URL"))
                .textFieldStyle(.roundedBorder)
                .disabled(manager.phase.isBusy)
        }
    }

    private var modeSection: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(String(localized: "Download"))
                .foregroundColor(.secondary)

            ForEach(SpotifyDownloadManager.Mode.allCases) { candidate in
                let locked = candidate.needsCredentials && !credentialsAvailable
                HStack(spacing: 6) {
                    Toggle(isOn: Binding(
                        get: { mode == candidate },
                        set: { if $0 { mode = candidate } }
                    )) {
                        Text(candidate.title)
                    }
                    .toggleStyle(RadioButtonToggleStyle())
                    .disabled(locked || manager.phase.isBusy)

                    if locked {
                        Image(systemName: "lock.fill")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
            }

            if !credentialsAvailable {
                Button {
                    showingCredentials.toggle()
                } label: {
                    Text("Artist options need free Spotify API credentials — add them…")
                        .font(.caption)
                }
                .buttonStyle(.link)
            }
        }
    }

    private var destinationSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Save to"))
                .foregroundColor(.secondary)
            HStack {
                Text(destination?.path ?? String(localized: "No folder selected"))
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .foregroundColor(destination == nil ? .secondary : .primary)
                Spacer()
                Button(String(localized: "Choose…")) { chooseDestination() }
                    .disabled(manager.phase.isBusy)
            }
            .padding(8)
            .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
        }
    }

    private var credentialsSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(String(localized: "Spotify API credentials"))
                .foregroundColor(.secondary)
            Text("Create a free app at developer.spotify.com/dashboard and paste its Client ID and Client Secret here. They are stored in your keychain.")
                .font(.caption)
                .foregroundColor(.secondary)
            TextField(String(localized: "Client ID"), text: $clientId)
                .textFieldStyle(.roundedBorder)
            SecureField(String(localized: "Client Secret"), text: $clientSecret)
                .textFieldStyle(.roundedBorder)
            Button(String(localized: "Save Credentials")) {
                SpotifyDownloadManager.saveCredentials(clientId: clientId, clientSecret: clientSecret)
                credentialsAvailable = manager.hasCredentials
                showingCredentials = false
            }
            .disabled(clientId.isEmpty || clientSecret.isEmpty)
        }
        .padding(10)
        .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .quaternaryLabelColor).opacity(0.5)))
    }

    private var logSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(String(localized: "Progress"))
                .foregroundColor(.secondary)
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 2) {
                        ForEach(Array(manager.logLines.enumerated()), id: \.offset) { index, line in
                            Text(line)
                                .font(.system(size: 11, design: .monospaced))
                                .textSelection(.enabled)
                                .id(index)
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(6)
                }
                .frame(height: 140)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .textBackgroundColor)))
                .onChange(of: manager.logLines.count) { _, count in
                    proxy.scrollTo(count - 1, anchor: .bottom)
                }
            }
        }
    }

    private var footer: some View {
        HStack(spacing: 8) {
            statusLabel
            Spacer()

            if manager.phase.isBusy {
                Button(String(localized: "Cancel Download")) { manager.cancel() }
            }
            Button(String(localized: "Close")) { dismiss() }
                .keyboardShortcut(.cancelAction)
            Button(String(localized: "Download")) { startDownload() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.borderedProminent)
                .disabled(!canStart)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
    }

    @ViewBuilder private var statusLabel: some View {
        switch manager.phase {
        case .idle:
            EmptyView()
        case .preparingFFmpeg:
            Label(String(localized: "Setting up ffmpeg…"), systemImage: "gear")
                .foregroundColor(.secondary)
        case .resolving:
            Label(String(localized: "Finding music…"), systemImage: "magnifyingglass")
                .foregroundColor(.secondary)
        case .downloading:
            HStack(spacing: 6) {
                ProgressView().controlSize(.small)
                Text(String(localized: "Downloading…"))
                    .foregroundColor(.secondary)
            }
        case .finished(let count):
            Label(String(localized: "Downloaded \(count) tracks"), systemImage: "checkmark.circle.fill")
                .foregroundColor(.green)
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundColor(.red)
                .lineLimit(2)
        }
    }

    // MARK: - Actions

    private var canStart: Bool {
        !manager.phase.isBusy
            && destination != nil
            && !query.trimmingCharacters(in: .whitespaces).isEmpty
    }

    private var defaultDestination: URL? {
        if !savedDownloadFolder.isEmpty {
            let url = URL(fileURLWithPath: savedDownloadFolder)
            if FileManager.default.fileExists(atPath: url.path) { return url }
        }
        return libraryManager.folders.first?.url
    }

    private func chooseDestination() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.canCreateDirectories = true
        panel.directoryURL = destination
        panel.message = String(localized: "Choose where to save the downloaded tracks")
        if panel.runModal() == .OK, let url = panel.url {
            destination = url
            savedDownloadFolder = url.path
        }
    }

    private func startDownload() {
        guard let destination else { return }
        manager.start(
            mode: mode,
            query: query.trimmingCharacters(in: .whitespaces),
            destination: destination
        ) {
            // Make the freshly downloaded tracks appear on the page. A hard,
            // targeted rescan of the library folder that contains the download
            // guarantees pickup: the default soft refresh can skip a folder
            // whose top-level mtime/hash heuristic doesn't flag a change.
            if let folder = containingLibraryFolder(for: destination) {
                libraryManager.refreshFolder(folder, hardRefresh: true)
            } else {
                // The chosen destination is outside every library folder, so a
                // rescan can never surface the tracks — tell the user why.
                NotificationManager.shared.addMessage(
                    .warning,
                    String(localized: "Downloaded to a folder outside your library, so the tracks won't appear. Choose a folder inside your music library.")
                )
            }
        }
    }

    /// The library folder that `url` lives in (equal to it or a descendant), or
    /// nil if the download landed outside every watched library folder.
    private func containingLibraryFolder(for url: URL) -> Folder? {
        let target = url.standardizedFileURL.path
        return libraryManager.folders.first { folder in
            let base = folder.url.standardizedFileURL.path
            return target == base || target.hasPrefix(base.hasSuffix("/") ? base : base + "/")
        }
    }
}

/// macOS radio-button look for a Toggle used as a single-choice option.
private struct RadioButtonToggleStyle: ToggleStyle {
    func makeBody(configuration: Configuration) -> some View {
        Button {
            configuration.isOn = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: configuration.isOn ? "circle.inset.filled" : "circle")
                    .foregroundColor(configuration.isOn ? .accentColor : .secondary)
                configuration.label
            }
        }
        .buttonStyle(.plain)
    }
}
