"""mail_engine: reads the notmuch mail store for kak-mail and bin/mail.

Its functions return data and raise MailError; none prints, exits, or marks
mail read as a side effect of reading. The box list lives here only.
"""

import json
import os
import re
import subprocess

HOME = os.path.expanduser("~")
# The shell's margin watches this file for the Imbox unread count.
COUNT_FILE = os.path.join(os.environ.get("XDG_STATE_HOME", HOME + "/.local/state"), "dots", "mail-unread")

# The HEY boxes in HEY's order as (key, name, query, unthreaded); the queries use the post-new hook's tags, and tests/home/mail-engine.test.mjs pins them to the hook's and hey-folder-sync's.
BOXES = [
    ("i", "Imbox", "tag:inbox and tag:screened and tag:unread and not tag:seen and not tag:bundled", False),
    ("y", "Prev. Seen", "tag:inbox and tag:screened and tag:unread and tag:seen", False),
    # Unthreaded, alone among the boxes: the Screener decides on people, and one sender's year of notifications would thread into one row.
    ("s", "Screener", "tag:inbox and tag:unread and not tag:screened", True),
    ("f", "The Feed", "tag:thefeed and tag:unread", False),
    ("p", "Paper Trail", "tag:/^ledger\\//", False),
    ("l", "Reply Later", "tag:replylater", False),
    ("a", "Set Aside", "tag:setaside", False),
    ("b", "Bubbled Up", "tag:bubbled and tag:unread", False),
    ("I", "Read", "tag:inbox and tag:screened and not tag:unread", False),
    ("n", "Notes", "tag:note", False),
    ("m", "Muted", "tag:muted", False),
    ("t", "Sent", "tag:sent", False),
    ("e", "Everything", "*", False),
]


class MailError(Exception):
    pass


class NotFound(MailError):
    pass


def nm(*args, stdin=None):
    try:
        return subprocess.run(["notmuch", *args], input=stdin, capture_output=True,
                              text=True, check=True).stdout
    except subprocess.CalledProcessError as e:
        raise MailError(f"notmuch {args[0]}: {(e.stderr or '').strip() or 'failed'}") from None


def show_json(*args):
    return json.loads(nm("show", "--format=json", "--format-version=5", *args))


def idq(msg_id):
    """An id: term notmuch reads whole: a Message-Id is the sender's text, and its ' ( ) " break an unquoted term."""
    return 'id:"' + msg_id.replace('"', '""') + '"'


def target(query):
    """A message or thread from a mail buffer as notmuch should read it; the buffers keep ids bare.
    Notmuch drops a Message-Id's whitespace, so a query with a space, or an id already quoted, goes as written."""
    rest = query[3:]
    bare = query.startswith("id:") and rest and not rest.startswith('"') and not any(c.isspace() for c in rest)
    return idq(rest) if bare else query


def both(a, b):
    """Mail matching query A and query B; notmuch reads a bare * only alone, and (*) matches nothing."""
    terms = [q for q in (a, b) if q.strip() != "*"]
    return " and ".join(f"({q})" for q in terms) or "*"


def box(name):
    for b in BOXES:
        if b[1] == name:
            return b
    return None


def box_counts():
    """How many messages each box holds, in BOXES order."""
    return [int(n) for n in nm("count", "--batch", stdin="\n".join(b[2] for b in BOXES) + "\n").split()]


# A sender writes every header, so control characters (a newline splits a row, ESC drives the terminal) become spaces and bidi controls go.
BIDI = dict.fromkeys(map(ord, "؜‎‏‪‫‬‭‮⁦⁧⁨⁩"))


def line(s):
    """S as one line of plain text: control characters become spaces, bidi controls are dropped."""
    s = re.sub(r"[\x00-\x1f\x7f-\x9f]", " ", str(s))
    return s.translate(BIDI)


def search_threads(query, limit, offset=0):
    """notmuch's thread summaries for QUERY, newest first."""
    return json.loads(nm("search", "--format=json", "--format-version=5", f"--limit={limit}", f"--offset={offset}", "--", query))


def matched_messages(query):
    """The messages QUERY matches, without bodies, newest first."""
    msgs = []

    def walk(nodes):
        for node in nodes:
            if isinstance(node, list):
                walk(node)
            elif isinstance(node, dict) and "id" in node:
                if node.get("match"):
                    msgs.append(node)
    walk(show_json("--body=false", "--entire-thread=false", "--", query))
    msgs.sort(key=lambda m: -m["timestamp"])
    return msgs


# Where a mail lives when several boxes hold it, as hey-folder-sync files it: a pile, then the Feed and Paper Trail, then the Screener and the Imbox.
HOME_ORDER = ["Bubbled Up", "Reply Later", "Set Aside", "The Feed", "Paper Trail", "Screener", "Imbox", "Prev. Seen", "Read",
              "Muted", "Notes", "Sent"]


def boxes_of(msg_ids):
    """The box each of MSG_IDS lives in, by HOME_ORDER; a message no box holds is left out."""
    home = {}
    if not msg_ids:
        return home
    ids = " or ".join(idq(i) for i in msg_ids)
    for name in HOME_ORDER:
        for i in json.loads(nm("search", "--format=json", "--output=messages", "--", both(box(name)[2], ids))):
            home.setdefault(i, name)
    return home


def thread_of(msg_id):
    found = nm("search", "--output=threads", "--", idq(msg_id)).split()
    if not found:
        raise NotFound(f"no message {idq(msg_id)}")
    return found[0].removeprefix("thread:")


def write_count():
    """Write the Imbox unread count to COUNT_FILE through a rename, so the margin never reads half a file; return it."""
    n = int(nm("count", "--", box("Imbox")[2]))
    os.makedirs(os.path.dirname(COUNT_FILE), exist_ok=True)
    tmp = f"{COUNT_FILE}.{os.getpid()}.tmp"
    with open(tmp, "w") as f:
        f.write(f"{n}\n")
    os.replace(tmp, COUNT_FILE)
    return n


def refresh_count():
    # A count that fails leaves the margin's last number; reading or filing mail goes on.
    try:
        write_count()
    except (MailError, OSError, ValueError):
        pass


def set_unread(query, unread):
    """Mark QUERY's messages unread or read, then rewrite the margin's count."""
    nm("tag", "+unread" if unread else "-unread", "--", query)
    refresh_count()


def html_to_text(html, links=True):
    # lynx never fetches, so remote images and trackers stay blocked; a quoted reply drops the link list (links=False).
    r = subprocess.run(["lynx", "-dump", "-stdin", "-force_html", "-nomargins",
                        "-display_charset=utf-8", "-assume_charset=utf-8", "-width=100",
                        *([] if links else ["-nolist"])],
                       input=html, capture_output=True, text=True)
    return r.stdout


def body_text(parts, attachments, links=True):
    """Readable text of a MIME tree; attachments collected as (id, name, type)."""
    out = []
    for p in parts:
        ct = p.get("content-type", "").lower()
        c = p.get("content")
        if p.get("filename") or (p.get("content-disposition") == "attachment"):
            # The name is the sender's text: one line, or it splits the thread and the A picker.
            attachments.append((p["id"], line(p.get("filename") or "").strip() or "unnamed", ct))
        elif ct == "multipart/alternative" and isinstance(c, list):
            plain = [q for q in c if q.get("content-type", "").lower() == "text/plain" and (q.get("content") or "").strip()]
            html = [q for q in c if q.get("content-type", "").lower() == "text/html"]
            if plain:
                out.append(plain[0]["content"])
            elif html:
                out.append(html_to_text(html[0].get("content") or "", links))
            else:
                out.append(body_text(c, attachments, links))
        elif ct.startswith("multipart/") and isinstance(c, list):
            out.append(body_text(c, attachments, links))
        elif ct == "message/rfc822" and isinstance(c, list):
            for inner in c:
                h = inner.get("headers", {})
                out.append("---------- attached message ----------\n" +
                           "".join(f"{k}: {line(h[k])}\n" for k in ("From", "Date", "Subject") if k in h) + "\n" +
                           body_text(inner.get("body", []), attachments, links))
        elif ct == "text/plain":
            out.append(c or "")
        elif ct == "text/html":
            out.append(html_to_text(c or "", links))
        elif ct.startswith("text/") and isinstance(c, str):
            out.append(c)
    return "\n".join(s.rstrip("\n") + "\n" for s in out if s)


def thread_messages(query):
    """Every message of the threads QUERY matches, with bodies, in thread order."""
    msgs = []

    def walk(nodes):
        for node in nodes:
            if isinstance(node, list):
                walk(node)
            elif isinstance(node, dict) and "id" in node:
                msgs.append(node)
    walk(show_json("--include-html", "--entire-thread=true", "--", query))
    return msgs


def one_message(msg_id):
    m = next((m for m in thread_messages(idq(msg_id)) if m["id"] == msg_id), None)
    if m is None:
        raise NotFound(f"no message {idq(msg_id)}")
    return m


def message_of(query):
    """Bare Message-Id for QUERY: an id: as given, a thread: by its newest
    message — the one the list row is showing."""
    if query.startswith("id:"):
        return query[3:]
    ids = nm("search", "--output=messages", "--sort=newest-first", "--limit=1", query).split()
    if not ids:
        raise NotFound(f"no message for {query}")
    return ids[0].removeprefix("id:")


def part_bytes(msg_id, part):
    """The decoded bytes of one MIME part of a message."""
    try:
        return subprocess.run(["notmuch", "show", f"--part={part}", idq(msg_id)],
                              capture_output=True, check=True).stdout
    except subprocess.CalledProcessError as e:
        raise MailError(f"notmuch show: {e.stderr.decode(errors='replace').strip() or 'failed'}") from None
