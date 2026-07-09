---
name: build-run-ios
description: Build, install, launch, and screenshot the Chaparii-iOS (iPhone/iPad) app in the iOS Simulator. Use whenever asked to build, run, launch, or verify the iOS/iPad app, or to check an iOS change compiles/works. For the macOS app use the build-run skill instead.
---

# Build & run Chaparii-iOS (Simulator)

The iPhone/iPad app (target `Chaparii-iOS`, bundle `com.chaparii.player.ios.Chaparii-iOS`), sharing
the core with the macOS app. Run all commands from the repo root (`~/Projects/petrichor-fork`).
Default simulator: **iPhone 17 Pro**.

## Build (Debug, simulator)

```sh
xcodebuild -project Chaparii-Player.xcodeproj -scheme Chaparii-iOS -sdk iphonesimulator \
  -configuration Debug -derivedDataPath build/DerivedDataiOS \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build
```

- Look for `** BUILD SUCCEEDED **`. Ignore SourceKit per-file diagnostics ("Cannot find type … in
  scope", "AVAudioSession unavailable in macOS") — the indexer often uses the wrong target; trust
  the `xcodebuild` result.
- App bundle: `build/DerivedDataiOS/Build/Products/Debug-iphonesimulator/Chaparii-iOS.app`.

## Install, launch, screenshot

```sh
APP="build/DerivedDataiOS/Build/Products/Debug-iphonesimulator/Chaparii-iOS.app"
BID="com.chaparii.player.ios.Chaparii-iOS"
open -a Simulator                                    # ensure the sim is booted/awake
xcrun simctl terminate "iPhone 17 Pro" "$BID" 2>/dev/null
xcrun simctl install  "iPhone 17 Pro" "$APP"         # MUST re-install to pick up a new build
xcrun simctl launch   "iPhone 17 Pro" "$BID"
sleep 6
xcrun simctl io "iPhone 17 Pro" screenshot /tmp/chaparii_ios.png
```

Then read `/tmp/chaparii_ios.png` to inspect the UI.

## Gotchas

- **Always `simctl install` after a rebuild** — `launch` alone re-runs the previously-installed
  binary, so you'll screenshot the old build and think a change didn't take.
- If a screenshot fails with "Timeout waiting for screen surfaces", the sim display went idle:
  `open -a Simulator`, wait a few seconds, relaunch, retry.
- **No `idb`/`cliclick` and osascript lacks accessibility access** — you cannot drive taps
  programmatically. To verify a non-default tab/screen, temporarily set the `TabView` selection
  default (or auto-play the first track / auto-open a playlist) in the view, screenshot, then revert
  the temp edit. Playback-dependent UI (mini-player, Now Playing) only renders once something plays.
- **`simctl install` mints a NEW data container in this environment**, wiping seeded audio and the
  DB. After each install, re-seed and expect a fresh scan:
  ```sh
  CUR=$(xcrun simctl get_app_container "iPhone 17 Pro" "$BID" data)
  cp -R "/Users/atavakoli/Downloads/HiBy_R1_Music/Arabic" "$CUR/Documents/Arabic"   # small test set
  cp "/Users/atavakoli/Downloads/HiBy_R1_Music/Arabic.m3u8" "$CUR/Documents/"
  ```
  Because scan runs in background, the first launch after seeding may still be empty — **relaunch**
  (no reinstall) so the now-indexed library loads, then screenshot. Inspect state directly with
  `sqlite3 "$CUR/Library/Application Support/$BID/petrichor.db" "SELECT COUNT(*) FROM tracks;"`.
- App logs: `xcrun simctl spawn "iPhone 17 Pro" log show --last 90s --info --debug --predicate 'processImagePath CONTAINS "Chaparii-iOS"' | grep 'music]'` (the app's Logger uses the `music` category; needs `--info --debug`).

## Verify a change

Build → install → launch → screenshot, and read the screenshot. Don't claim a runtime behavior
works from a successful build alone.
