"""mail_engine: reads the notmuch mail store, and writes and sends drafts, for kak-mail and bin/mail.

Its functions return data and raise MailError; none prints, exits, or marks
mail read as a side effect of reading. The box list lives here only.
"""

import email.policy
import fcntl
import functools
import hashlib
import json
import mimetypes
import os
import re
import secrets
import subprocess
import time
from email.message import EmailMessage
from email.utils import formatdate, getaddresses, make_msgid, parseaddr
from html.parser import HTMLParser
from urllib.parse import unquote

HOME = os.path.expanduser("~")
DB_DIR = os.environ.get("HEY_MAIL_DB_DIR") or os.path.join(os.environ.get("XDG_DATA_HOME", HOME + "/.local/share"), "hey-mail")
DRAFTS = os.path.join(os.environ.get("XDG_DATA_HOME", HOME + "/.local/share"), "kak-mail", "drafts")
SENT_FOLDER = "icloud/Sent Messages"
MSMTP_ACCOUNT = "icloud"
# The draft names send has sent: a Kakoune buffer still open on a draft an agent sent writes the file back, and this refuses it.
SENT_DRAFTS = os.path.join(os.environ.get("XDG_STATE_HOME", HOME + "/.local/state"), "kak-mail", "sent-drafts")
# When each HEY decision was made here, one "MILLISECONDS KEY" line each; dots sync's mail unit stamps the change with it, so the later decision wins, not the later sync.
JOURNAL = os.path.join(os.environ.get("XDG_STATE_HOME", HOME + "/.local/state"), "hey-mail", "decided")
# Held by each decision while it reads and writes the db files and the journal, and by dots sync's mail round from reading them to rewriting them, so neither writes over the other; mail-sync's lock is never taken, so a decision never waits for a fetch.
DECIDE_LOCK = os.path.join(os.path.dirname(JOURNAL), "decide.lock")
# The last archive or Feed move, for undo-last: when it was made, the tags of the mail it changed as `notmuch dump` wrote them, and the sender's class before a Feed move.
UNDO = os.path.join(os.environ.get("XDG_STATE_HOME", HOME + "/.local/state"), "hey-mail", "undo.json")
# The shell's margin watches this file for the Imbox unread count.
COUNT_FILE = os.path.join(os.environ.get("XDG_STATE_HOME", HOME + "/.local/state"), "dots", "mail-unread")

# The HEY boxes in HEY's order as (key, name, query, unthreaded); the queries use the post-new hook's tags, and tests/home/mail-engine.test.mjs pins them to the hook's and hey-folder-sync's.
BOXES = [
    ("i", "Imbox", "tag:inbox and tag:screened and tag:unread", False),
    # Unthreaded, alone among the boxes: the Screener decides on people, and one sender's year of notifications would thread into one row.
    ("s", "Screener", "tag:inbox and not tag:screened", True),
    ("f", "The Feed", "tag:thefeed", False),
    ("p", "Paper Trail", "tag:/^ledger\\//", False),
    ("l", "Reply Later", "tag:replylater", False),
    ("a", "Set Aside", "tag:setaside", False),
    ("b", "Bubbled Up", "tag:bubbled and tag:unread", False),
    ("I", "Read", "tag:inbox and tag:screened and not tag:unread", False),
    ("m", "Muted", "tag:muted", False),
    ("t", "Sent", "tag:sent", False),
    ("e", "Everything", "*", False),
]


class MailError(Exception):
    pass


class NotFound(MailError):
    pass


class Refusal(MailError):
    """A send that must not go: the draft was sent already, or changed since it was shown."""


class AlreadySent(Refusal):
    """A draft send has sent before."""


class MissingAttachment(MailError):
    """A draft's Attach: file is gone; PATH may hold a sender's file name, from a forward."""

    def __init__(self, path):
        super().__init__(f"attachment not found: {path}")
        self.path = path


def nm(*args, stdin=None):
    """notmuch's output; a byte that is not UTF-8 stays as a surrogate for mended() to read."""
    try:
        r = subprocess.run(["notmuch", *args], input=stdin.encode() if stdin is not None else None,
                           capture_output=True, check=True)
    except subprocess.CalledProcessError as e:
        raise MailError(f"notmuch {args[0]}: {e.stderr.decode(errors='replace').strip() or 'failed'}") from None
    return r.stdout.decode("utf-8", "surrogateescape")


RAW = re.compile("[\udc80-\udcff]+")
CHARSET = re.compile(rb"charset=[\"']?([\w.:-]+)", re.I)


def mended(obj):
    """OBJ with each run of raw bytes decoded: a part with no charset in its header comes through notmuch as the sender
    wrote it, so the charset its own text names (an HTML <meta>) reads it, and windows-1252 when it names none."""
    if isinstance(obj, list):
        return [mended(x) for x in obj]
    if isinstance(obj, dict):
        return {k: mended(v) for k, v in obj.items()}
    if not isinstance(obj, str) or not RAW.search(obj):
        return obj
    named = CHARSET.search(obj.encode("utf-8", "surrogateescape"))

    def decode(run):
        raw = run.group().encode("utf-8", "surrogateescape")
        try:
            return raw.decode(named.group(1).decode() if named else "cp1252", "replace")
        except LookupError:
            return raw.decode("cp1252", "replace")
    return RAW.sub(decode, obj)


def show_json(*args):
    return mended(json.loads(nm("show", "--format=json", "--format-version=5", *args)))


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


def within(*queries):
    """Mail matching every one of QUERIES, as an s-expression for --query=sexp: notmuch parses each query on its own, so a ) or " in a typed one cannot reach past it; a bare *, which (infix "*") reads as nothing, drops out."""
    return "(" + " ".join(['and'] + ['(infix "' + q.replace("\\", "\\\\").replace('"', '\\"') + '")' for q in queries if q.strip() != "*"]) + ")"


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


def search_threads(query, limit, offset=0, syntax="infix"):
    """notmuch's thread summaries for QUERY, in SYNTAX, newest first."""
    return mended(json.loads(nm("search", f"--query={syntax}", "--format=json", "--format-version=5", f"--limit={limit}", f"--offset={offset}", "--", query)))


def matched_messages(query, syntax="infix"):
    """The messages QUERY, in SYNTAX, matches, without bodies, newest first."""
    msgs = []

    def walk(nodes):
        for node in nodes:
            if isinstance(node, list):
                walk(node)
            elif isinstance(node, dict) and "id" in node:
                if node.get("match"):
                    msgs.append(node)
    walk(show_json(f"--query={syntax}", "--body=false", "--entire-thread=false", "--", query))
    msgs.sort(key=lambda m: -m["timestamp"])
    return msgs


# Where a mail lives when several boxes hold it, as hey-folder-sync files it: a pile, then the Feed and Paper Trail, then the Screener and the Imbox.
HOME_ORDER = ["Bubbled Up", "Reply Later", "Set Aside", "The Feed", "Paper Trail", "Screener", "Imbox", "Read", "Muted", "Sent"]


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


# notmuch hands over HTML already decoded to UTF-8, and lynx would believe a <meta> naming the sender's charset over -assume_charset.
META_CHARSET = re.compile(r"<meta\b[^>]*charset[^>]*>", re.I)


def html_to_text(html, links=True):
    # lynx never fetches, so remote images and trackers stay blocked; a quoted reply drops the link list (links=False).
    html = META_CHARSET.sub("", html)
    r = subprocess.run(["lynx", "-dump", "-stdin", "-force_html", "-nomargins",
                        "-display_charset=utf-8", "-assume_charset=utf-8", "-width=100",
                        *([] if links else ["-nolist"])],
                       input=html, capture_output=True, text=True)
    return r.stdout


class Anchors(HTMLParser):
    """Each <a href>'s text, in document order."""

    def __init__(self):
        super().__init__()
        self.found, self.open = [], None

    def handle_starttag(self, tag, attrs):
        if tag == "a" and dict(attrs).get("href"):
            self.open = [dict(attrs)["href"], ""]

    def handle_data(self, data):
        if self.open:
            self.open[1] += data

    def handle_endtag(self, tag):
        if tag == "a" and self.open:
            self.found.append((self.open[0], " ".join(self.open[1].split())))
            self.open = None


LYNX_REF = re.compile(r"^\s*(\d+)\. (\S.*)$")


def html_with_links(html, found):
    """lynx's text of HTML, its [n] link numbers kept and its References list cut; each numbered link goes on FOUND as (label, url)."""
    text = html_to_text(html)
    head, sep, refs = text.rpartition("\nReferences\n")
    rows = refs.split("\n")
    if not sep or not all(not r.strip() or r.strip() in ("Visible links:", "Hidden links:") or LYNX_REF.match(r) for r in rows):
        return text
    parser = Anchors()
    parser.feed(META_CHARSET.sub("", html))
    anchors = parser.found
    for r in rows:
        if r.strip() == "Hidden links:":
            break
        m = LYNX_REF.match(r)
        if m:
            url = m.group(2)
            label = next((a for a in anchors if a[0] == url), None)
            if label:
                anchors.remove(label)
            found.append((label[1] if label else url, url))
    return head.rstrip("\n") + "\n"


URL = re.compile(r"https?://[^\s<>\"')\]]+")


def body_text(parts, attachments, links=True, found=None):
    """Readable text of a MIME tree; attachments collected as (id, name, type).
    With FOUND, a list, HTML keeps its link numbers without lynx's list, and every link goes on FOUND as (label, url) instead."""
    out = []

    def html(content):
        return html_to_text(content, links) if found is None else html_with_links(content, found)

    def plain(content):
        if found is not None:
            found.extend((u, u) for u in dict.fromkeys(u.rstrip(".,;:!?") for u in URL.findall(content)))
        return content
    for p in parts:
        ct = p.get("content-type", "").lower()
        c = p.get("content")
        if p.get("filename") or (p.get("content-disposition") == "attachment"):
            # The name is the sender's text: one line, or it splits the thread and the A picker.
            attachments.append((p["id"], line(p.get("filename") or "").strip() or "unnamed", ct))
        elif ct == "multipart/alternative" and isinstance(c, list):
            plain_parts = [q for q in c if q.get("content-type", "").lower() == "text/plain" and (q.get("content") or "").strip()]
            html_parts = [q for q in c if q.get("content-type", "").lower() == "text/html"]
            if plain_parts:
                out.append(plain(plain_parts[0]["content"]))
            elif html_parts:
                out.append(html(html_parts[0].get("content") or ""))
            else:
                out.append(body_text(c, attachments, links, found))
        elif ct.startswith("multipart/") and isinstance(c, list):
            out.append(body_text(c, attachments, links, found))
        elif ct == "message/rfc822" and isinstance(c, list):
            for inner in c:
                h = inner.get("headers", {})
                out.append("---------- attached message ----------\n" +
                           "".join(f"{k}: {line(h[k])}\n" for k in ("From", "Date", "Subject") if k in h) + "\n" +
                           body_text(inner.get("body", []), attachments, links, found))
        elif ct == "text/plain":
            out.append(plain(c or ""))
        elif ct == "text/html":
            out.append(html(c or ""))
        elif ct.startswith("text/") and isinstance(c, str):
            out.append(plain(c))
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


def part_sizes(parts):
    """Each MIME part's decoded size by part id; notmuch hands a text part over as its UTF-8 text instead of a length."""
    sizes = {}
    for p in parts:
        c = p.get("content")
        if "content-length" in p:
            sizes[p["id"]] = p["content-length"]
        elif isinstance(c, str):
            sizes[p["id"]] = len(c.encode())
        if isinstance(c, list):
            sizes.update(part_sizes([q for q in c if "id" in q] + [b for inner in c for b in inner.get("body", [])]))
    return sizes


def part_bytes(msg_id, part):
    """The decoded bytes of one MIME part of a message."""
    try:
        return subprocess.run(["notmuch", "show", f"--part={part}", idq(msg_id)],
                              capture_output=True, check=True).stdout
    except subprocess.CalledProcessError as e:
        raise MailError(f"notmuch show: {e.stderr.decode(errors='replace').strip() or 'failed'}") from None


# ───────────────────────────── compose / send ─────────────────────────────

def identities():
    name = nm("config", "get", "user.name").strip()
    addrs = [nm("config", "get", "user.primary_email").strip()]
    addrs += [a for a in nm("config", "get", "user.other_email").split() if a]
    return [f"{name} <{a}>" if name else a for a in addrs]


def nametag():
    try:
        with open(os.path.join(DB_DIR, "nametag")) as f:
            s = f.read().strip()
        return f"\n\n-- \n{s}\n" if s else "\n"
    except FileNotFoundError:
        return "\n"


def quote(text):
    return "".join("> " + l if l.strip() else ">\n" for l in text.splitlines(True)) + "\n"


# Every character str.splitlines() breaks on: a sender's header value holding one would start a header line of its own in the draft.
LINE_BREAKS = re.compile("[\n\r\v\f\x1c\x1d\x1e\x85\u2028\u2029]")


def oneline(value):
    return LINE_BREAKS.sub(" ", value)


# The mailto fields a draft takes; any other (bcc, from, attach, in-reply-to) is a web page's say about who the mail goes to or what it holds, so it is dropped.
MAILTO_FIELDS = {"to": "To", "cc": "Cc", "subject": "Subject", "body": "Body"}


def mailto(url):
    """URL's draft headers (To, Cc, Subject) and Body, as RFC 6068 spells them; + is a plus, not a space."""
    if not url.lower().startswith("mailto:"):
        raise MailError(f"not a mailto URL: {url}")
    path, _, query = url[7:].partition("?")
    fields = {"To": [unquote(path)] if path else [], "Cc": [], "Subject": [], "Body": []}
    for pair in query.split("&"):
        k, _, v = pair.partition("=")
        name = MAILTO_FIELDS.get(unquote(k).lower())
        if name:
            fields[name].append(unquote(v))
    out = [(k, ", ".join(a for a in fields[k] if a)) for k in ("To", "Cc") if any(fields[k])]
    out.append(("Subject", fields["Subject"][0] if fields["Subject"] else ""))
    if fields["Body"]:
        out.append(("Body", fields["Body"][0].replace("\r\n", "\n")))
    return out


# The address headers and Subject in the order a draft writes them.
HEADER_ORDER = ["From", "To", "Cc", "Bcc", "Subject"]


def with_header(headers, name, value):
    """HEADERS with NAME's value set to VALUE: in place of the first NAME line, else after the headers that come before it."""
    if any(k.lower() == name.lower() for k, _ in headers):
        first = next(i for i, (k, _) in enumerate(headers) if k.lower() == name.lower())
        return [(name, value) if i == first else (k, v) for i, (k, v) in enumerate(headers)
                if i == first or k.lower() != name.lower()]
    rank = HEADER_ORDER.index(name)
    at = next((i for i, (k, _) in enumerate(headers) if k in HEADER_ORDER and HEADER_ORDER.index(k) > rank), len(headers))
    return headers[:at] + [(name, value)] + headers[at:]


def write_draft(kind, arg=None, overrides=(), text=None, attach=()):
    """A new draft of KIND (new, reply, replyall, forward of the message ARG names, or mailto URL ARG); returns its path.
    OVERRIDES are (header, value) pairs that replace the draft's own, TEXT goes above any quote, ATTACH are file paths."""
    headers, body = [], ""
    if kind == "new":
        headers = [("From", identities()[0]), ("To", ""), ("Subject", "")]
    elif kind in ("reply", "replyall"):
        msg_id = message_of(arg)
        r = json.loads(nm("reply", "--format=json",
                          "--reply-to=" + ("all" if kind == "replyall" else "sender"), idq(msg_id)))
        rh = r["reply-headers"]
        # notmuch spells it "In-reply-to"; send keys off the canonical name.
        rh = {k.lower(): v for k, v in rh.items()}
        headers = [(k, rh[k.lower()]) for k in ("From", "To", "Cc", "Subject", "In-Reply-To", "References")
                   if rh.get(k.lower())]
        orig = one_message(msg_id)
        oh = orig["headers"]
        body = (f"\n\nOn {oh.get('Date', '')}, {oh.get('From', '')} wrote:\n" +
                quote(body_text(orig.get("body", []), [], links=False)))
    elif kind == "mailto":
        fields = mailto(arg)
        headers = [("From", identities()[0])] + [f for f in fields if f[0] != "Body"]
        body = "".join("\n" + v for k, v in fields if k == "Body")
    elif kind == "forward":
        msg_id = message_of(arg)
        orig = one_message(msg_id)
        oh = orig["headers"]
        subj = oh.get("Subject", "")
        headers = [("From", identities()[0]), ("To", ""),
                   ("Subject", subj if subj.lower().startswith("fwd:") else "Fwd: " + subj)]
        atts = []
        forwarded = body_text(orig.get("body", []), atts)
        # The original's attachments ride along as Attach: pseudo-headers, like a hand-added one, so send has one path.
        os.makedirs(DRAFTS, exist_ok=True)
        for part_id, name, _ in atts:
            path = os.path.join(DRAFTS, f"fwd-{secrets.token_hex(4)}-{oneline(os.path.basename(name))}")
            with open(path, "wb") as f:
                f.write(part_bytes(msg_id, part_id))
            headers.append(("Attach", path))
        body = ("\n\n---------- Forwarded message ----------\n" +
                "".join(f"{k}: {oh[k]}\n" for k in ("From", "Date", "Subject", "To") if oh.get(k)) +
                "\n" + forwarded)
    else:
        raise MailError(f"unknown compose kind: {kind}")
    for name, value in overrides:
        headers = with_header(headers, name, value)
    headers += [("Attach", a) for a in attach]
    if text is not None:
        text = text.replace("\r\n", "\n").rstrip("\n") + "\n"
        # The body starts with the blank line that ends the headers; the text goes after it, above a quote or a forward.
        body = "\n" + text + body[1:]
    os.makedirs(DRAFTS, exist_ok=True)
    path = os.path.join(DRAFTS, time.strftime("%Y%m%d-%H%M%S-") + secrets.token_hex(3) + ".eml")
    with open(path, "w") as f:
        f.write("".join(f"{k}: {oneline(v)}\n" for k, v in headers) + body + nametag())
    return path


def parse_draft(text):
    head, _, body = text.partition("\n\n")
    headers = []
    for line in head.splitlines():
        if line[:1] in (" ", "\t") and headers:
            headers[-1] = (headers[-1][0], headers[-1][1] + " " + line.strip())
        elif ":" in line:
            k, v = line.split(":", 1)
            headers.append((k.strip(), v.strip()))
    return headers, body


# A draft's file name as write_draft makes it; a forward's attachments beside the drafts are named fwd-….
DRAFT_NAME = re.compile(r"\d{8}-\d{6}-[0-9a-f]{6}")


def draft_path(arg):
    """The draft file ARG names, by its id or its path, or None when ARG names no file in the drafts folder."""
    stem = os.path.basename(arg).removesuffix(".eml")
    if not DRAFT_NAME.fullmatch(stem) or os.path.basename(arg) not in (stem, stem + ".eml"):
        return None
    if os.sep in arg and os.path.dirname(os.path.abspath(arg)) != os.path.abspath(DRAFTS):
        return None
    return os.path.join(DRAFTS, stem + ".eml")


def drafts():
    """The draft files, newest first."""
    try:
        names = [n for n in os.listdir(DRAFTS) if n.endswith(".eml") and DRAFT_NAME.fullmatch(n[:-4])]
    except FileNotFoundError:
        return []
    paths = [os.path.join(DRAFTS, n) for n in names]
    return sorted(paths, key=lambda p: -os.stat(p).st_mtime)


def draft_message(text):
    """The message a draft's TEXT sends, without its Date and Message-ID, its attachment paths and its body; send and show read a draft only this way."""
    headers, body = parse_draft(text)
    msg = EmailMessage(policy=email.policy.SMTP)
    attach = []
    for k, v in headers:
        if k.lower() == "attach":
            attach.append(os.path.expanduser(v))
        elif v and k.lower() in ("to", "cc", "bcc") and msg.get(k):
            # A second To line adds its people; the message can hold only one.
            merged = f"{msg[k]}, {v}"
            del msg[k]
            msg[k] = merged
        elif v:
            # A message holds one Subject or From; a later line of a hand-edited draft replaces the earlier one.
            del msg[k]
            msg[k] = v
    return msg, attach, body


def check_recipients(msg):
    """Raise MailError when a To, Cc or Bcc line does not read as a clean list of addresses: msmtp -t reads such a line its own
    way, so what draft show lists and who the mail goes to could differ."""
    for k in ("To", "Cc", "Bcc"):
        h = msg.get(k)
        if h is not None and (h.defects or any(not a.addr_spec or a.addr_spec == "<>" for a in h.addresses)):
            raise MailError(f"the {k} line does not read as a list of addresses")


def digest(raw, attach):
    """A digest of a draft's bytes RAW and of each attachment's bytes, so a change to either shows."""
    h = hashlib.sha256(raw)
    for a in attach:
        h.update(b"\0" + os.fsencode(a) + b"\0")
        try:
            with open(a, "rb") as f:
                h.update(hashlib.sha256(f.read()).digest())
        except OSError:
            h.update(b"missing")
    return h.hexdigest()[:16]


def send_draft(path, expect=None, env=None):
    """Send the draft at PATH through msmtp, file it in Sent, delete it; return the To and Cc addresses.
    With EXPECT, a draft whose digest is not EXPECT is refused; ENV is msmtp's environment. One send at a time holds the drafts folder's lock,
    so two sends of one draft run msmtp once: the second finds the draft gone."""
    folder = os.open(os.path.dirname(os.path.abspath(path)), os.O_RDONLY)
    try:
        fcntl.flock(folder, fcntl.LOCK_EX)
        return locked_send(path, expect, env)
    finally:
        os.close(folder)


def locked_send(path, expect, env):
    # Kakoune writes the buffer back over the draft before each send, so the mark lives beside it.
    mark = path + ".sent"
    if os.path.exists(mark):
        raise AlreadySent(f"already sent; {mark} holds the message as it went out")
    try:
        with open(SENT_DRAFTS) as f:
            if os.path.basename(path) in f.read().split():
                raise AlreadySent("already sent; this draft went out before, so discard it")
    except FileNotFoundError:
        pass
    try:
        with open(path, "rb") as f:
            raw = f.read()
    except FileNotFoundError:
        raise NotFound(f"no draft {path}") from None
    msg, attach, body = draft_message(raw.decode("utf-8", "replace"))
    check_recipients(msg)
    if expect is not None and digest(raw, attach) != expect:
        raise Refusal("the draft changed since it was shown")
    if not any(msg.get(h) for h in ("To", "Cc", "Bcc")):
        raise MailError("no recipients (To/Cc/Bcc all empty)")
    if not msg.get("From"):
        raise MailError("no From header")
    domain = parseaddr(msg["From"])[1].rpartition("@")[2] or None
    msg["Date"] = formatdate(localtime=True)
    msg["Message-ID"] = make_msgid(domain=domain)
    msg.set_content(body)
    for a in attach:
        if not os.path.isfile(a):
            raise MissingAttachment(a)
        ctype = mimetypes.guess_type(a)[0] or "application/octet-stream"
        maintype, subtype = ctype.split("/", 1)
        with open(a, "rb") as f:
            msg.add_attachment(f.read(), maintype=maintype, subtype=subtype, filename=os.path.basename(a))
    raw = msg.as_bytes()
    # -t takes recipients from To/Cc/Bcc (msmtp strips Bcc) and the envelope-from from From, so every iCloud+ alias sends as itself.
    r = subprocess.run(["msmtp", "-a", MSMTP_ACCOUNT, "--read-envelope-from", "-t"],
                       input=raw, capture_output=True, env=env)
    if r.returncode != 0:
        raise MailError("msmtp: " + (r.stderr.decode(errors="replace").strip().splitlines() or ["failed"])[-1])
    with open(mark, "wb") as f:
        f.write(raw)
    os.makedirs(os.path.dirname(SENT_DRAFTS), exist_ok=True)
    with open(SENT_DRAFTS, "a") as f:
        f.write(os.path.basename(path) + "\n")
    # File the sent copy in icloud/Sent Messages, tagged +sent -inbox -unread -new.
    filed = subprocess.run(["notmuch", "insert", f"--folder={SENT_FOLDER}", "+sent", "-inbox", "-unread", "-new"],
                           input=raw, capture_output=True)
    if filed.returncode != 0:
        why = (filed.stderr.decode(errors="replace").strip().splitlines() or ["notmuch insert failed"])[-1]
        # Kakoune's status line cuts a long message, so the file to look in comes before notmuch's reason.
        raise MailError(f"sent, but not filed in Sent; {os.path.basename(mark)} beside the draft holds it: {why}")
    irt = msg.get("In-Reply-To", "").strip().strip("<>")
    if irt:
        subprocess.run(["notmuch", "tag", "+replied", "--", idq(irt)])
        # The mail is out and filed, so a busy database only leaves the thread's piles as they were.
        threads = subprocess.run(["notmuch", "search", "--output=threads", idq(irt)], capture_output=True, text=True).stdout.split()
        for thread in threads:
            try:
                unpile(thread)
            except MailError:
                pass
        refresh_count()
    for a in attach:
        if os.path.dirname(a) == DRAFTS:
            os.unlink(a)
    os.unlink(path)
    os.unlink(mark)
    return [a for _, a in getaddresses([msg.get('To', ''), msg.get('Cc', '')]) if a]


# ───────────────────────────── HEY actions ─────────────────────────────

# The post-new hook applies these .db files to every new message, so their tags and line formats are its own.

def db_path(db):
    os.makedirs(DB_DIR, exist_ok=True)
    return os.path.join(DB_DIR, db)


def db_add(db, line):
    with open(db_path(db), "a") as f:
        f.write(line + "\n")


def db_drop(db, addr):
    """Remove the lines naming ADDR as one whole field, so joann@ outlives ann@;
    written via rename so the post-new hook never reads a half-written routing
    table (suffix distinct from the hook's own `.tmp'); returns the lines it
    removed, split into words."""
    path = db_path(db)
    if not os.path.exists(path):
        return []
    with open(path) as f:
        lines = f.readlines()
    keep = [l for l in lines if addr.lower() not in (w.lower() for w in l.split())]
    if len(keep) != len(lines):
        with open(path + ".kak-tmp", "w") as f:
            f.writelines(keep)
        os.replace(path + ".kak-tmp", path)
    return [l.split() for l in lines if l not in keep]


def sanitize(name, what):
    clean = re.sub(r"[^A-Za-z0-9_-]", "", name or "")
    if not clean:
        raise MailError(f"{what} must contain a letter, digit, - or _")
    return clean


def sender(query):
    """The sender to decide on: newest sender of QUERY that is not you."""
    mine = {parseaddr(i)[1].lower() for i in identities()}
    for a in nm("address", "--output=sender", "--output=address", query).split():
        if a.lower() not in mine:
            return a.lower()
    raise MailError(f"no sender found for {query}")


def tag(query, *changes):
    nm("tag", *changes, "--", query)


# An address or @domain rule goes into a from: query in post-new and dots sync, so nothing in it may widen the query: notmuch reads from:/.../ as a regex, and a domain with no dot matches every address under it.
ADDR = re.compile(r'[^\s"*(){}\[\]\\/@]*@(?:[^\s"*(){}\[\]\\/@.]+\.)+[^\s"*(){}\[\]\\/@.]+')
# Domains anyone can sign up at, which never get an @domain line.
FREEMAIL = {"gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "yahoo.com", "icloud.com", "me.com",
            "mac.com", "proton.me", "protonmail.com", "aol.com"}
# Each sender class file and the class its lines give; a ledger.db line names its category first, and its class is "ledger CATEGORY".
CLASS_FILES = {"screened.db": "screened", "thefeed.db": "thefeed", "spam.db": "spam", "ledger.db": "ledger"}
# An address in two class files reads as post-new's tags leave its mail: spam over Paper Trail over The Feed over screened in.
CLASS_RANK = ("screened", "thefeed", "ledger", "spam")
CATEGORY = re.compile(r"[A-Za-z0-9_-]+")


def class_line(name, line):
    """The (address, class) a line of class file NAME gives, or None for a comment or a line no decision reads."""
    w = line.split()
    if not w or w[0].startswith("#"):
        return None
    if name == "ledger.db":
        return (w[1].lower(), "ledger " + w[0]) if len(w) > 1 and CATEGORY.fullmatch(w[0]) else None
    return w[0].lower(), CLASS_FILES[name]


def class_rank(cls):
    return CLASS_RANK.index(cls.split(" ")[0])


def sender_class(addr):
    """ADDR's class in this machine's files, or None."""
    best = None
    for name in CLASS_FILES:
        try:
            with open(db_path(name)) as f:
                lines = f.read().splitlines()
        except FileNotFoundError:
            continue
        for got in filter(None, (class_line(name, line) for line in lines)):
            if got[0] == addr.lower() and (best is None or class_rank(got[1]) > class_rank(best)):
                best = got[1]
    return best


def stamp(key):
    os.makedirs(os.path.dirname(JOURNAL), exist_ok=True)
    with open(JOURNAL, "a") as f:
        f.write(f"{int(time.time() * 1000)} {key}\n")


# What each sender class puts on the sender's mail, as post-new does for new mail.
CLASS_TAGS = {
    "screened": ("+screened",),
    "thefeed": ("+thefeed", "+archived", "-inbox"),
    "spam": ("+spam", "+deleted", "+archived", "-inbox", "-unread", "-screened"),
}
# What leaving every class takes off a sender's mail.
LEFT_TAGS = ("-screened", "-thefeed", "-spam", "-deleted", "-bubble")
# A sender moved from one class to another starts from the inbox, unarchived, before the new class's tags; The Feed, Paper Trail and screen-out archive again.
UNSCREEN_TAGS = (*LEFT_TAGS, "-archived", "+inbox")


def class_tags(cls):
    if cls.startswith("ledger "):
        return (f"+ledger/{cls[7:]}", "+archived", "-inbox", "-unread")
    return CLASS_TAGS[cls]


# What a regex reads as more than itself; ADDR keeps most of them out of a key, and the rest are escaped.
RX_SPECIAL = set(".^$|?*+()[]{}")


def from_query(key):
    """The from: query for a sender key of the db files, as a regex in any case: an address key matches that From address exactly and an @domain key any address of that domain alone, since notmuch reads from:"a@d" as a phrase that also matches a longer address ending in it and a display name spelling it."""
    # notmuch matches a regex byte by byte, so only an ASCII letter gets its other case.
    rx = "".join(f"[{c.lower()}{c.upper()}]" if c.isascii() and c.isalpha() else "\\" + c if c in RX_SPECIAL else c for c in key)
    # An address starts the header, follows its <, or follows the comma of a list, whose last address its domain's line matches too; an old-style (comment) may follow a bare address that is the whole header.
    comment = r"[[:space:]]*\([^()]*\)$"
    if key.startswith("@"):
        return f'from:"/{rx}>?$|^[^[:space:]<>(),@]*{rx}{comment}/"'
    return f'from:"/(^|<|,[[:space:]]*){rx}>?$|^{rx}{comment}/"'


def domain_of(addr):
    return "@" + addr.rpartition("@")[2].lower()


def own_lines(domain):
    """The addresses under DOMAIN that a class line of their own decides."""
    found = set()
    for name in CLASS_FILES:
        try:
            with open(db_path(name)) as f:
                lines = f.read().splitlines()
        except FileNotFoundError:
            continue
        found.update(a for a, _ in filter(None, (class_line(name, line) for line in lines))
                     if not a.startswith("@") and domain_of(a) == domain.lower())
    return sorted(found)


def key_query(key, keep=None):
    """The query for the mail a sender KEY's line decides: an @domain line leaves out each address in KEEP, by default those with a line of their own, as that line decides their mail."""
    q = from_query(key)
    if key.startswith("@"):
        keep = own_lines(key) if keep is None else keep
        if keep:
            q = f"{q} and not ({' or '.join(from_query(a) for a in keep)})"
    return q


# How far back an unscreened sender's mail waits in the Screener again; older mail stays archived.
SCREENER_DAYS = 365


def to_screener(addr, unread=True, keep=None):
    """Put the mail ADDR's line decided of the last SCREENER_DAYS back in the Screener, in no box and with UNREAD unread, and archive the rest."""
    frm = key_query(addr, keep)
    ledger = [t for t in nm("search", "--exclude=false", "--output=tags", "--", frm).split() if t.startswith("ledger/")]
    tag(frm, *LEFT_TAGS, *(f"-{t}" for t in ledger))
    since = int(time.time()) - SCREENER_DAYS * 86400
    tag(f"{frm} and date:@{since}..", "+inbox", "-archived", *(("+unread",) if unread else ()))
    tag(f"{frm} and date:..@{since}", "+archived", "-inbox")
    unpiled_inbox(frm)


def refile(addr, old, new, keep=None, pulled=False):
    """Re-file the mail this machine holds from ADDR, whose class went from OLD to NEW (either may be None), as unscreening and deciding here would; an @domain leaves out the addresses in KEEP, as key_query does.
    A PULLED decision, made on another machine, leaves unread as it is: that machine changed its own mail's, and iCloud carries the flag here."""
    frm = key_query(addr, keep)
    if old and not new:
        to_screener(addr, unread=False, keep=keep)
    elif old and old != new:
        tag(frm, *UNSCREEN_TAGS, *((f"-ledger/{old[7:]}",) if old.startswith("ledger ") else ()))
    if new:
        tag(frm, *(t for t in class_tags(new) if not (pulled and t[1:] == "unread")))
    unpiled_inbox(frm)


def unpiled_inbox(query):
    """Take inbox back off QUERY's mail in Reply Later or Set Aside, which a sender's class change gives the sender's mail; a pile has no inbox until it is cleared."""
    tag(f"({query}) and (tag:replylater or tag:setaside)", "-inbox")


SENDER_ACTIONS = ("screen-in", "feed", "papertrail", "screen-out", "unscreen", "autofile", "recycle")
DECIDES_CLASS = {"screen-in": "screened", "feed": "thefeed", "papertrail": "ledger", "screen-out": "spam"}
THREAD_ACTIONS = ("reply-later", "set-aside", "clear", "bubble", "archive", "mute")


def remember(query, **move):
    """Keep QUERY's tags, and MOVE, as the one move undo_last undoes; written by rename, so a failed write leaves the last one."""
    os.makedirs(os.path.dirname(UNDO), exist_ok=True)
    with open(UNDO + ".tmp", "w") as f:
        json.dump({**move, "at": time.time(), "dump": nm("dump", "--format=batch-tag", "--", query)}, f)
    os.replace(UNDO + ".tmp", UNDO)


# How long a move can be undone.
UNDO_SECONDS = 600


def lock_decisions():
    """Wait for DECIDE_LOCK and return the fd that holds it; the lock goes when the fd closes or the process ends."""
    os.makedirs(os.path.dirname(DECIDE_LOCK), exist_ok=True)
    fd = os.open(DECIDE_LOCK, os.O_WRONLY | os.O_CREAT, 0o644)
    fcntl.flock(fd, fcntl.LOCK_EX)
    return fd


def deciding(fn):
    """Run FN holding DECIDE_LOCK; nothing it calls may take the lock again, as a second flock in one process waits on the first."""
    @functools.wraps(fn)
    def run(*args, **kwargs):
        fd = lock_decisions()
        try:
            return fn(*args, **kwargs)
        finally:
            os.close(fd)
    return run


@deciding
def undo_last():
    """Put back the mail the last archive or Feed move changed, and the sender's class before a Feed move, when it was made in the last UNDO_SECONDS; return what it undid."""
    try:
        with open(UNDO) as f:
            move = json.load(f)
    except (FileNotFoundError, ValueError):
        move = None
    # A move from before moves were timed is past undoing; one stamped ahead of a clock set back is not.
    at = move.get("at") if isinstance(move, dict) and "dump" in move else None
    if not isinstance(at, (int, float)) or time.time() - at > UNDO_SECONDS:
        e = MailError("nothing to undo")
        e.hint = "undo-last undoes only the last archive or Feed move, once, within 10 minutes"
        raise e
    addr = move.get("sender")
    if addr:
        for db in CLASS_FILES:
            db_drop(db, addr)
        old = move.get("old")
        if old:
            db_add(old.split(" ")[0] + ".db", f"{old[7:]} {addr}" if old.startswith("ledger ") else addr)
        stamp("sender " + addr)
    nm("restore", "--format=batch-tag", stdin=move["dump"])
    os.unlink(UNDO)
    return f"feed of {addr}" if addr else "archive"


def covering(addr):
    """The key an unscreen of ADDR acts on: ADDR, or the @domain line that alone decides it."""
    if sender_class(addr) is None and sender_class(domain_of(addr)) is not None:
        return domain_of(addr)
    return addr


def domain_key(addr):
    """The @domain line a domain decision on ADDR writes, or a MailError when no such line may be written."""
    key = domain_of(addr)
    if not ADDR.fullmatch(key):
        e = MailError(f"{key} is not one domain, and its line would match more senders than it")
        e.hint = "name a domain with a dot in it, as @example.com"
        raise e
    # One sender at a freemail domain never decides everyone there.
    if key[1:] in FREEMAIL:
        e = MailError(f"{key[1:]} is freemail, so a domain line would decide every sender there; decide the address alone")
        e.hint = "decide the address alone: the same action without --domain, or screen-out --sender ADDR"
        raise e
    return key


@deciding
def decide(action, addr, arg=None, domain=False):
    """Apply a sender ACTION to ADDR, to its @domain with DOMAIN, or to the @domain line that alone decides it for unscreen: the decision line in the db the post-new hook reads, and the tags on its mail so far; return the key it acted on."""
    if "*" in addr:
        raise MailError(f"{addr} holds a *, which notmuch reads as any sender")
    if domain:
        if action not in DECIDES_CLASS:
            raise MailError(f"{action} takes no domain; a domain is screened in, fed, filed in Paper Trail or screened out")
        addr = domain_key(addr)
    elif addr.startswith("@") or not ADDR.fullmatch(addr):
        raise MailError(f"{addr} is not one plain address, and its line would match more senders than it")
    # A decision writes a line for the address alone, which beats its domain's line; an unscreen of an address no line of its own decides undoes its domain's line.
    if action == "unscreen":
        addr = covering(addr)
    frm = from_query(addr)
    # The class the domain's line gives an address with no line of its own.
    inherited = None if addr.startswith("@") else sender_class(domain_of(addr))
    if action in DECIDES_CLASS:
        # A sender has one class, so one moved from another loses its line there, and that class's tags, first.
        new = "ledger " + sanitize(arg, "Category") if action == "papertrail" else DECIDES_CLASS[action]
        old = sender_class(addr)
        if action == "feed":
            remember(frm, sender=addr.lower(), old=old)
        # Tags first: a notmuch that fails then leaves the files, and the sender's class, as they were.
        refile(addr, old or inherited, new)
        for db in CLASS_FILES:
            db_drop(db, addr)
        db_add(new.split(" ")[0] + ".db", f"{new[7:]} {addr}" if action == "papertrail" else addr)
        stamp("sender " + addr.lower())
    elif action == "unscreen":
        own = sender_class(addr)
        for db in ("screened.db", "thefeed.db", "spam.db", "ledger.db"):
            db_drop(db, addr)
        for w in db_drop("autofile.db", addr):
            if len(w) > 1:
                stamp(f"autofile {addr.lower()} {w[1]}")
        if db_drop("recycle.db", addr):
            stamp("recycle " + addr.lower())
        # An address that loses its own line under a domain's line is that line's again.
        if inherited:
            refile(addr, own, inherited)
        else:
            to_screener(addr)
        stamp("sender " + addr.lower())
    elif action == "autofile":
        label = sanitize(arg, "Label")
        db_add("autofile.db", f"{addr} {label}")
        tag(frm, f"+label/{label}")
        stamp(f"autofile {addr.lower()} {label}")
    elif action == "recycle":
        if arg not in ("30", "90", "730"):
            raise MailError("recycle days must be 30, 90 or 730")
        db_add("recycle.db", f"{addr} {arg}")
        stamp("recycle " + addr.lower())
    return addr


def unpile(thread):
    """Take THREAD out of Reply Later and Set Aside, giving inbox back to the mail a pile took it from: to its unread mail alone while any of the thread is unread, so the thread is in the Imbox and not in Read too, else to all of it, for Read."""
    # Archived, Feed and Paper Trail mail, a sent copy, a draft and muted mail had no inbox to give back.
    took = f"({thread}) and (tag:replylater or tag:setaside) and not (tag:archived or tag:sent or tag:draft or tag:muted or tag:deleted)"
    if nm("count", "--exclude=false", "--", f"(({took}) or (({thread}) and tag:inbox)) and tag:unread").strip() != "0":
        took = f"({took}) and tag:unread"
    # One batch, so a database busy between two calls never leaves the thread in a pile and the inbox at once.
    nm("tag", "--batch", stdin=f"+inbox -- {took}\n-replylater -setaside -- {thread}\n")


@deciding
def pile(action, queries, arg=None):
    """Apply a thread ACTION to every thread QUERIES match; return the thread count and, for bubble, when it comes back."""
    threads = dict.fromkeys(t.removeprefix("thread:")
                            for t in nm("search", "--output=threads", " or ".join(f"({q})" for q in queries)).split())
    when = None
    if action == "bubble":
        r = subprocess.run(["date", "-d", arg or "", "+%s"], capture_output=True, text=True)
        if r.returncode != 0 or not arg:
            raise MailError(f"cannot read a time from {arg!r} (try: tomorrow 9am, next friday, 3 days)")
        when = int(r.stdout)
        if when <= time.time():
            raise MailError("that time is already past")
    if action == "archive" and threads:
        remember(" or ".join("thread:" + tid for tid in threads))
    for tid in threads:
        q = "thread:" + tid
        if action == "reply-later":
            tag(f"{q} and not tag:sent", "+replylater", "-inbox")
        elif action == "set-aside":
            tag(f"{q} and not tag:sent", "+setaside", "-inbox")
        elif action == "clear":
            unpile(q)
            tag(q, "-bubbled")
            # A pending bubble is cancelled too: its line goes, stamped so dots sync takes the removal, and the thread is back in the inbox.
            try:
                with open(db_path("bubble.db")) as f:
                    named = {l.split()[0] for l in f if l.split()}
            except FileNotFoundError:
                named = set()
            for mid in named & set(nm("search", "--exclude=false", "--output=messages", q).split()):
                db_drop("bubble.db", mid)
                stamp("bubble " + mid)
            if nm("count", "--exclude=false", "--", f"({q}) and tag:bubble").strip() != "0":
                tag(q, "-bubble", "+inbox")
        elif action == "archive":
            tag(q, "-inbox", "+archived")
        elif action == "mute":
            # Named by its first Message-ID, as a bubble is, so post-new on every machine keeps the thread's new mail muted.
            first = nm("search", "--exclude=false", "--output=messages", "--sort=oldest-first", q).split()[0]
            try:
                with open(db_path("muted.db")) as f:
                    known = f.read().split()
            except FileNotFoundError:
                known = []
            if first not in known:
                db_add("muted.db", first)
            stamp("mute " + first)
            tag(q, "+muted", "-inbox")
        elif action == "bubble":
            # Named by its first Message-ID, which every machine knows the thread by, where a thread id is this machine's own.
            first = nm("search", "--exclude=false", "--output=messages", "--sort=oldest-first", q).split()[0]
            db_add("bubble.db", f"{first} {when}")
            stamp("bubble " + first)
            tag(q, "+bubble", "-inbox", "-unread", "-bubbled")
    return len(threads), when
