#!/usr/bin/env python3
"""Regenerate per-language <Lang>.m3u8 from folder contents, and repair
Chaparii.m3u8 (fix moved/renamed track paths; never add or remove tracks).

Usage:
  python update_playlists.py            # both: regenerate langs + fix Chaparii
  python update_playlists.py --langs    # only regenerate per-language playlists
  python update_playlists.py --chaparii # only repair Chaparii.m3u8
"""
import os, re, sys, shutil
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ROOT, EXTS, LANGS, audio_under, tags, lang_of

def regen_langs():
    total = 0
    for lang in LANGS:
        rels = sorted(audio_under(lang), key=str.lower)
        lines = ["#EXTM3U"]
        for rel in rels:
            t = tags(rel)
            title = t["title"] or os.path.splitext(os.path.basename(rel))[0]
            lines.append(f"#EXTINF:{t['duration']},{title}")
            lines.append(rel)
        with open(os.path.join(ROOT, f"{lang}.m3u8"), "w", encoding="utf-8") as f:
            f.write("\n".join(lines) + "\n")
        total += len(rels)
        print(f"  {lang:12s} {len(rels):5d}")
    print(f"regenerated 14 playlists, {total} tracks")

def norm(s):
    s = os.path.splitext(s)[0].lower(); s = re.sub(r"\(\d+\)$", "", s)
    return re.sub(r"[^a-z0-9؀-ۿЀ-ӿ]", "", s)

def fix_chaparii():
    chap = os.path.join(ROOT, "Chaparii.m3u8")
    if not os.path.exists(chap):
        print("no Chaparii.m3u8"); return
    from collections import defaultdict
    idx = defaultdict(list)
    for lang in LANGS:
        for rel in audio_under(lang):
            idx[norm(os.path.basename(rel))].append(rel)
    lines = [l.rstrip("\n") for l in open(chap, encoding="utf-8")]
    shutil.copy2(chap, chap + ".bak")
    ok = fixed = unresolved = 0; out = []; i = 0; unres = []
    while i < len(lines):
        line = lines[i]
        if line.startswith("#EXTINF") and i+1 < len(lines) and lines[i+1] and not lines[i+1].startswith("#"):
            path = lines[i+1]; target = None
            if os.path.exists(os.path.join(ROOT, path)):
                target = path; ok += 1
            else:
                cand = idx.get(norm(os.path.basename(path)), [])
                if cand:
                    pref = [c for c in cand if lang_of(c) == lang_of(path)]
                    target = (pref or cand)[0]; fixed += 1
            if target:
                t = tags(target)
                title = t["title"] or os.path.splitext(os.path.basename(target))[0]
                out.append(f"#EXTINF:{t['duration']},{title}"); out.append(target)
            else:
                out.append(line); out.append(path); unresolved += 1; unres.append(path)
            i += 2; continue
        out.append(line); i += 1
    open(chap, "w", encoding="utf-8").write("\n".join(out) + "\n")
    print(f"Chaparii: ok={ok} fixed={fixed} unresolved={unresolved}")
    for p in unres[:20]: print("   unresolved:", p)

if __name__ == "__main__":
    do_l = "--chaparii" not in sys.argv
    do_c = "--langs" not in sys.argv
    if do_l: regen_langs()
    if do_c: fix_chaparii()
