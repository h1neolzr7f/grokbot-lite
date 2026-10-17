#!/usr/bin/env python3
"""Generate docs/memory.png from the MEASURED numbers in docs/benchmark.md.

Left:  RSS of grokbot-lite (daemon + supervisor) on two real hosts vs. the full
       Electron client started headless.
Right: whole-machine "used" memory on a 2 GiB Aliyun lightweight VPS before and
       after installing (free -m).
Re-run after updating the numbers:  python3 scripts/gen-chart.py
"""
import pathlib

import matplotlib

matplotlib.use("Agg")
import matplotlib.pyplot as plt  # noqa: E402

# --- measured (see docs/benchmark.md) -----------------------------------------
VPS = {"daemon": 122, "supervisor": 70}        # Aliyun lightweight, 2 vCPU / 2 GiB, Ubuntu 24.04.2
MINIPC = {"daemon": 120, "supervisor": 78}     # mini PC, 8 cores / 7.6 GB, Ubuntu 24.04.5
FULL_CLIENT = 740                              # full client started headless (mini PC), not logged in
VPS_TOTAL, VPS_USED_BEFORE, VPS_USED_AFTER = 1613, 480, 544

out = pathlib.Path(__file__).resolve().parent.parent / "docs" / "memory.png"
fig, (ax, ax2) = plt.subplots(1, 2, figsize=(12, 4.6), dpi=150, gridspec_kw={"width_ratios": [2.2, 1]})

rows = [("2 GiB cloud VPS\n(grokbot-lite)", VPS), ("8 GB mini PC\n(grokbot-lite)", MINIPC)]
for i, (label, d) in enumerate(rows):
    ax.barh(i, d["daemon"], color="#2f7ed8", label="local-exec daemon" if i == 0 else None)
    ax.barh(i, d["supervisor"], left=d["daemon"], color="#8bbc21", label="supervisor" if i == 0 else None)
    tot = d["daemon"] + d["supervisor"]
    ax.text(d["daemon"] / 2, i, str(d["daemon"]), va="center", ha="center", color="white", fontsize=9)
    ax.text(d["daemon"] + d["supervisor"] / 2, i, str(d["supervisor"]), va="center", ha="center", color="white", fontsize=9)
    ax.text(tot + 10, i, f"~{tot} MB", va="center", fontsize=11, fontweight="bold")
ax.barh(2, FULL_CLIENT, color="#c42525", label="full Electron client")
ax.text(FULL_CLIENT + 10, 2, f"~{FULL_CLIENT} MB", va="center", fontsize=11, fontweight="bold")
ax.set_yticks([0, 1, 2], [r[0] for r in rows] + ["full client\n(started headless)"])
ax.set_xlim(0, FULL_CLIENT * 1.2)
ax.invert_yaxis()
ax.set_xlabel("Resident memory (RSS, MB) - lower is better")
ax.set_title("Grok Bot remote-exec footprint (measured)", fontsize=12)
ax.grid(axis="x", alpha=0.3)
ax.legend(loc="upper left", bbox_to_anchor=(0.55, 0.98), fontsize=9, frameon=False)

ax2.bar(["before", "after"], [VPS_USED_BEFORE, VPS_USED_AFTER], color=["#999999", "#2f7ed8"])
ax2.axhline(VPS_TOTAL, color="#c42525", linestyle="--", linewidth=1)
ax2.text(-0.4, VPS_TOTAL - 90, f"total {VPS_TOTAL} MB", color="#c42525", fontsize=9)
for x, v in enumerate([VPS_USED_BEFORE, VPS_USED_AFTER]):
    ax2.text(x, v + 25, f"{v} MB", ha="center", fontsize=10, fontweight="bold")
ax2.set_ylim(0, VPS_TOTAL * 1.08)
ax2.set_ylabel("machine memory used (free -m)")
ax2.set_title("2 GiB VPS: whole machine", fontsize=12)
ax2.grid(axis="y", alpha=0.3)

fig.text(0.01, 0.01, "grok-bot 0.71.2 (Electron 42.1.0). Single spot measurements, 2026-10-18. "
         "VPS has 2 GB swap; 'used' excludes cache and swapped pages.", fontsize=7, color="#555555")
fig.tight_layout(rect=(0, 0.04, 1, 1))
fig.savefig(out)
print(out)
