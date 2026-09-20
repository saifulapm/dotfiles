"""One agent's (or one provider's) slice of pxy's per-leg rows.

pxy records every upstream call it makes — which model answered, how long it
took to the first byte and to the end, what it billed, how much of the input
was a cache read, and how it ended — plus a row per served tool call. The
usage panel already shows what each agent SPENT; these are the numbers it
cannot get from an agent's own logs: latency, failures, cache share and what
the server tools cost.

Keys are the BARE model id, because that is how the usage scans bucket models
(an agent's own logs call it that). pxy keys its rows "provider/model", so two
providers serving the same id fold into one entry here: the counts add, and
the busier one's latency stands for both — medians cannot be averaged.

Used by the claude/codex/opencode/commandcode usage scans. Every failure path
returns {}: a panel that cannot reach pxy shows what it already had.
"""

import json
import os
import shutil
import subprocess


def _pxy():
    return shutil.which("pxy") or os.path.expanduser("~/.local/bin/pxy")


def _number(value):
    try:
        return int(value or 0)
    except (TypeError, ValueError):
        return 0


def agent_stats(agent=None, provider=None, since="today", timeout=15):
    """`pxy stats --json` for one slice, reshaped for the usage panel."""
    pxy = _pxy()
    if not os.path.exists(pxy):
        return {}
    cmd = [pxy, "stats", "--json", "--since", since]
    if agent:
        cmd += ["--agent", agent]
    if provider:
        cmd += ["--provider", provider]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        if out.returncode != 0:
            return {}
        data = json.loads(out.stdout)
    except Exception:
        return {}

    models = {}
    for row in data.get("models") or []:
        full = str(row.get("name") or "")
        leaf = full.split("/", 1)[1] if "/" in full else full
        if not leaf:
            continue
        legs = _number(row.get("legs"))
        entry = {
            "id": full,
            "legs": legs,
            "errors": _number(row.get("errors")),
            "inputTokens": _number(row.get("inputTokens")),
            "outputTokens": _number(row.get("outputTokens")),
            "cacheReadTokens": _number(row.get("cacheReadTokens")),
            "p50Ms": row.get("p50Ms"),
            "p95Ms": row.get("p95Ms"),
            "tokensPerSecond": row.get("tokensPerSecond"),
        }
        current = models.get(leaf)
        if current is None:
            models[leaf] = entry
            continue
        if legs > current["legs"]:
            current["p50Ms"] = entry["p50Ms"]
            current["p95Ms"] = entry["p95Ms"]
            current["tokensPerSecond"] = entry["tokensPerSecond"]
            current["id"] = entry["id"]
        for key in ("legs", "errors", "inputTokens", "outputTokens", "cacheReadTokens"):
            current[key] += entry[key]

    return {
        "since": since,
        "legs": _number(data.get("legs")),
        "errors": _number(data.get("errors")),
        "inputTokens": _number(data.get("inputTokens")),
        "outputTokens": _number(data.get("outputTokens")),
        "cacheReadTokens": _number(data.get("cacheReadTokens")),
        "p50Ms": data.get("p50Ms"),
        "p95Ms": data.get("p95Ms"),
        "models": models,
        "tools": data.get("tools") or [],
        "topErrors": (data.get("topErrors") or [])[:3],
    }
