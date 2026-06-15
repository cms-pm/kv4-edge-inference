#!/usr/bin/env python3
"""Reproduce the paper's headline numbers from the shipped data/ — no GPU needed.

Parses llama-bench JSONL (decode/prefill tok/s) + VRAM peaks and prints the
tables behind Fig. 1 and the calibration. Stdlib only.

    python3 analysis/analyze.py            # uses ./data
    python3 analysis/analyze.py path/to/data
"""
import json, math, os, sys, glob

DATA = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(__file__), "..", "data")


def rows(path):
    """Yield llama-bench JSONL records (file may be one JSON array or JSONL)."""
    try:
        txt = open(path).read().strip()
    except OSError:
        return
    if not txt:
        return
    try:
        d = json.loads(txt)
        for r in (d if isinstance(d, list) else [d]):
            yield r
        return
    except json.JSONDecodeError:
        for line in txt.splitlines():
            line = line.strip()
            if line:
                yield json.loads(line)


def kind(r):
    return "pp" if r.get("n_prompt") and not r.get("n_gen") else "tg"


def wilson(k, n, z=1.96):
    if not n:
        return (0.0, 0.0)
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return (round(max(0, c - h), 2), round(min(1, c + h), 2))


print("=" * 64, "\nDECODE / PREFILL throughput (from data/bench, data/.../bench)\n" + "=" * 64)
print(f"{'cell':44} {'type':4} {'depth':>6} {'avg_ts':>9} {'reps':>4}")
for f in sorted(set(glob.glob(os.path.join(DATA, "**", "bench", "*.jsonl"), recursive=True)) |
                set(glob.glob(os.path.join(DATA, "bench", "*.jsonl")))):
    for r in rows(f):
        if r.get("n_gen") == 0 and not r.get("n_prompt"):
            continue
        reps = len(r.get("samples_ts") or []) or r.get("reps") or "?"
        print(f"{os.path.basename(f).replace('.jsonl',''):44} {kind(r):4} "
              f"{r.get('n_depth',0):>6} {r.get('avg_ts',float('nan')):>9.2f} {reps:>4}")

peaks = os.path.join(DATA, "vram", "peaks.txt")
if os.path.exists(peaks):
    print("\n" + "=" * 64, "\nPEAK VRAM (MiB) vs context (from data/vram/peaks.txt)\n" + "=" * 64)
    print(open(peaks).read().rstrip())

print("\n" + "=" * 64, "\nWilson 95% CI helper (for the n=8 RAG accuracy probe)\n" + "=" * 64)
for label, k in [("8/8", 8), ("7/8", 7), ("6/8", 6), ("4/8", 4), ("3/8", 3)]:
    lo, hi = wilson(k, 8)
    print(f"  {label}:  [{lo:.2f}, {hi:.2f}]")
print("\nPer-model RAG accuracy: see data/V3-GENERALITY.md and data/rag-real*/.")
