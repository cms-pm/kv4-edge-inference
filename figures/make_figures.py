#!/usr/bin/env python3
"""Generate the kv4 paper figures (PDF) from the measured data.

Reproducible source for Fig. 1 (decode-vs-depth + VRAM-vs-context),
Fig. 2 (batch scaling), Fig. 3 (per-family accuracy w/ Wilson CIs).
Data mirrors the paper tables / docs/validation/kv4/evidence. Run:
    /tmp/pdfv/bin/python docs/papers/kv4/figures/make_figures.py
or `make -C docs/papers/build PAPER=kv4 figures`.
"""
import math
import os
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.ticker import FixedLocator

HERE = os.path.dirname(os.path.abspath(__file__))

# --- house style: Times-like serif (STIX), IEEE figure sizes -----------------
plt.rcParams.update({
    "font.family": "serif", "font.serif": ["STIXGeneral"],
    "mathtext.fontset": "stix",
    "font.size": 8, "axes.labelsize": 8, "axes.titlesize": 8,
    "xtick.labelsize": 7, "ytick.labelsize": 7, "legend.fontsize": 7,
    "axes.linewidth": 0.6, "lines.linewidth": 1.6, "lines.markersize": 4.2,
    "axes.spines.top": False, "axes.spines.right": False,
    "legend.frameon": False, "figure.dpi": 200,
})
# Consistent palette across ALL figures (cross-figure consistency, 40-figures-tikz)
F16, T4, T3, T2 = "#2c6fbb", "#d1495b", "#e6a817", "#4c9f70"
GREY = "#888888"


def wilson(k, n, z=1.96):
    p = k / n; d = 1 + z * z / n
    c = (p + z * z / (2 * n)) / d
    h = z * math.sqrt(p * (1 - p) / n + z * z / (4 * n * n)) / d
    return max(0, c - h), min(1, c + h)


def save(fig, name):
    fig.savefig(os.path.join(HERE, name), bbox_inches="tight", pad_inches=0.02)
    plt.close(fig)


# All figures are f16-vs-turbo4 GROUPED BAR charts (one consistent visual
# language, per the tikz visual-quality rules). W = bar half-offset.
W = 0.40


def grid(ax):
    ax.yaxis.grid(True, lw=0.3, color="#dddddd"); ax.set_axisbelow(True)


def vlabel(ax, xs, vals, fmt, dy):
    for xx, v in zip(xs, vals):
        if v is None or (isinstance(v, float) and math.isnan(v)):
            continue
        ax.text(xx, v + dy, fmt.format(v), ha="center", va="bottom", fontsize=5.8)


def oom_bar(ax, xx, top, label_y):
    # f16 unavailable here: crosshatched OUTLINE bar (no fill) in the f16 slot,
    # with a rotated "OOM" label. The legend lives OUTSIDE the axes (below), so
    # nothing overlaps these bars or the cap line.
    ax.bar([xx], [top], W, fill=False, edgecolor=F16, hatch="////", lw=0.8)
    ax.text(xx, label_y, "OOM", rotation=90, ha="center", va="center",
            fontsize=6.0, color=F16, fontweight="bold")


# === Fig 1: decode-vs-depth (a) + VRAM-vs-context (b), grouped bars ==========
# Legend placement matches Fig 2: a single shared legend centred BELOW the plot.
fig, (axL, axR) = plt.subplots(1, 2, figsize=(7.0, 2.8))
xc = [0, 1, 2]
xl = [i - W / 2 for i in xc]; xr = [i + W / 2 for i in xc]

# (a) decode tok/s vs depth (f16 OOMs at 32 K)
axL.bar(xl[:2], [75.40, 33.50], W, color=F16, label="f16")
axL.bar(xr, [73.05, 24.53, 8.14], W, color=T4, label="turbo4")
oom_bar(axL, xl[2], 84, 42)
vlabel(axL, xl[:2], [75.4, 33.5], "{:.1f}", 1.2)
vlabel(axL, xr, [73.0, 24.5, 8.1], "{:.1f}", 1.2)
grid(axL)
axL.set_xticks(xc); axL.set_xticklabels(["0", "8k", "32k"])
axL.set_ylim(0, 90); axL.set_xlabel("decode depth (KV entries)")
axL.set_ylabel("decode tok/s")
axL.set_title("(a) decode throughput vs depth", fontsize=8, pad=6)

# (b) peak VRAM vs context (f16 OOMs by 32 K; 4 GB cap)
axR.bar(xl[:1], [2426], W, color=F16, label="f16")
axR.bar(xr, [1750, 2464, 3416], W, color=T4, label="turbo4")
axR.axhline(4096, ls="--", lw=0.8, color=GREY)
axR.text(2.46, 4180, "4 GB cap", va="bottom", ha="right", fontsize=6.5, color=GREY)
oom_bar(axR, xl[1], 4096, 2050); oom_bar(axR, xl[2], 4096, 2050)
vlabel(axR, xl[:1], [2426], "{:.0f}", 70)
vlabel(axR, xr, [1750, 2464, 3416], "{:.0f}", 70)
grid(axR)
axR.set_xticks(xc); axR.set_xticklabels(["8k", "32k", "64k"])
axR.set_ylim(0, 4700); axR.set_xlabel("context length (KV entries)")
axR.set_ylabel("peak VRAM (MiB)")
axR.set_title("(b) peak VRAM vs context", fontsize=8, pad=6)

# single shared legend below both panels (same x,y placement as Fig 2)
h, l = axL.get_legend_handles_labels()
fig.legend(h, l, loc="upper center", bbox_to_anchor=(0.5, 0.06), ncol=2,
           handlelength=1.2, frameon=False)
fig.subplots_adjust(bottom=0.26, wspace=0.26)
save(fig, "fig_tradeoff.pdf")

# === Fig 2: per-family accuracy, grouped bars + Wilson 95% CIs ===============
fams = ["Qwen3-1.7B", "Llama-3.2-3B", "SmolLM2-1.7B", "MiniCPM5-1B"]
f16k = [8, 8, 8, 6]; t4k = [4, 7, 7, 6]; n = 8


def series(ks):
    pts = [k / n for k in ks]
    lo = [p - wilson(k, n)[0] for p, k in zip(pts, ks)]
    hi = [wilson(k, n)[1] - p for p, k in zip(pts, ks)]
    return pts, [lo, hi]


fig, ax = plt.subplots(figsize=(7.0, 2.6))
x = list(range(4))
p16, e16 = series(f16k); p4, e4 = series(t4k)
ax.bar([i - W / 2 for i in x], p16, W, yerr=e16, capsize=2.5,
       color=F16, label="f16", error_kw=dict(lw=0.8))
ax.bar([i + W / 2 for i in x], p4, W, yerr=e4, capsize=2.5,
       color=T4, label="turbo4", error_kw=dict(lw=0.8))
for i, k in zip(x, f16k):
    ax.text(i - W / 2, p16[i] + e16[1][i] + 0.025, f"{k}/8", ha="center",
            va="bottom", fontsize=6)
for i, k in zip(x, t4k):
    ax.text(i + W / 2, p4[i] + e4[1][i] + 0.025, f"{k}/8", ha="center",
            va="bottom", fontsize=6)
grid(ax)
ax.set_ylim(0, 1.2); ax.set_xticks(x); ax.set_xticklabels(fams)
ax.set_ylabel("extractive-QA accuracy")
ax.set_title("error bars: Wilson 95% CI ($n{=}8$) — only Qwen3-1.7B's drop is "
             "statistically resolved", fontsize=6.8)
# legend OUTSIDE, below the family labels — guaranteed clear of bars/CIs
ax.legend(loc="upper center", bbox_to_anchor=(0.5, -0.16), ncol=2,
          handlelength=1.2, framealpha=1.0, edgecolor="none")
save(fig, "fig_accuracy.pdf")

# === Fig 3: batch / concurrency scaling, grouped bars =======================
fig, ax = plt.subplots(figsize=(3.4, 2.6))
xc = [0, 1, 2, 3]
ax.bar([i - W / 2 for i in xc], [70.9, 117.9, 132.4, 157.0], W,
       color=F16, label="f16")
ax.bar([i + W / 2 for i in xc], [59.3, 98.7, 108.2, 123.4], W,
       color=T4, label="turbo4")
vlabel(ax, [i - W / 2 for i in xc], [70.9, 117.9, 132.4, 157.0], "{:.0f}", 2)
vlabel(ax, [i + W / 2 for i in xc], [59.3, 98.7, 108.2, 123.4], "{:.0f}", 2)
grid(ax)
ax.set_xticks(xc); ax.set_xticklabels(["1", "2", "4", "8"])
ax.set_ylim(0, 178); ax.set_xlabel("concurrent requests (np)")
ax.set_ylabel("aggregate tok/s")
ax.legend(loc="upper left", handlelength=1.2)
save(fig, "fig_batch.pdf")

print("wrote fig_tradeoff.pdf, fig_accuracy.pdf, fig_batch.pdf to", HERE)
