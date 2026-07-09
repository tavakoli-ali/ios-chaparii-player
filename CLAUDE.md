# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

A personal macOS music player: a fork of **Petrichor** (MIT, `kushalpandya/Petrichor`) on
branch `hiby-fork`. It plays the `HiBy_R1_Music` library
(`/Users/atavakoli/Downloads/HiBy_R1_Music`, ~1,400 tracks in language subfolders + `.m3u8`
playlists) that is synced to a HiBy R1 DAP. SwiftUI + AppKit, GRDB for the library database.

## Build & run

Debug build (ad-hoc signing — no Apple developer account):

```sh
xcodebuild -project Petrichor.xcodeproj -scheme Petrichor -configuration Debug \
  -derivedDataPath build/DerivedData build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual
```

- Product: `build/DerivedData/Build/Products/Debug/Petrichor Dev.app` — launch with `open`.
- Bundle IDs are `com.atavakoli.petrichor` / `com.atavakoli.petrichor.debug` (renamed from
  upstream). The Sparkle auto-update feed was removed.
- The project uses **filesystem-synchronized groups**: new source files are picked up without
  editing `project.pbxproj`.
- `Scripts/build-installer.sh` builds a distributable installer.

## Fork-specific gotchas

- **`ENABLE_APP_SANDBOX = NO`** in `project.pbxproj` is required. The sandbox silently kills the
  spawned `spotdl` binary — do not re-enable it.
- The library database lives at
  `~/Library/Application Support/com.atavakoli.petrichor.debug/` (migrated out of the old sandbox
  container; the copy under `~/Library/Containers/com.atavakoli.petrichor.debug` is stale).
- Single-file SourceKit diagnostics ("Cannot find type X in scope") are indexing noise — trust the
  full `xcodebuild` result, not per-file diagnostics.

## Layout

- `PetrichorApp.swift`, `Application/` — app entry and top-level wiring.
- `Managers/` — business logic, split by domain. `Library/` (`LibraryManager` + `LM*` extensions),
  `Database/` (`DatabaseManager` + `DM*` extensions, GRDB), `Playlist/`, plus `PlaybackManager`,
  `SpotifyDownloadManager`, `ArtistBioManager`, etc. Managers are `@MainActor ObservableObject`s;
  DB work runs off-main and hops back to `MainActor` to publish.
- `Views/` — SwiftUI. `Main/` (player bar, window shell), `Library/`, `Playlists/`, `Home/`,
  `Folders/`, `Components/` (reusable views incl. the shared context-menu builder).
- `Models/` — GRDB records and value types (`Track`, `Folder`, `Playlist`, entities).
- `Core/` — cross-cutting (metadata read/write, playback engine, logging).
- `Utilities/` — helpers (`FilesystemUtils`, etc.).

## Features added on top of upstream

- **Tag editor** — `Core/Metadata/MetadataWriter.swift` (SFBAudioEngine/TagLib),
  `Views/Library/Sheets/TagEditorSheet.swift`, "Edit Tags…" context item. Refresh via
  `libraryManager.refreshLibrary()` (mtime-based reprocess).
- **Online tag lookup** — `Core/Metadata/OnlineTagLookup.swift` (iTunes Search API, no key, 600×600
  artwork) + `Views/Library/Sheets/OnlineTagUpdateSheet.swift`; "Update Tags from Internet…"
  context item, single and batch.
- **Spotify downloads** — `Managers/SpotifyDownloadManager.swift` +
  `Views/Library/Sheets/SpotifyDownloadSheet.swift`. Bundled `spotdl` 4.5.0 arm64 at
  `Resources/ThirdParty/spotdl` (audio from YouTube, Spotify metadata). Song→album via
  `--fetch-albums` (no creds); artist top-tracks/top-album need user Spotify client credentials
  (Keychain `com.atavakoli.petrichor.spotify.*`); ffmpeg auto-installed to `~/.spotdl/ffmpeg`.
  On success the sheet hard-refreshes the library folder containing the download so new tracks
  appear immediately, and warns if the destination is outside the library.

## Conventions

- User-facing strings use `String(localized:)`; see `docs/LOCALIZATION.md`.
- The track right-click menu is built once in `Views/Components/TrackContextMenu.swift`
  (`createMenuItems(for:playlistManager:currentContext:)`) and reused by every surface (lists and
  the player bar) so they stay identical. Menu actions are dispatched via `NotificationCenter`
  names (e.g. `EditTrackTags`, `ShowSpotifyDownload`, `goToLibraryFilter`).
- Match surrounding style; don't reformat untouched code.
