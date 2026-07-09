---
name: build-run
description: Build and launch the Petrichor (hiby-fork) macOS app. Use whenever asked to build, compile, run, launch, or open the app, or to verify a change compiles/works in the real app.
---

# Build & run Petrichor (hiby-fork)

Personal macOS music player, ad-hoc signed (no Apple developer account). Run all commands from
the repo root (`~/Projects/petrichor-fork`).

## Build (Debug)

```sh
xcodebuild -project Petrichor.xcodeproj -scheme Petrichor -configuration Debug \
  -derivedDataPath build/DerivedData build \
  CODE_SIGN_IDENTITY=- CODE_SIGNING_REQUIRED=YES DEVELOPMENT_TEAM= CODE_SIGN_STYLE=Manual
```

- Look for `** BUILD SUCCEEDED **` at the end. Errors are Swift compiler lines, not the SourceKit
  "Cannot find type … in scope" per-file diagnostics — those are single-file indexing noise and
  are safe to ignore; trust the `xcodebuild` result.
- The build can take a couple of minutes cold; allow a generous timeout.

## Launch

```sh
open "build/DerivedData/Build/Products/Debug/Petrichor Dev.app"
```

## Verify a change

To confirm a UI/behavior change, build then `open` the app and exercise the affected flow (e.g.
right-click a track for the context menu; download a track from the Spotify sheet and confirm it
appears). Do not claim a change works from a successful build alone if it has runtime behavior.

## Gotchas

- Do **not** enable the App Sandbox (`ENABLE_APP_SANDBOX = NO` must stay) — it kills the spawned
  `spotdl` binary.
- Library DB: `~/Library/Application Support/com.atavakoli.petrichor.debug/`.
- New source files are picked up automatically (filesystem-synchronized groups); no
  `project.pbxproj` edits needed.
