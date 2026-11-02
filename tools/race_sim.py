#!/usr/bin/env python3
"""Finds the steady power it takes to win each race: runs tools/race_sim.gd for every combination of race,
difficulty, wattage and seed, in parallel, and prints the lowest wattage that won every run.

  python3 tools/race_sim.py --ftp 200 --weight-lb 175 --bike 3 --difficulty easy --watts 100:160:5 --seeds 1,2,3
  python3 tools/race_sim.py --races 3 --difficulty hard,ludicrous --watts 150:230:10 --jobs 16 --out crit.txt
  python3 tools/race_sim.py --summarize crit.txt more.txt      # just the table, from earlier runs

Races: 0 Foothill Gravel Grind, 1 Summit Gravel Showdown, 2 Flour Run, 3 Crusty Crit, 4 the Velodoughm; add the
champion's versions (Maillot Max) of 0-2 with --champion. Each run prints one line (appended to --out as it goes, so
a long sweep can be stopped and summarized). A crit takes a few minutes of CPU per run, the road races one to five.
"""
import argparse
import collections
import json
import os
import subprocess
import sys
from concurrent.futures import ThreadPoolExecutor

REPO = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
NAMES = {0: "Foothill Gravel Grind", 1: "Summit Gravel Showdown", 2: "Flour Run", 3: "Crusty Crit", 4: "The Velodoughm"}
DIFFS = ["easy", "medium", "hard", "ludicrous"]


def run(cfg, opts):
    course, champ, watts, seed, diff = cfg
    env = dict(os.environ, PIZZA_NO_SAVE="1", SIM_COURSE=str(course), SIM_CHAMP="1" if champ else "0",
               SIM_WATTS=str(watts), SIM_SEED=str(seed), SIM_DIFF=diff, SIM_FTP=str(opts.ftp),
               SIM_WEIGHT_KG=str(opts.weight_kg), SIM_BIKE=str(opts.bike))
    try:
        out = subprocess.run([opts.godot, "--headless", "--fixed-fps", "10", "--path", REPO, "-s", "tools/race_sim.gd"],
                             env=env, capture_output=True, text=True, timeout=opts.timeout).stdout
    except subprocess.TimeoutExpired:
        return cfg, "TIMEOUT"
    lines = [l for l in out.splitlines() if l.startswith("RESULT")]
    return cfg, lines[0] if lines else "NO RESULT"


def summarize(paths):
    """The lowest wattage from which every run won, per (difficulty, race), with every run listed (W won, l lost)."""
    res = collections.defaultdict(lambda: collections.defaultdict(list))
    for p in paths:
        for line in open(p):
            if "RESULT" not in line:
                continue
            cfg = json.loads(line[:line.index("]") + 1])
            course, champ, watts = cfg[:3]
            diff = cfg[4] if len(cfg) > 4 else "easy"   # (the first sweeps were all on Easy and didn't say)
            res[(diff, champ, course)][watts].append("place=1 " in line)
    for key in sorted(res, key=lambda k: (DIFFS.index(k[0]), k[1], k[2])):
        diff, champ, course = key
        runs = res[key]
        sure = [w for w in sorted(runs) if all(all(runs[v]) for v in runs if v >= w)]
        name = NAMES.get(course, str(course)) + (" vs Max" if champ else "")
        cells = "  ".join(f"{w}:{''.join('W' if x else 'l' for x in runs[w])}" for w in sorted(runs))
        print(f"{diff:9s} {name:32s} always wins from {str(sure[0]) + ' W' if sure else '?':>7} | {cells}")


def span(text):
    """"100:160:5" -> 100, 105 ... 160; "120,125" -> those."""
    if ":" in text:
        a, b, step = (float(x) for x in text.split(":"))
        out, w = [], a
        while w <= b + 1e-9:
            out.append(int(w) if w == int(w) else w)
            w += step
        return out
    return [float(x) if "." in x else int(x) for x in text.split(",")]


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--ftp", type=float, default=200.0)
    weight = ap.add_mutually_exclusive_group()
    weight.add_argument("--weight-kg", type=float, default=75.0)
    weight.add_argument("--weight-lb", type=float)
    ap.add_argument("--bike", type=int, default=3, help="index into Game.bikes (default 3, the Carbon Crit Machine)")
    ap.add_argument("--difficulty", default="medium", help="comma-separated: " + ", ".join(DIFFS))
    ap.add_argument("--races", default="0,1,2,3,4", help="comma-separated race numbers (see above)")
    ap.add_argument("--champion", action="store_true", help="also the champion's versions of races 0-2")
    ap.add_argument("--watts", default="100:300:20", help="from:to:step, or a comma-separated list")
    ap.add_argument("--seeds", default="1", help="comma-separated")
    ap.add_argument("--jobs", type=int, default=max(1, (os.cpu_count() or 2) - 2))
    ap.add_argument("--out", default="race_sim.txt", help="file the results are appended to")
    ap.add_argument("--godot", default="godot")
    ap.add_argument("--timeout", type=int, default=1800, help="seconds before a run is given up on")
    ap.add_argument("--summarize", nargs="+", metavar="FILE", help="only print the table from earlier results")
    opts = ap.parse_args()
    if opts.summarize:
        summarize(opts.summarize)
        return
    if opts.weight_lb:
        opts.weight_kg = opts.weight_lb / 2.20462
    diffs = opts.difficulty.split(",")
    if any(d not in DIFFS for d in diffs):
        sys.exit("--difficulty takes " + ", ".join(DIFFS))
    races = [int(r) for r in opts.races.split(",")]
    cfgs = [(r, False, w, s, d) for d in diffs for r in races for w in span(opts.watts) for s in span(opts.seeds)]
    if opts.champion:
        cfgs += [(r, True, w, s, d) for d in diffs for r in races if r <= 2 for w in span(opts.watts) for s in span(opts.seeds)]
    print(f"{len(cfgs)} runs, {opts.jobs} at a time: FTP {opts.ftp:g} W, {opts.weight_kg:.1f} kg, bike {opts.bike}", flush=True)
    with open(opts.out, "a") as f, ThreadPoolExecutor(opts.jobs) as ex:
        for done, (cfg, res) in enumerate(ex.map(lambda c: run(c, opts), cfgs), 1):
            f.write(json.dumps(list(cfg)) + " " + res + "\n")
            f.flush()
            print(f"[{done}/{len(cfgs)}] {list(cfg)} {res}", flush=True)
    print()
    summarize([opts.out])


if __name__ == "__main__":
    main()
