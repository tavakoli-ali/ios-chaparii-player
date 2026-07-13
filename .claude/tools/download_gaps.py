#!/usr/bin/env python3
"""Find incomplete albums (files present < total tracks in tags) and fill the
gaps with the bundled spotDL. Resumable via a queue JSON (status per album).

spotDL config ~/.spotdl/config.json has overwrite=skip, so re-runs only fetch
missing tracks. Invocation mirrors the Petrichor app's credential-free mode:
  spotdl download "<Artist> - <a track title>" --fetch-albums --ffmpeg <ffmpeg>
          --format mp3 --output "<album folder>/{artists} - {title}.{output-ext}"

Usage:
  python download_gaps.py --scan        # (re)build the queue of incomplete albums
  python download_gaps.py --download    # process queue (resumable); re-run to retry failures
  python download_gaps.py --status      # show progress
"""
import os, sys, json, subprocess, time, datetime
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from lib import ROOT, EXTS, LANGS, audio_under, tags
from collections import defaultdict, Counter

HERE = os.path.dirname(os.path.abspath(__file__))
QUEUE = os.path.join(HERE, "download_queue.json")
LOG = os.path.join(HERE, "download.log")
SPOTDL = "/Users/atavakoli/Projects/petrichor-fork/Resources/ThirdParty/spotdl"
FFMPEG = os.path.expanduser("~/.spotdl/ffmpeg")
PER_ALBUM_TIMEOUT = 900
MAX_ATTEMPTS = 2

def now(): return datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
def log(m):
    line = f"[{now()}] {m}"; print(line, flush=True)
    open(LOG, "a", encoding="utf-8").write(line + "\n")

def pair(s):
    s = s.strip()
    if "/" in s:
        a, b = s.split("/", 1)
        return (int(a) if a.isdigit() else None, int(b) if b.isdigit() else None)
    return (int(s) if s.isdigit() else None, None)

def scan():
    albums = defaultdict(lambda: {"files":0,"disc_totals":{},"folders":Counter(),
                                  "artist":"","album":"","sample":""})
    for lang in LANGS:
        for rel in audio_under(lang):
            t = tags(rel)
            if not t["album"]: continue
            key = ((t["albumartist"] or t["artist"]).lower(), t["album"].lower())
            d = albums[key]
            d["artist"] = t["albumartist"] or t["artist"]; d["album"] = t["album"]
            d["files"] += 1; d["folders"][os.path.dirname(os.path.join(ROOT, rel))] += 1
            if not d["sample"] and t["title"]: d["sample"] = t["title"]
            _, tt = pair(t["tracknumber"]); disc, _ = pair(t["discnumber"]); disc = disc or 1
            if tt: d["disc_totals"][disc] = max(d["disc_totals"].get(disc, 0), tt)
    q = []
    for d in albums.values():
        exp = sum(d["disc_totals"].values())
        if exp == 0 or d["files"] >= exp or not d["sample"]: continue
        ratio = d["files"] / exp
        if d["artist"].lower() in ("various artists","va","") or ratio < 0.5 or d["files"] < 3:
            continue   # skip singles-from-compilations
        q.append({"artist":d["artist"],"album":d["album"],
                  "query":f'{d["artist"]} - {d["sample"]}',
                  "folder":d["folders"].most_common(1)[0][0],
                  "present":d["files"],"expected":exp,"missing":exp-d["files"],
                  "status":"pending","attempts":0,"downloaded":0,"note":""})
    q.sort(key=lambda a: a["missing"], reverse=True)
    json.dump({"albums": q}, open(QUEUE, "w", encoding="utf-8"), ensure_ascii=False, indent=1)
    print(f"queued {len(q)} incomplete albums (~{sum(a['missing'] for a in q)} tracks) -> {QUEUE}")

def run_album(a):
    tpl = os.path.join(a["folder"], "{artists} - {title}.{output-ext}")
    cmd = [SPOTDL,"download",a["query"],"--fetch-albums","--ffmpeg",FFMPEG,
           "--format","mp3","--output",tpl]
    os.makedirs(a["folder"], exist_ok=True)
    dl = 0
    try:
        p = subprocess.Popen(cmd, stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True, bufsize=1)
    except Exception as e:
        return ("failed", 0, f"launch {e}")
    start = time.time()
    for line in p.stdout:
        line = line.rstrip()
        if not line: continue
        if line.startswith("Downloaded"): dl += 1
        log("    | " + line)
        if time.time() - start > PER_ALBUM_TIMEOUT:
            p.kill(); return ("failed", dl, "timeout")
    p.wait()
    return ("done" if p.returncode == 0 else "failed", dl, "" if p.returncode == 0 else f"exit {p.returncode}")

def download():
    data = json.load(open(QUEUE, encoding="utf-8")); albums = data["albums"]
    todo = [a for a in albums if a["status"] == "pending"
            or (a["status"] == "failed" and a["attempts"] < MAX_ATTEMPTS)]
    log(f"=== start === {len(todo)}/{len(albums)} to process")
    for a in todo:
        idx = albums.index(a)
        log(f"[{idx+1}/{len(albums)}] {a['artist']} - {a['album']} (need {a['missing']})")
        a["attempts"] += 1
        st, dl, note = run_album(a)
        a["status"] = st; a["downloaded"] = a.get("downloaded",0)+dl; a["note"] = note
        json.dump(data, open(QUEUE,"w",encoding="utf-8"), ensure_ascii=False, indent=1)
        log(f"    -> {st}; +{dl}" + (f"; {note}" if note else "")); time.sleep(2)
    status(); log("=== stop ===")

def status():
    if not os.path.exists(QUEUE): print("no queue; run --scan"); return
    a = json.load(open(QUEUE, encoding="utf-8"))["albums"]
    c = Counter(x["status"] for x in a); dl = sum(x.get("downloaded",0) for x in a)
    done = c.get("done",0)
    print(f"{done}/{len(a)} done ({done/max(len(a),1)*100:.1f}%) | "
          f"pending {c.get('pending',0)} | failed {c.get('failed',0)} | {dl} tracks")

if __name__ == "__main__":
    if "--scan" in sys.argv: scan()
    elif "--download" in sys.argv: download()
    else: status()
