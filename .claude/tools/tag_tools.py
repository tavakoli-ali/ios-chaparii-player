#!/usr/bin/env python3
"""Inspect/repair audio tags and normalize filenames to "{artist} - {title}.ext".

Usage:
  python tag_tools.py --report                 # list files with missing tags / off-scheme names
  python tag_tools.py --rename [--apply]        # rename to "{artist} - {title}.ext" where both tags exist
  python tag_tools.py --set <relpath> title="..." artist="..." album="..."   # write specific tags
"""
import os, re, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ROOT, LANGS, audio_under, tags

def sanitize(s):
    return re.sub(r'[\\/:*?"<>|]', "_", s).strip()

def report():
    no_artist = no_title = offname = 0
    for lang in LANGS:
        for rel in audio_under(lang):
            t = tags(rel)
            if not t["artist"]: no_artist += 1
            if not t["title"]: no_title += 1
            if t["artist"] and t["title"]:
                want = f"{sanitize(t['artist'])} - {sanitize(t['title'])}"
                have = os.path.splitext(os.path.basename(rel))[0]
                if have != want:
                    offname += 1
                    if offname <= 40: print(f"  off-name: {rel}\n            -> {want}")
    print(f"\nmissing artist tag: {no_artist} | missing title tag: {no_title} | off-scheme names: {offname}")

def rename(apply):
    n = 0
    for lang in LANGS:
        for rel in audio_under(lang):
            t = tags(rel)
            if not (t["artist"] and t["title"]): continue
            d = os.path.dirname(rel); ext = os.path.splitext(rel)[1]
            want = f"{sanitize(t['artist'])} - {sanitize(t['title'])}{ext}"
            src = os.path.join(ROOT, rel); dst = os.path.join(ROOT, d, want)
            if os.path.abspath(src) == os.path.abspath(dst) or os.path.exists(dst): continue
            n += 1
            print(f"  {rel}\n    -> {os.path.join(d, want)}")
            if apply: os.rename(src, dst)
    print(f"\n{'renamed' if apply else 'would rename'} {n} files")
    if apply: print("Reminder: run update_playlists.py afterwards.")

def set_tags(relpath, kv):
    from mutagen import File as MFile
    p = os.path.join(ROOT, relpath)
    a = MFile(p, easy=True)
    for k, v in kv.items(): a[k] = v
    a.save()
    print("set", kv, "on", relpath)

if __name__ == "__main__":
    if "--report" in sys.argv: report()
    elif "--rename" in sys.argv: rename("--apply" in sys.argv)
    elif "--set" in sys.argv:
        rel = sys.argv[sys.argv.index("--set")+1]
        kv = dict(x.split("=", 1) for x in sys.argv if "=" in x and not x.startswith("--"))
        set_tags(rel, kv)
    else: report()
