# Chaparii for iOS / iPad — Plan

## Decisions (locked with user)
- **No spotDL / downloads** on iOS (can't spawn a binary there anyway).
- **Compromised feature set** for v1: browse library, playlists, now-playing, search, favorites. No tag editing, no online lookup, no downloads.
- **Library ingestion Phase 1: iTunes File Sharing** — user copies audio (and `.m3u8`) into the app's Documents via Finder/Files; the app indexes it.
- **Phase 2: server-side sync** — a server holds the master library; iOS uploads/downloads tracks + playlist state.

## Technical findings
- **SFBAudioEngine** supports iOS (`.iOS(.v15)`) → metadata reading + format support reuse on iOS.
- **GRDB** is cross-platform → the whole DB layer (`Managers/Database/*`, `Models/*`) reuses as-is.
- **Crescendo** (current playback engine) declares no iOS platform → **iOS playback = AVFoundation** (`AVAudioPlayer`/`AVPlayer`) behind a shared protocol. Verify Crescendo iOS support early; assume AVFoundation.
- Won't port: menu bar, mini-player `NSWindow`, `NSOpenPanel`, Sparkle, spotDL, `NSWorkspace`/`NSEvent` usage — all `#if os(macOS)`.

## Architecture
Single project (`Chaparii-Player.xcodeproj`) + a new **iOS app target**, sharing a **core**:
- **Shared** (both targets): `Models/`, `Managers/Database/` (GRDB), library/playlist query logic, metadata read (`Core/Metadata` read paths via SFBAudioEngine/AVAsset), and a new **`PlaybackEngine` protocol**.
- **macOS-only** (`#if os(macOS)`): AppKit managers (WindowManager, MenuBar, MiniPlayer, folder pickers), Crescendo engine impl, Spotify download, Sparkle, tag *writing*.
- **iOS-only** (new): AVFoundation engine impl, `AVAudioSession` + background-audio + `MPNowPlayingInfoCenter`/`MPRemoteCommandCenter` (lock-screen controls), Documents-based ingestion, SwiftUI iOS UI (TabView/NavigationStack/List).

## Phase 0 — Shared-core refactor (prerequisite, macOS stays working)
1. Introduce a `PlaybackEngine` protocol; make the existing Crescendo code conform (macOS). Route `PlaybackManager` through the protocol.
2. Fence all AppKit/macOS-only code with `#if os(macOS)`; extract any platform calls (file pickers, workspace, events) behind small protocols.
3. Verify the **macOS app still builds and runs** unchanged. (No behavior change — pure refactor.)

## Phase 1 — iOS MVP (iTunes File Sharing)
1. Add the iOS target; give it the shared core. Info.plist: `UIFileSharingEnabled=YES`, `LSSupportsOpeningDocumentsInPlace=YES`, background mode `audio`.
2. **Ingestion:** treat the app's `Documents/` as the single library "folder"; reuse the scan/index logic pointed at Documents (recursive). Import `.m3u8` playlists found there. A pull-to-refresh / on-launch scan rebuilds the DB index.
3. **Playback:** AVFoundation engine conforming to `PlaybackEngine`; `AVAudioSession` (playback category), background audio, lock-screen/Control-Center transport via `MPRemoteCommandCenter` + `MPNowPlayingInfoCenter`.
4. **UI (SwiftUI, iPhone + iPad):** `TabView` → Library (tracks/albums/artists), Playlists, Search, plus a Now-Playing bar + full-screen player. iPad uses `NavigationSplitView` (sidebar + content). Reuse view-model logic; new List-based views (no Table/column-customization on iOS).
5. Favorites + regular-playlist create/edit/reorder/delete (reuse `PlaylistManager`).

## Phase 2 — Server-side sync
- Server stores the master library + playlist/DB state; iOS uploads local additions and downloads the rest. Design the sync API + conflict handling later (out of scope for v1).

## Verification
- Phase 0: `xcodebuild -project Chaparii-Player.xcodeproj -scheme Chaparii-Player build` (macOS) unchanged; run and confirm playback/UI identical.
- Phase 1: run the iOS target in Simulator; copy sample mp3s into the app container (Simulator: drag into the app's Documents, or Finder File Sharing on device); confirm they index, play (with lock-screen controls), and that playlists/search/favorites work.

## Effort
Large. Phase 0 is a focused refactor; Phase 1 is a multi-week build (iOS UI + playback + ingestion). Recommend doing Phase 0 first as a self-contained, low-risk step that leaves macOS untouched.
