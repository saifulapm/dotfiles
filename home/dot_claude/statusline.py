#!/usr/bin/env python3
# One-line statusline: model/context │ ◈ ctx% │ repo (branch*) │ thinking.
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
if cw.get("context_window_size", 0) >= 1_000_000:
    model += " (1M context)"
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

sep = c(DIM, "│")
print(f"{c(CYAN, model)} {sep} {c(YELLOW, '◈')} {c(GREEN, pct)} {sep} {where} {sep} {think}")
