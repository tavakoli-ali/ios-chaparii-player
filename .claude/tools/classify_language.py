#!/usr/bin/env python3
"""Re-file tracks into the correct language folder.

Detection layers (high precision — a naive detector mislabels romanized Persian
as Turkish/English, e.g. Googoosh/Hayedeh, so DO NOT trust lingua alone on Latin):
  1. Script: Cyrillic -> Russian; Arabic-script stuck in a Latin/generic folder
     -> Persian (never reshuffle within Persian/Arabic/Azari/Kurdish).
  2. Known artists / Persian classical (radif) terms  -> curated map (most reliable
     for romanized text).
  3. Latin via lingua: only move when a diacritic DISTINCTIVE to the detected
     language is present (Turkish ığşİ, French éèç, German äöüß, Azeri ə, Spanish ñ).
  Instrumental is frozen (genre, not a language).

Usage:
  python classify_language.py                 # dry-run, whole library
  python classify_language.py --only Unknown  # dry-run, one source folder
  python classify_language.py --apply [--only Unknown]
"""
import os, re, sys, json
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import (ROOT, LANGS, EXTS, GENERIC, FROZEN, ARAB_FAM, audio_under,
                 tags, tagtext, fold, script_counts, lang_of, md5)
from collections import defaultdict, Counter
from lingua import Language, LanguageDetectorBuilder

APPLY = "--apply" in sys.argv
ONLY = None
if "--only" in sys.argv: ONLY = sys.argv[sys.argv.index("--only")+1]
MANIFEST = os.path.join(os.path.dirname(os.path.abspath(__file__)), "move_manifest.json")

L2F = {Language.ENGLISH:"English",Language.FRENCH:"French",Language.GERMAN:"German",
       Language.ITALIAN:"Italian",Language.SPANISH:"Spanish",Language.TURKISH:"Turkish",
       Language.AZERBAIJANI:"Azari"}
LAT = LanguageDetectorBuilder.from_languages(*L2F.keys()).build()
DIA = {"Turkish":set("ığşİıĞŞ"),"Azari":set("əƏ"),"French":set("éèêàâçëïîôûùœæ"),
       "German":set("äöüßÄÖÜ"),"Spanish":set("ñ¿¡"),"Italian":set("àèìòùé")}
WORD = re.compile(r"[^\W\d_]{2,}", re.UNICODE)

# curated knowledge (extend as needed) — matched on folded word tokens / phrases
PERSIAN_TOK = set("""hayedeh viguen vigen nemati shahghasemi chavoshi afagh dadvar
 shabankhani lotfi sharif alizadeh alizade darvish talai neydavoud neydavud shahnaz
 shahnazi jangouk bigjekhani zarif marufi zarpanje majd pirniakan abdollah vaziri
 zarrinpanje lilehkoohi homayounfar kiarostami tafti ghorbani mokhberi hocheraghi
 chehrazi saghi hanoozam homayun homayoun mahur shur chahargah segah bayat esfahan
 afshari dashti abuata mashq radif dastgah norooz aroos arous baroun khazoun ghazaal
 faghiri shenidam bahare gozashte saaren miladi koorosh googoosh""".split())
INSTR_TOK = set("""yiruma zimmer djawadi paterlini lanz karaindrou alcocer allegri
 monolink ebina kashkashian reelaudio""".split())
INSTR_PH = ["hans zimmer","de maeyer","film music","string orche"]
FRENCH_PH = ["pierre perret","amelie-les-crayons","cardone"]
SPANISH_PH = ["hasta siempre","amor -"]
ENGLISH_PH = ["sting","chase & status","plot in you","blackmore","invadable harmony"]

def classify(pooled, cur):
    c = script_counts(pooled)
    if c["cyr"] >= 2 and c["cyr"] >= c["lat"]:
        return None if cur == "Russian" else "Russian"
    if c["arab"] >= 2:
        if cur in ARAB_FAM: return None
        return "Kurdish" if c["kurd"] >= 1 else "Persian"
    f = fold(pooled); toks = set(re.findall(r"[a-z0-9']+", f))
    if any(p in f for p in INSTR_PH) or (toks & INSTR_TOK):
        return None if cur == "Instrumental" else "Instrumental"
    if toks & PERSIAN_TOK: return None if cur == "Persian" else "Persian"
    if any(p in f for p in FRENCH_PH): return None if cur == "French" else "French"
    if any(p in f for p in SPANISH_PH): return None if cur == "Spanish" else "Spanish"
    if any(p in f for p in ENGLISH_PH): return None if cur == "English" else "English"
    # lingua on Latin, gated by distinctive diacritic
    if len(WORD.findall(pooled)) < 2 or c["lat"] < 6: return None
    vals = LAT.compute_language_confidence_values(pooled)
    if not vals: return None
    top = vals[0]; tgt = L2F.get(top.language)
    if not tgt or tgt == cur or tgt in FROZEN: return None
    if tgt == "English":
        return "English" if (cur in GENERIC and top.value >= 0.90) else None
    if (set(pooled) & DIA.get(tgt, set())) and top.value >= 0.35:
        return tgt
    return None

# build units: album subfolders detected together, loose files individually
units = defaultdict(list)
sources = [ONLY] if ONLY else [l for l in LANGS if l not in FROZEN]
for lang in sources:
    base = os.path.join(ROOT, lang)
    for dp, _, fs in os.walk(base):
        mp3s = [fn for fn in fs if fn.lower().endswith(EXTS)]
        if not mp3s: continue
        key = os.path.relpath(dp, ROOT)
        if dp == base:
            for fn in mp3s:
                r = os.path.relpath(os.path.join(dp, fn), ROOT); units[(lang, r)].append(r)
        else:
            for fn in mp3s:
                units[(lang, key)].append(os.path.relpath(os.path.join(dp, fn), ROOT))

plan = []
for (lang, key), rels in units.items():
    to = classify(" ".join(tagtext(r) for r in rels), lang)
    if to and to != lang:
        for r in rels: plan.append((r, lang, to))

print(f"{'APPLY' if APPLY else 'DRY-RUN'}  source={ONLY or 'ALL'}  moves={len(plan)}")
for (f, t), n in Counter((f, t) for _, f, t in plan).most_common():
    print(f"   {n:4d}  {f:12s} -> {t}")
for r, f, t in plan[:30]:
    print(f"     {f} -> {t}   {os.path.basename(r)}")

if APPLY:
    man = []
    for r, f, t in plan:
        parts = r.split("/"); parts[0] = t; newrel = "/".join(parts)
        src = os.path.join(ROOT, r); dst = os.path.join(ROOT, newrel)
        if not os.path.exists(src): continue
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if os.path.exists(dst):
            try:
                if os.path.getsize(src) == os.path.getsize(dst) and md5(src) == md5(dst):
                    os.remove(src); continue
            except OSError: pass
            stem, ext = os.path.splitext(newrel); newrel = f"{stem} (2){ext}"; dst = os.path.join(ROOT, newrel)
        os.rename(src, dst); man.append({"old": r, "new": newrel})
    json.dump(man, open(MANIFEST, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    for lang in LANGS:
        for dp, _, _ in os.walk(os.path.join(ROOT, lang), topdown=False):
            if dp != os.path.join(ROOT, lang):
                try:
                    if not os.listdir(dp): os.rmdir(dp)
                except OSError: pass
    print(f"APPLIED: moved {len(man)}; undo -> {MANIFEST}")
    print("Reminder: run update_playlists.py afterwards.")
