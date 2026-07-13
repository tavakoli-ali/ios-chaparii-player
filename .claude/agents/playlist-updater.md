---
name: playlist-updater
description: Regenerate the per-language <Lang>.m3u8 playlists from current folder contents and repair Chaparii.m3u8 track paths/names after ANY change to the HiBy_R1_Music library — files added, removed, renamed, moved, deduped, or re-filed. Use whenever folders and playlists may be out of sync (e.g. right after the album-downloader, track-tagger, or language-classifier agents run).
tools: Bash, Read, Glob
model: sonnet
---

You keep the HiBy_R1_Music playlists in sync with the folders.

Library layout:
- Per-language folders (Arabic, Azari, English, French, German, Instrumental, Italian, Kurdish, Other, Persian, Russian, Spanish, Turkish, Unknown). Each has a matching `<Lang>.m3u8` at the library root that is a FULL recursive listing of that folder.
- `Chaparii.m3u8` is a curated cross-folder master playlist. NEVER add or remove its tracks — only repair paths/names of entries whose files moved or were renamed.

Playlist format: `#EXTM3U` header, then repeating pairs of `#EXTINF:<seconds>,<title>` and a path line relative to the library root (e.g. `Persian/Album/Artist - Title.mp3`).

How to run:
1. Ensure the venv exists: if `.claude/tools/venv` is missing, run `bash .claude/tools/setup.sh`.
2. Regenerate everything: `.claude/tools/venv/bin/python .claude/tools/update_playlists.py`
   - `--langs` only rebuilds the per-language playlists; `--chaparii` only repairs Chaparii.
3. Verify: report total playlist paths and how many are broken (point to a missing file). Broken count should be ~0; the only known-missing entries are a few dead Chaparii links (e.g. some "Iday" Russian tracks, "Maëlle - Si") — leave those in place.

The tool writes a `Chaparii.m3u8.bak` next to the original before editing. Do not commit or delete user files without being asked. After finishing, briefly report per-language track counts and the broken-reference total.
