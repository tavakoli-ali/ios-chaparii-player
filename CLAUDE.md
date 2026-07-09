# CLAUDE.md

Guidance for Claude Code when working in this repository.

## What this is

**Chaparii** — a personal music player, forked from **Petrichor** (MIT, `kushalpandya/Petrichor`)
on branch `hiby-fork`. GitHub: `tavakoli-ali/ios-chaparii-player`. It plays the `HiBy_R1_Music`
library (`/Users/atavakoli/Downloads/HiBy_R1_Music`, ~1,400 tracks in language subfolders +
`.m3u8` playlists) synced to a HiBy R1 DAP.

Two targets in one project (`Chaparii-Player.xcodeproj`) sharing a common core:

- **`Chaparii-Player`** — the original macOS app (SwiftUI + AppKit). Product: `Chaparii Dev.app`
  (Debug) / `Chaparii.app` (Release). Bundle `com.chaparii.player` / `.debug`.
- **`Chaparii-iOS`** — the iPhone/iPad app (SwiftUI). Bundle `com.chaparii.player.ios.Chaparii-iOS`.
  Sources live in `Chaparii-iOS/`.

Shared across both: `Models/` (GRDB records), `Managers/` (library/playlist/playback logic),
`Core/` (metadata + playback engine). GRDB is the cross-platform library database.

## Build & run

Run all commands from the repo root (`~/Projects/petrichor-fork`). Ad-hoc signed (no Apple
developer account). See the **`build-run`** and **`build-run-ios`** skills for the full flows.

**macOS** (Debug):

```sh
xcodebuild -project Chaparii-Player.xcodeproj -scheme Chaparii-Player -configuration Debug \
  -derivedDataPath build/DerivedData build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual
```
Launch: `open "build/DerivedData/Build/Products/Debug/Chaparii Dev.app"`.

**iOS** (simulator):

```sh
xcodebuild -project Chaparii-Player.xcodeproj -scheme Chaparii-iOS -sdk iphonesimulator \
  -configuration Debug -derivedDataPath build/DerivedDataiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```
Then `xcrun simctl install "iPhone 17 Pro" <.app>` and `xcrun simctl launch …`.

- Both schemes are **shared** (in `xcshareddata/xcschemes/`) so CI/xcodebuild can see them.
- The project uses **filesystem-synchronized groups**: new source files are picked up without
  editing `project.pbxproj`. Membership exceptions in `project.pbxproj` control which files each
  target excludes.
- `Scripts/build-installer.sh` builds a distributable macOS installer.

## Fork-specific gotchas

- **`ENABLE_APP_SANDBOX = NO`** (macOS) is required. The sandbox silently kills the spawned
  `spotdl` binary — do not re-enable it.
- The macOS library database lives at `~/Library/Application Support/com.chaparii.player.debug/`.
- **Single-file SourceKit diagnostics ("Cannot find type X in scope") are indexing noise** — the
  linter frequently indexes shared files against the wrong target (e.g. flagging `AVAudioSession`
  as "unavailable in macOS" in the iOS app). Trust the full `xcodebuild` result, not per-file
  diagnostics.

## Cross-platform structure

The port keeps a single shared core and fences platform-specific code:

- **`MediaBackend.current`** returns `.sfb` on iOS (SFBAudioEngine backend, no AppKit) and may use
  the macOS-only `.crescendo` backend on macOS. `PlaybackManager` → `PlaybackEngine` →
  `PlaybackBackend` protocol.
- **`#if os(macOS)` / `#if os(iOS)`** fences AppKit shells, menu bar, `NSOpenPanel`, Sparkle, and
  spotDL. `Utilities/PlatformImage.swift` typealiases `PlatformImage`/`PlatformColor`/`PlatformFont`;
  `Utilities/BookmarkOptions.swift` fences security-scoped bookmarks.
- The macOS entry is `PetrichorApp.swift` (file not renamed); the iOS entry is
  `Chaparii-iOS/Chaparii_iOSApp.swift`.

## iOS app (`Chaparii-iOS/`)

- **Feature set is deliberately compromised** (see `docs/iOS-plan.md`): browse, playlists, search,
  now-playing, favorites, playback resume. **No tag editing, no online lookup, no downloads**
  (can't spawn `spotdl`).
- **UI**: `RootView.swift` is a 5-tab shell — Library, Browse, Playlists, Search, Now Playing —
  with `MiniPlayerBar` floating above the tab bar (tap it to open the player; it hides on the
  Now Playing tab, animated).
  - `LibraryListView` — flat track list; long-press a row to Favorite or Add to a user playlist.
  - `BrowseView` — Artist / Album / Genre / **Folders** (Folders is a filesystem tree derived from
    each track's on-disk path via `FolderBrowseView`).
  - `PlaylistsListView` — create (`+`), rename/delete (swipe) user playlists; smart playlists
    (Favorites, Top 25) are protected. Detail view has **Play / Shuffle** header buttons, per-track
    swipe to favorite / remove, and lazily loads tracks via `getPlaylistTracks`
    (`loadSmartPlaylistTracks` for smart ones).
  - `NowPlayingView` — minimal: artwork, title/artist, scrubbable seek bar, prev/play/next,
    **shuffle + repeat** (own row), a toolbar heart (favorite) and a **"•••" menu** (Go to Artist /
    Go to Album → pushes an `EntityTracksView`).
- **Ingestion (Phase 1, iTunes File Sharing)**: the user copies audio (+ `.m3u8`) into the app's
  Documents via Finder/Files; `LibraryManager+iOS.ensureDocumentsFolderAndScan(forceRescan:)`
  registers Documents as a library folder, scans, loads tracks, then **auto-imports `.m3u8`/`.m3u`**
  (`PlaylistManager+iOS.autoImportDocumentsPlaylists`). Run once at the shell level in `RootView`'s
  `.task`. **Scans only when needed** (first run / after a container change) — normal launches just
  load from the DB; the refresh button / pull-to-refresh pass `forceRescan: true`. An `isScanning`
  banner shows while processing.
- **Playback resume**: `AppCoordinator` saves state on the periodic "SavePlaybackState" notification
  and restores on launch; the iOS app also saves on scene background (`Chaparii_iOSApp` scenePhase).
- **Playlist auto-import repair**: `autoImportDocumentsPlaylists` rebuilds a user playlist whose
  track links were cascade-removed by a container change (deletes the empty one, re-imports);
  populated playlists are left alone. Match is by relative path, filename fallback.

### iOS gotchas (hard-won)

- **Container UUID changes on every (re)install.** Absolute paths in the DB go stale. Two mitigations:
  `DocumentsPathResolver` rebases stored paths onto the live Documents dir at decode time; and
  `ensureDocumentsFolderAndScan` prunes stale folder rows (cascading their dead tracks) and
  re-scans. This is why playback / playlists break until a rebuild after a reinstall.
- **Scan concurrency deadlock (fixed):** `DMTrackProcessing.processBatch` caps parse concurrency
  under `#if os(iOS)` — the `#available(macOS 15)` guard is false on iOS, and over-subscribing iOS's
  small cooperative pool with blocking parses deadlocks the scan (empty library, silent hang).
- **Duplicates**: the scan's quality-scored `detectAndMarkDuplicates()` flags all but the best copy;
  the app registers `hideDuplicateTracks = true` so every query surfaces only the primary. Non-destructive.
- **Simulator testing**: `simctl install` mints a new data container here, wiping seeded audio and the
  DB — re-seed Documents after each install, and there's no tap/UI-automation tool, so verify
  interactive flows by temporarily defaulting the tab / auto-playing, then reverting.
- **Phase 2 (planned)**: server-side sync via the Subsonic API (Navidrome). Not yet built.

## macOS layout

- `PetrichorApp.swift`, `Application/` — macOS app entry and top-level wiring.
- `Managers/` — business logic by domain: `Library/` (`LibraryManager` + `LM*` extensions),
  `Database/` (`DatabaseManager` + `DM*` extensions, GRDB), `Playlist/`, plus `PlaybackManager`,
  `SpotifyDownloadManager` (macOS-only), etc. Managers are `@MainActor ObservableObject`s; DB work
  runs off-main and hops back to `MainActor` to publish.
- `Views/` — macOS SwiftUI (`#if os(macOS)`): `Main/`, `Library/`, `Playlists/`, `Home/`,
  `Folders/`, `Components/` (reusable views incl. the shared context-menu builder).
- `Models/` — GRDB records and value types (`Track`, `Folder`, `Playlist`, entities). Shared.
- `Core/` — cross-cutting (metadata read/write, playback engine, logging). Shared.
- `Utilities/` — helpers.

## macOS features added on top of upstream

- **Tag editor** — `Core/Metadata/MetadataWriter.swift`, `Views/Library/Sheets/TagEditorSheet.swift`.
- **Online tag lookup** — `Core/Metadata/OnlineTagLookup.swift` (iTunes Search API) +
  `Views/Library/Sheets/OnlineTagUpdateSheet.swift`.
- **Spotify downloads** — `Managers/SpotifyDownloadManager.swift` + bundled `spotdl` 4.5.0 arm64 at
  `Resources/ThirdParty/spotdl`; ffmpeg auto-installed to `~/.spotdl/ffmpeg`. Artist top-tracks need
  user Spotify client credentials (Keychain `com.atavakoli.petrichor.spotify.*`). **Handle
  credentials/tokens in-process only — never print or write them.**

## CI

`.github/workflows/ci.yml`: SwiftLint (Linux) + actionlint gate, then macOS `build analyze`
(`Chaparii-Player`) **and** iOS simulator `build analyze` (`Chaparii-iOS`, generic simulator
destination) in parallel, plus a Release build check on push to `main`/tags. `ci-summary` is the
single required status. Env `SCHEME`/`PROJECT`/`IOS_SCHEME` must match the renamed targets.

## Conventions

- User-facing strings use `String(localized:)`; see `docs/LOCALIZATION.md`.
- The macOS track right-click menu is built once in `Views/Components/TrackContextMenu.swift` and
  reused by every surface so they stay identical. Actions dispatch via `NotificationCenter` names.
- Match surrounding style; don't reformat untouched code.
