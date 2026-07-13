#!/usr/bin/env python3
"""Find duplicate audio files (size bucket -> md5). Report by default; --apply
removes redundant copies (content-preserving: always keeps one). Keeps the copy
in the most specific language folder. Writes an undo manifest.

Usage:
  python dedup.py            # report only
  python dedup.py --apply    # remove redundant copies (keeps 1 per group)
"""
import os, re, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ROOT, all_audio, md5, lang_of, GENERIC
from collections import defaultdict, Counter

APPLY = "--apply" in sys.argv
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "dedup_manifest.json")
PRIO = {l: i for i, l in enumerate(
    ["Unknown","Other","Instrumental","English","Spanish","German","French",
     "Italian","Turkish","Azari","Kurdish","Arabic","Persian","Russian"])}
PAREN = re.compile(r"\s*\(\d+\)(?=\.[^.]+$)")

def groups():
    by_size = defaultdict(list)
    for rel in all_audio():
        try: by_size[os.path.getsize(os.path.join(ROOT, rel))].append(rel)
        except OSError: pass
    out = []
    for _, g in by_size.items():
        if len(g) < 2: continue
        by_hash = defaultdict(list)
        for rel in g: by_hash[md5(os.path.join(ROOT, rel))].append(rel)
        out += [sorted(v) for v in by_hash.values() if len(v) > 1]
    return out

def keeper(group):
    # same-folder (N) copy: keep the one without the (N) suffix
    if len({os.path.dirname(r) for r in group}) == 1:
        base = [r for r in group if not PAREN.search(os.path.basename(r))]
        if base: return base[0]
    specific = [r for r in group if lang_of(r) not in GENERIC and lang_of(r) != "Instrumental"]
    pool = specific or group
    return max(pool, key=lambda r: PRIO.get(lang_of(r), -1))

g = groups()
redundant = sum(len(x) - 1 for x in g)
print(f"{len(all_audio())} audio files; {len(g)} duplicate groups; {redundant} redundant copies")
cross = sum(1 for x in g if len({lang_of(r) for r in x}) > 1)
print(f"  cross-language groups: {cross}  within-folder/other: {len(g)-cross}")
for x in g[:25]:
    print("  DUP:", " | ".join(x))
if len(g) > 25: print(f"  ... and {len(g)-25} more groups")

if APPLY:
    man = []; removed = 0
    for x in g:
        keep = keeper(x); kp = os.path.join(ROOT, keep)
        if not os.path.exists(kp): continue
        ks = os.path.getsize(kp)
        for r in x:
            if r == keep: continue
            rp = os.path.join(ROOT, r)
            if not os.path.exists(rp) or os.path.getsize(rp) != ks: continue
            man.append({"removed": r, "identical_to": keep}); os.remove(rp); removed += 1
    json.dump(man, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    # prune empty dirs
    from lib import LANGS
    for lang in LANGS:
        for dp, _, _ in os.walk(os.path.join(ROOT, lang), topdown=False):
            if dp != os.path.join(ROOT, lang):
                try:
                    if not os.listdir(dp): os.rmdir(dp)
                except OSError: pass
    print(f"APPLIED: removed {removed}; undo manifest -> {MANIFEST}")
    print("Reminder: run update_playlists.py afterwards.")
