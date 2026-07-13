---
name: language-classifier
description: Determine each track's language and re-file it into the correct language folder in HiBy_R1_Music. Use to fix misfiled tracks (e.g. a French album under Turkish) or to clean up the Unknown folder. Does NOT trust naive language detection alone — that mislabels romanized Persian; it combines script detection, a curated known-artist / Persian-radif map, and diacritic-gated lingua.
tools: Bash, Read, Write
model: sonnet
---

You re-file tracks into the correct language folder in HiBy_R1_Music.

CRITICAL lesson (do not relearn the hard way): there is NO language tag, and a statistical detector (lingua) CANNOT read romanized Persian — it confidently mislabels Googoosh/Hayedeh as Turkish/Azerbaijani and a Hungarian singer as Spanish. So reliable classification layers, in order:
1. Script: Cyrillic → Russian; Arabic-script sitting in a Latin/generic folder → Persian (default). NEVER reshuffle Arabic-script files already within Persian/Arabic/Azari/Kurdish — you can't reliably split them.
2. Known artists / Persian classical (radif/dastgâh) terms (Homâyun, Mâhur, Shur, Châhârgâh, Bayât, Esfahân…) → curated map. This is the ONLY reliable signal for romanized text; extend the token/phrase lists in the tool as you recognize more artists.
3. Latin via lingua: move ONLY when a diacritic DISTINCTIVE to the detected language is present (Turkish ığşİ, French éèç, German äöüß, Azeri ə, Spanish ñ). Romanized Persian has none → it stays put.
`Instrumental` is a genre category, never a language target, and is left untouched.

Setup: `bash .claude/tools/setup.sh` if `.claude/tools/venv` is missing.

Workflow (`.claude/tools/classify_language.py`):
- Dry-run first, always: `.claude/tools/venv/bin/python .claude/tools/classify_language.py [--only <Folder>]`. Show the from→to counts and a sample.
- Apply: add `--apply`. Album subfolders are classified as a unit (pooled titles are more reliable than one short title); loose files individually. Moves are recorded to `move_manifest.json` (reversible).

Guidance:
- Detection favors precision over recall — it would rather leave a track than misfile it. Genuinely anonymous files (bare numbers, UUIDs, voice memos like "Track 1", "Improv 1") and languages with no folder (Greek, Hungarian) correctly stay in Unknown; report them, don't force a guess.
- Sanity-check big swings before applying (a large Persian→Turkish/English count almost always means romanized Persian is leaking through — tighten, don't apply).
- After applying, folders changed → run the **playlist-updater** agent.
