<img width="170" src=".github/assets/DefaultAppIcon.png" alt="Chaparii App Icon" align="left"/>

<div>
<h3>Chaparii</h3>
<p>A personal offline music player for macOS & iOS</p>
</div>

<br/><br/>

<div align="center">
<a href="https://github.com/tavakoli-ali/ios-chaparii-player/actions/workflows/ci.yml"><img alt="CI" src="https://img.shields.io/github/actions/workflow/status/tavakoli-ali/ios-chaparii-player/ci.yml?label=CI&style=flat-square"></a>
<a href="LICENSE"><img alt="License" src="https://img.shields.io/badge/License-MIT-ffa726?style=flat-square"></a>
<img src="https://img.shields.io/badge/platform-macOS%20%7C%20iOS-blue.svg?label=Platform&style=flat-square&logo=apple" alt="Platform"/>
</div>

---

## Summary

**Chaparii** is a personal music player built on top of
[**Petrichor**](https://github.com/kushalpandya/Petrichor) (MIT). It plays my
`HiBy_R1_Music` library — roughly 1,400 tracks organized into language subfolders
with `.m3u8` playlists — synced to a HiBy R1 DAP, and runs on both macOS and iOS.

This is a personal project, not a general-purpose release: it's tuned for my own
library and workflow rather than distributed to end users.

### 🎵 Two apps, one shared core

- **macOS** (`Chaparii-Player`) — the full SwiftUI + AppKit app: browse, playlists,
  search, now-playing, favorites, tag editing, online tag lookup, and Spotify
  downloads via a bundled `spotdl`.
- **iOS / iPadOS** (`Chaparii-iOS`) — a deliberately trimmed companion: browse
  (Artist / Album / Genre / Folders), playlists, search, now-playing, favorites, and
  playback resume. **No tag editing, online lookup, or downloads.** Audio is ingested
  via iTunes File Sharing (copy audio + `.m3u8` into the app's Documents folder).

Both share `Models/` (GRDB records), `Managers/` (library/playlist/playback logic),
and `Core/` (metadata + playback engine). GRDB is the cross-platform library database.

### ✨ Features

- Wide audio format support: MP3, AAC/M4A, WAV, AIFF, ALAC, Ogg Vorbis, Speex, Opus,
  FLAC, APE, MPC, TTA, WavPack, DSF/DFF, plus MOD/IT/S3M/XM and AU.
- Map music folders and browse an organized library view.
- Create, import, and export playlists (including `.m3u8` auto-import on iOS).
- Folder-tree browsing, favorites, and go-to-artist / go-to-album navigation.
- Native macOS menubar and dock playback controls, plus dark mode.
- Handles large libraries with thousands of tracks; duplicate detection surfaces only
  the best copy of each track.

💡 **Tip**: Chaparii relies on tracks having good metadata for its features to work well.

### Requirements

- **macOS 14** or later
- **iOS 17** or later (simulator or device)

## 🏗️ Development

### Implementation overview

- Built with Swift and SwiftUI, with AppKit on macOS for native integration.
- On first run the app scans mapped folders, extracts metadata, and populates an
  SQLite database. It **never** alters your audio files — it only reads them.
- Track search uses [SQLite FTS5](https://www.sqlite.org/fts5.html).
- Playback runs through the [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine)
  backend (`MediaBackend.current`), with a macOS-only alternate backend.

See [`CLAUDE.md`](CLAUDE.md) for the full build/run flow, cross-platform structure, and
fork-specific gotchas, and [`docs/iOS-plan.md`](docs/iOS-plan.md) for the iOS scope.

<details>
<summary>View database schema</summary>

```mermaid
erDiagram
    folders {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT name "NOT NULL"
        TEXT path "NOT NULL UNIQUE"
        INTEGER track_count "NOT NULL DEFAULT 0"
        DATETIME date_added "NOT NULL"
        DATETIME date_updated "NOT NULL"
        BLOB bookmark_data "Security-scoped bookmark"
    }

    artists {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT name "NOT NULL"
        TEXT normalized_name "NOT NULL UNIQUE"
        TEXT sort_name
        BLOB artwork_data
        TEXT bio
        TEXT bio_source
        DATETIME bio_updated_at
        TEXT image_url
        TEXT image_source
        DATETIME image_updated_at
        TEXT discogs_id
        TEXT musicbrainz_id
        TEXT spotify_id
        TEXT apple_music_id
        TEXT country
        INTEGER formed_year
        INTEGER disbanded_year
        TEXT genres "JSON array"
        TEXT websites "JSON array"
        TEXT members "JSON array"
        INTEGER total_tracks "NOT NULL DEFAULT 0 CHECK >= 0"
        INTEGER total_albums "NOT NULL DEFAULT 0 CHECK >= 0"
        DATETIME created_at "NOT NULL"
        DATETIME updated_at "NOT NULL"
    }

    albums {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT title "NOT NULL"
        TEXT normalized_title "NOT NULL"
        TEXT sort_title
        BLOB artwork_data
        TEXT release_date
        INTEGER release_year "CHECK 1900-2100"
        TEXT album_type
        INTEGER total_tracks "CHECK >= 0"
        INTEGER total_discs "CHECK >= 0"
        TEXT description
        TEXT review
        TEXT review_source
        TEXT cover_art_url
        TEXT thumbnail_url
        TEXT discogs_id
        TEXT musicbrainz_id
        TEXT spotify_id
        TEXT apple_music_id
        TEXT label
        TEXT catalog_number
        TEXT barcode
        TEXT genres "JSON array"
        DATETIME created_at "NOT NULL"
        DATETIME updated_at "NOT NULL"
    }

    album_artists {
        INTEGER album_id FK "NOT NULL"
        INTEGER artist_id FK "NOT NULL"
        TEXT role "NOT NULL DEFAULT 'primary'"
        INTEGER position "NOT NULL DEFAULT 0"
    }

    genres {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT name "NOT NULL UNIQUE"
    }

    tracks {
        INTEGER id PK "AUTO_INCREMENT"
        INTEGER folder_id FK "NOT NULL"
        INTEGER album_id FK
        TEXT path "NOT NULL UNIQUE"
        TEXT filename "NOT NULL"
        TEXT title
        TEXT artist
        TEXT album
        TEXT composer
        TEXT genre
        TEXT year
        REAL duration "CHECK >= 0"
        TEXT format
        INTEGER file_size
        DATETIME date_added "NOT NULL"
        DATETIME date_modified
        BLOB track_artwork_data
        BOOLEAN is_favorite "NOT NULL DEFAULT false"
        INTEGER play_count "NOT NULL DEFAULT 0"
        DATETIME last_played_date
        BOOLEAN is_duplicate "NOT NULL DEFAULT false"
        INTEGER primary_track_id FK
        TEXT duplicate_group_id
        TEXT album_artist
        INTEGER track_number "CHECK > 0"
        INTEGER total_tracks
        INTEGER disc_number "CHECK > 0"
        INTEGER total_discs
        INTEGER rating "CHECK 0-5"
        BOOLEAN compilation "DEFAULT false"
        TEXT release_date
        TEXT original_release_date
        INTEGER bpm
        TEXT media_type "Music/Audiobook/Podcast"
        INTEGER bitrate "CHECK > 0"
        INTEGER sample_rate
        INTEGER channels "1=mono, 2=stereo"
        TEXT codec
        INTEGER bit_depth
        TEXT sort_title
        TEXT sort_artist
        TEXT sort_album
        TEXT sort_album_artist
        TEXT extended_metadata "JSON"
    }

    playlists {
        TEXT id PK "UUID"
        TEXT name "NOT NULL"
        TEXT type "NOT NULL (regular/smart)"
        BOOLEAN is_user_editable "NOT NULL"
        BOOLEAN is_content_editable "NOT NULL"
        DATETIME date_created "NOT NULL"
        DATETIME date_modified "NOT NULL"
        BLOB cover_artwork_data
        TEXT smart_criteria "JSON"
        INTEGER sort_order "NOT NULL DEFAULT 0"
    }

    playlist_tracks {
        TEXT playlist_id FK "NOT NULL"
        INTEGER track_id FK "NOT NULL"
        INTEGER position "NOT NULL"
        DATETIME date_added "NOT NULL"
    }

    track_artists {
        INTEGER track_id FK "NOT NULL"
        INTEGER artist_id FK "NOT NULL"
        TEXT role "NOT NULL DEFAULT 'artist'"
        INTEGER position "NOT NULL DEFAULT 0"
    }

    track_genres {
        INTEGER track_id FK "NOT NULL"
        INTEGER genre_id FK "NOT NULL"
    }

    pinned_items {
        INTEGER id PK "AUTO_INCREMENT"
        TEXT item_type "NOT NULL (library/playlist)"
        TEXT filter_type "For library items"
        TEXT filter_value "Artist/album name"
        TEXT entity_id "UUID for entities"
        INTEGER artist_id "Database ID"
        INTEGER album_id "Database ID"
        TEXT playlist_id "For playlist items"
        TEXT display_name "NOT NULL"
        TEXT subtitle "For albums"
        TEXT icon_name "NOT NULL"
        INTEGER sort_order "NOT NULL DEFAULT 0"
        DATETIME date_added "NOT NULL"
    }

    tracks_fts {
        INTEGER track_id "NOT INDEXED"
        TEXT title
        TEXT artist
        TEXT album
        TEXT album_artist
        TEXT composer
        TEXT genre
        TEXT year
    }

    folders ||--o{ tracks : contains
    albums ||--o{ album_artists : "has artists"
    artists ||--o{ album_artists : "appears on"
    albums ||--o{ tracks : contains
    artists ||--o{ track_artists : "appears in"
    tracks ||--o{ track_artists : "has artists"
    tracks ||--o| tracks : "duplicate of"
    genres ||--o{ track_genres : "categorizes"
    tracks ||--o{ track_genres : "has genres"
    playlists ||--o{ playlist_tracks : contains
    tracks ||--o{ playlist_tracks : "appears in"
    tracks ||--|| tracks_fts : "searchable in"
```

</details>

### Development setup

- macOS 14 or later, with [Xcode](https://developer.apple.com/xcode/) installed.
- Clone the repository and open `Chaparii-Player.xcodeproj`.
- Build the `Chaparii-Player` (macOS) or `Chaparii-iOS` scheme — see
  [`CLAUDE.md`](CLAUDE.md) for exact `xcodebuild` commands.

## Credits

Chaparii is a fork of [**Petrichor**](https://github.com/kushalpandya/Petrichor) by
Kushal Pandya, and stands on these open-source projects:

- [SFBAudioEngine](https://github.com/sbooth/SFBAudioEngine)
- [GRDB.swift](https://github.com/groue/GRDB.swift/)
- [Sparkle](https://github.com/sparkle-project/Sparkle)
- [spotDL](https://github.com/spotDL/spotify-downloader) (macOS downloads)

## 📝 License

- Chaparii and Petrichor are licensed under [MIT](LICENSE).
- Core dependencies (SFBAudioEngine, GRDB, Sparkle) are licensed under MIT.
- Audio codec libraries (FLAC, Vorbis, Opus, etc.) are dynamically linked and use
  various open-source licenses including GPL and LGPL.

For complete third-party license information, see [ACKNOWLEDGEMENTS.md](ACKNOWLEDGEMENTS.md).
