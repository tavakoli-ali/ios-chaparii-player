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
  default (or launch state) to that tab, screenshot, then revert. Playback-dependent UI (the
  mini-player) only renders once something is playing.
- Library ingestion on iOS reads the app's Documents folder (iTunes File Sharing). The simulator's
  Documents persists across installs, so previously-copied tracks remain.

## Verify a change

Build → install → launch → screenshot, and read the screenshot. Don't claim a runtime behavior
works from a successful build alone.
