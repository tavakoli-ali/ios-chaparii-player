#!/usr/bin/env python3
"""Shared helpers for HiBy_R1_Music maintenance tools.

Run scripts with the local venv: .claude/tools/venv/bin/python <script>.py
(create it once with: bash .claude/tools/setup.sh)
"""
import os, re, unicodedata, hashlib
from collections import Counter

HERE = os.path.dirname(os.path.abspath(__file__))                 # <project>/.claude/tools
PROJECT = os.path.dirname(os.path.dirname(HERE))                  # <project> (petrichor-fork)
# The music library lives in a subfolder of the project. Override with MUSIC_ROOT.
ROOT = os.environ.get("MUSIC_ROOT") or os.path.join(PROJECT, "HiBy_R1_Music")
EXTS = (".mp3", ".flac", ".m4a", ".ogg", ".opus", ".wav")
LANGS = ["Arabic","Azari","English","French","German","Instrumental","Italian",
         "Kurdish","Other","Persian","Russian","Spanish","Turkish","Unknown"]
GENERIC = {"Unknown","Other"}
FROZEN = {"Instrumental"}          # genre category, never a language target
ARAB_FAM = {"Persian","Arabic","Azari","Kurdish"}   # share Arabic script

def audio_under(rel):
    base = os.path.join(ROOT, rel)
    out = []
    for dp, _, fs in os.walk(base):
        for fn in fs:
            if fn.lower().endswith(EXTS):
                out.append(os.path.relpath(os.path.join(dp, fn), ROOT))
    return out

def all_audio():
    out = []
    for lang in LANGS:
        out += audio_under(lang)
    for fn in os.listdir(ROOT):
        if fn.lower().endswith(EXTS):
            out.append(fn)
    return out

def tags(rel):
    from mutagen import File as MFile
    try:
        a = MFile(os.path.join(ROOT, rel), easy=True); t = a.tags or {}
        g = lambda k: (str(t.get(k)[0]) if t.get(k) else "")
        return {"title": g("title"), "artist": g("artist") or g("albumartist"),
                "albumartist": g("albumartist"), "album": g("album"),
                "tracknumber": g("tracknumber"), "discnumber": g("discnumber"),
                "duration": int(round(getattr(a.info, "length", 0) or 0))}
    except Exception:
        return {"title":"","artist":"","albumartist":"","album":"",
                "tracknumber":"","discnumber":"","duration":0}

def tagtext(rel):
    t = tags(rel)
    title = t["title"] or os.path.splitext(os.path.basename(rel))[0]
    return f"{title} {t['artist']} {t['album']}"

def md5(path, chunk=1 << 20):
    h = hashlib.md5()
    with open(path, "rb") as f:
        for b in iter(lambda: f.read(chunk), b""): h.update(b)
    return h.hexdigest()

def fold(s):
    s = unicodedata.normalize("NFKD", s)
    return "".join(c for c in s if not unicodedata.combining(c)).lower()

def script_counts(text):
    c = Counter()
    for ch in text:
        o = ord(ch)
        if 0x0400 <= o <= 0x04FF: c["cyr"] += 1
        elif (0x0600<=o<=0x06FF) or (0x0750<=o<=0x077F) or (0xFB50<=o<=0xFDFF) or (0xFE70<=o<=0xFEFF):
            c["arab"] += 1
            if ch in "ۆێڕڵ": c["kurd"] += 1
        elif ch.isalpha() and o < 0x250: c["lat"] += 1
    return c

def lang_of(rel):
    return rel.split("/", 1)[0]
