#!/usr/bin/env python3
# One-line statusline: model │ ◈ ctx% │ repo (branch*) │ thinking │ cache │ limits.
# Reads statusline stdin JSON; git runs with --no-optional-locks and the
# line renders at most every refreshInterval, so no caching is needed.
import sys, json, os, subprocess

try:
    d = json.load(sys.stdin)
    assert isinstance(d, dict)
except Exception:
    # A statusline must never crash; degrade silently.
    print("")
    sys.exit(0)

def c(code, s): return f"\033[{code}m{s}\033[0m"
CYAN, GREEN, ORANGE = "38;5;39", "38;5;42", "38;5;208"
GREY, DIM, YELLOW = "38;5;245", "38;5;240", "38;5;178"

def git(*a):
    try:
        return subprocess.run(["git", "-C", cwd, "--no-optional-locks", *a],
            capture_output=True, text=True, timeout=1).stdout.strip()
    except Exception:
        return ""

model = d.get("model", {}).get("display_name", "?")
cw = d.get("context_window", {})
try:
    pct = f"{round(float(cw.get('used_percentage', 0)))}%"
except (TypeError, ValueError):
    pct = "0%"

cwd = d.get("workspace", {}).get("current_dir", "") or d.get("cwd", "")
if git("rev-parse", "--git-dir"):
    repo = os.path.basename(git("rev-parse", "--show-toplevel") or cwd)
    branch = git("rev-parse", "--abbrev-ref", "HEAD")
    dirty = "*" if git("status", "--porcelain") else ""
    where = f"{c(GREEN, repo)} ({c(GREEN, branch)}{c(ORANGE, dirty)})"
else:
    where = c(GREY, os.path.basename(cwd) or cwd)

if d.get("thinking", {}).get("enabled", False):
    think = c(GREY, "◖ " + (d.get("effort", {}).get("level") or "thinking"))
else:
    think = c(DIM, "○ no-think")

# Quiet while fine, coloured when the cache goes cold or a Max limit passes
# 80%. Both blocks are absent until the session's first API response.
def num(v):
    try:
        return float(v)
    except (TypeError, ValueError):
        return None

extra = []
pc = d.get("prompt_cache")
if isinstance(pc, dict):
    hr = num(pc.get("hit_ratio"))
    if pc.get("warm") is False:
        extra.append(c(ORANGE, "cache cold"))
    elif hr is not None:
        extra.append(c(DIM if hr >= 0.9 else YELLOW, f"cache {int(hr * 100)}%"))

limits = []
for key, label in (("five_hour", "5h"), ("seven_day", "7d")):
    used = num((d.get("rate_limits") or {}).get(key, {}).get("used_percentage"))
    if used is not None:
        limits.append(c(ORANGE if used >= 80 else DIM, f"{label} {round(used)}%"))
if limits:
    extra.append(c(DIM, " · ").join(limits))

sep = c(DIM, "│")
line = f"{c(CYAN, model)} {sep} {c(YELLOW, '◈')} {c(GREEN, pct)} {sep} {where} {sep} {think}"
print(" ".join([line, *(f"{sep} {e}" for e in extra)]))
