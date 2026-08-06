#!/usr/bin/env python3
# One-line statusline: model/context + git + thinking indicator.
# Reads statusline stdin JSON. No npx/network.
# Field paths verified against a live 2.1.143 payload.
import sys, json, time, subprocess, os

try:
    d = json.load(sys.stdin)
    if not isinstance(d, dict):
        raise ValueError
except Exception:
    # A statusline must never crash; degrade silently.
    print("")
    sys.exit(0)

def c(code, s): return f"\033[{code}m{s}\033[0m"
CYAN, GREEN, ORANGE = "38;5;39", "38;5;42", "38;5;208"
GREY, DIM, YELLOW = "38;5;245", "38;5;240", "38;5;178"

PEN, EMPTY, THINK = "◈", "○", "◖"

model = d.get("model", {}).get("display_name", "?")
cw = d.get("context_window", {})
size = cw.get("context_window_size", 0)
ctx_label = f"{model} (1M context)" if size >= 1_000_000 else model
def as_pct(v):
    try:
        return int(round(float(v)))
    except (TypeError, ValueError):
        return 0

ctx_pct = as_pct(cw.get("used_percentage", 0))

cwd = d.get("workspace", {}).get("current_dir", "") or d.get("cwd", "")

# Git info is cached per session (5s TTL) so git subprocesses don't run on
# every render. session_id is stable per session and unique across sessions,
# so concurrent sessions in different repos don't share cached state.
def git(*a):
    try:
        return subprocess.run(["git", "-C", cwd, "--no-optional-locks", *a],
            capture_output=True, text=True, timeout=1).stdout.strip()
    except Exception:
        return ""

def compute_git():
    if not git("rev-parse", "--git-dir"):
        return "", "", ""
    top = git("rev-parse", "--show-toplevel")
    return (os.path.basename(top) if top else os.path.basename(cwd),
            git("rev-parse", "--abbrev-ref", "HEAD"),
            "*" if git("status", "--porcelain") else "")

sid = d.get("session_id", "default")
cache_file = os.path.join(
    os.environ.get("TMPDIR", "/tmp"), f"sl-git-{sid}")
repo = branch = dirty = ""
try:
    fresh = (os.path.exists(cache_file)
             and time.time() - os.path.getmtime(cache_file) < 5)
    if fresh:
        repo, branch, dirty = (open(cache_file).read().split("\t") + ["", "", ""])[:3]
    else:
        repo, branch, dirty = compute_git()
        with open(cache_file, "w") as f:
            f.write(f"{repo}\t{branch}\t{dirty}")
except Exception:
    repo, branch, dirty = compute_git()

if repo:
    git_seg = f"{c(GREEN, repo)} ({c(GREEN, branch)}{c(ORANGE, dirty)})"
else:
    git_seg = c(GREY, os.path.basename(cwd) or cwd)

thinking = d.get("thinking", {}).get("enabled", False)
effort = d.get("effort", {}).get("level", "")
ind = f"{c(GREY, THINK)} {c(GREY, effort or 'thinking')}" if thinking else c(DIM, f"{EMPTY} no-think")

sep = c(DIM, "│")
line1 = f"{c(CYAN, ctx_label)} {sep} {c(YELLOW, PEN)} {c(GREEN, str(ctx_pct)+'%')} {sep} {git_seg} {sep} {ind}"

# No rate-limit rows here: the desktop bar's model-usage widget already
# shows current/weekly quota, so the statusline stays one line.
print(line1)
