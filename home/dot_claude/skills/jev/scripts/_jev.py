"""Shared plumbing for `jev` and `browse`: surfaces in, typed questions out.

Nothing here decides anything. It reads a surface as text, trims it to what
the gateway will accept, and shells out to `pxy ask`, which owns the
thresholds and the exit codes.
"""

import json
import re
import shutil
import subprocess
import sys

# Jev caps a choice at 255 options and `pxy ask pick` spends one of them on
# `none_of_these`, so 254 is what a caller may fill.
MAX_OPTIONS = 254
# Typesafe documents 64k tokens for the state and questions together, but the
# gateway pxy reaches answers `max_tokens_exceeded` above ~32,768 (measured
# 2026-09-22: 125,000 chars of page text went through as 32,539 tokens,
# 129,643 did not). Accessibility markup is the densest thing sent here at
# 2.29 chars/token, so this stays under that ceiling even at its worst.
MAX_STATE = 70_000

# Roles worth offering as a target, and the one operation each naturally
# takes. A page snapshot is mostly generics and containers, and every one of
# them on the list is one more way to be wrong.
ROLE_OPS = {
    "button": "click",
    "link": "click",
    "menuitem": "click",
    "tab": "click",
    "option": "click",
    "checkbox": "click",
    "radio": "click",
    "switch": "click",
    "textbox": "type",
    "searchbox": "type",
    "combobox": "select",
}
PAGE_REF = re.compile(
    rf"^\s*-\s+({'|'.join(ROLE_OPS)})\b(.*?)\[ref=([A-Za-z0-9]+)\]"
)

SGR = re.compile(r"\x1b\[([0-9;]*)m")
ANSI = re.compile(r"\x1b\[[0-9;?]*[A-Za-z]")

PANE_LEGEND = (
    "A terminal pane follows. Text between » and « is what the terminal is "
    "highlighting — the current selection. If no » appears anywhere, nothing "
    "is selected.\n\n"
)

PAGE_WHERE = "JSON.stringify({url: location.href, title: document.title})"


def die(msg):
    print(f"jev: {msg}", file=sys.stderr)
    sys.exit(1)


def run(cmd):
    """Run a command, returning stdout; die with its stderr if it fails.

    The encoding is pinned: these surfaces are full of the punctuation that
    comes back as mojibake when the locale decides it is latin-1.
    """
    p = subprocess.run(cmd, capture_output=True, text=True, encoding="utf-8")
    if p.returncode != 0:
        die(f"{cmd[0]} failed: {(p.stderr or p.stdout).strip()}")
    return p.stdout


def need_pxy():
    if not shutil.which("pxy"):
        die("pxy is not on PATH — the systemone chain lives there")


def trim(state):
    if len(state) <= MAX_STATE:
        return state
    # The head is kept, so anything below the fold is not being judged.
    print(
        f"jev: state trimmed to the first {MAX_STATE:,} of {len(state):,} chars "
        "(the gateway's token ceiling) — the answer does not account for the rest",
        file=sys.stderr,
    )
    return state[:MAX_STATE]


def ask_many(state, questions):
    """Several questions about one state, in one call.

    Jev answers every question in a request in parallel, so the questions are
    nearly free and the round trip is not: asking three separately would cost
    three times the latency and tell us the same thing.
    """
    need_pxy()
    body = {"model": "auto", "state": trim(state), "questions": questions}
    p = subprocess.run(
        ["pxy", "ask", "raw"], input=json.dumps(body), capture_output=True, text=True
    )
    if p.returncode != 0:
        die(f"pxy ask raw failed: {(p.stderr or p.stdout).strip()}")
    return json.loads(p.stdout)


def cap(criteria, grep=None):
    """Narrow the candidate set to something Jev will accept.

    Over the cap this refuses rather than keeping the first 254. Dropping
    candidates silently is the one failure `none_of_these` cannot catch: a
    target Jev was never shown cannot be reported missing, so the answer comes
    back confident and wrong.
    """
    if grep:
        pattern = re.compile(grep, re.I)
        criteria = {k: v for k, v in criteria.items() if pattern.search(v)}
        if not criteria:
            die(f"no candidate matched --grep {grep!r} — widen it, or drop it")
    if not criteria:
        die("no interactive candidates on this surface")

    # Two candidates with the same role and label are the same choice as far
    # as anyone asking can tell, and offering both only splits the vote
    # between them: playwright.dev lists `locator.fill()` twice, which put
    # 0.17 and 0.11 on the right answer and handed the escape option 0.68.
    seen, deduped = {}, {}
    for ref, what in criteria.items():
        if what in seen:
            continue
        seen[what] = ref
        deduped[ref] = what
    if len(deduped) < len(criteria):
        print(
            f"jev: {len(criteria) - len(deduped)} duplicate labels folded into "
            "the first of each",
            file=sys.stderr,
        )
    criteria = deduped
    if len(criteria) > MAX_OPTIONS:
        die(
            f"{len(criteria)} candidates, and Jev takes {MAX_OPTIONS} — narrow them "
            "with --grep (it matches the role and label, case-insensitively), or "
            "use `playwright-cli find` to locate the target directly"
        )
    return criteria


# ---------------------------------------------------------------- playwright


def page(session, *args, expect=False):
    """One playwright-cli call. `expect` when the output is the point.

    An action (click, fill, press) is silent under --raw by design, so only a
    read can treat empty output as a broken session.
    """
    cmd = ["playwright-cli"]
    if session:
        cmd.append(f"--s={session}")
    out = run(cmd + ["--raw", *args])
    if expect and not out.strip():
        die(f"`playwright-cli {args[0]}` returned nothing — is a session open?")
    return out


def page_elements(session):
    """Interactive elements, as {ref: (role, label)}.

    The element table is the state as well as the options: a real page's
    snapshot runs past a megabyte (Wikipedia: 1.18 MB, 3,621 refs), so sending
    the whole tree would blow the token budget on markup nobody asked about.
    """
    found = {}
    for line in page(session, "snapshot", expect=True).splitlines():
        m = PAGE_REF.match(line)
        if not m:
            continue
        # The snapshot already quotes a label; keeping its quotes would nest
        # them inside ours everywhere the label is shown.
        label = m.group(2).strip().strip(":").strip().strip('"') or "(no label)"
        found[m.group(3)] = (m.group(1), label[:100])
    return found


def describe(elements):
    return {ref: f"{role} {label}"[:120] for ref, (role, label) in elements.items()}


def page_text(session):
    """What the page says, which is what a claim about it is usually about.

    Five times smaller than the accessibility tree and better prose, so more
    of the page survives the token budget. The cost is that control state
    (disabled, checked, focused) is not in it — assert those over `jev pick
    --json` or by reading the snapshot.
    """
    return page(session, "eval", "document.body.innerText", expect=True)


# ---------------------------------------------------------------------- tmux


def pane_text(session):
    """A pane as text, with the highlighted run marked.

    `capture-pane -p` strips colour, so the selection becomes invisible and a
    question about it cannot be answered at all. `-e` keeps it, but as escape
    codes. Turning reverse-video into a marker is deterministic, so it happens
    here rather than being left for the model to infer.
    """
    p = subprocess.run(
        ["tmux", "capture-pane", "-p", "-e", "-t", session],
        capture_output=True,
        text=True,
    )
    if p.returncode != 0:
        die(f"no such tmux pane {session!r}: {p.stderr.strip()}")

    lines = []
    for line in p.stdout.splitlines():
        buf, lit, pos = [], False, 0
        state = {"reverse": False, "bg": False}
        for m in SGR.finditer(line):
            buf.append(line[pos : m.start()])
            apply_sgr(state, m.group(1))
            now = state["reverse"] or state["bg"]
            if now != lit:
                buf.append("»" if now else "«")
                lit = now
            pos = m.end()
        buf.append(line[pos:])
        if lit:
            buf.append("«")
        # A close followed straight by an open has no unmarked character
        # between them: one run that the terminal happened to restate, not
        # two. fzf restates it between the gutter glyph and the label.
        lines.append(ANSI.sub("", "".join(buf)).replace("«»", ""))
    return "\n".join(lines)


def apply_sgr(state, params):
    """Fold one SGR sequence into the highlight state.

    A terminal marks the selected row either by reversing it or by giving it
    a background, and which one is not a detail a caller can be asked to know
    — fzf uses bold plus `48;5;236` and never reverse video, so watching for
    reverse alone saw no selection at all on it. Foreground colour is ignored:
    it is how TUIs colour ordinary text.

    The extended-colour forms carry their own parameters (`38;5;N`,
    `48;2;R;G;B`), so they have to be consumed rather than read one number at
    a time, or the `5` in `48;5;236` reads as blink and the `48` never
    reaches the background.
    """
    codes = [c for c in params.split(";") if c] or ["0"]
    i = 0
    while i < len(codes):
        code = codes[i]
        if code in ("38", "48"):
            extended = codes[i + 1] if i + 1 < len(codes) else ""
            width = {"5": 3, "2": 5}.get(extended, 1)
            if code == "48":
                state["bg"] = True
            i += width
            continue
        if code == "0":
            state["reverse"] = state["bg"] = False
        elif code == "7":
            state["reverse"] = True
        elif code == "27":
            state["reverse"] = False
        elif code == "49":
            state["bg"] = False
        elif code.isdigit() and (40 <= int(code) <= 47 or 100 <= int(code) <= 107):
            state["bg"] = True
        i += 1
