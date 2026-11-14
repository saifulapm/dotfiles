"""mail_engine: reads the notmuch mail store, and writes and sends drafts, for kak-mail and bin/mail.

Its functions return data and raise MailError; none prints, exits, or marks
mail read as a side effect of reading. The box list lives here only.
"""

import email.policy
import fcntl
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


class Refusal(MailError):
    """A send that must not go: the draft was sent already, or changed since it was shown."""


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
    return mended(json.loads(nm("search", "--format=json", "--format-version=5", f"--limit={limit}", f"--offset={offset}", "--", query)))


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
        text = body_text(orig.get("body", []), atts)
        # The original's attachments ride along as Attach: pseudo-headers, like a hand-added one, so send has one path.
        os.makedirs(DRAFTS, exist_ok=True)
        for part_id, name, _ in atts:
            path = os.path.join(DRAFTS, f"fwd-{secrets.token_hex(4)}-{oneline(os.path.basename(name))}")
            with open(path, "wb") as f:
                f.write(part_bytes(msg_id, part_id))
            headers.append(("Attach", path))
        body = ("\n\n---------- Forwarded message ----------\n" +
                "".join(f"{k}: {oh[k]}\n" for k in ("From", "Date", "Subject", "To") if oh.get(k)) +
                "\n" + text)
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
            msg[k] = v
    return msg, attach, body


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
        raise Refusal(f"already sent; {mark} holds the message as it went out")
    try:
        with open(path, "rb") as f:
            raw = f.read()
    except FileNotFoundError:
        raise NotFound(f"no draft {path}") from None
    msg, attach, body = draft_message(raw.decode("utf-8", "replace"))
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
            raise MailError(f"attachment not found: {a}")
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
        if threads:
            subprocess.run(["notmuch", "tag", "-replylater", "-setaside", "--", " or ".join(threads)])
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
    table (suffix distinct from the hook's own `.tmp')."""
    path = db_path(db)
    if not os.path.exists(path):
        return
    with open(path) as f:
        lines = f.readlines()
    keep = [l for l in lines if addr.lower() not in (w.lower() for w in l.split())]
    if len(keep) != len(lines):
        with open(path + ".kak-tmp", "w") as f:
            f.writelines(keep)
        os.replace(path + ".kak-tmp", path)


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


SENDER_ACTIONS = ("screen-in", "feed", "papertrail", "screen-out", "unscreen", "autofile", "recycle")
THREAD_ACTIONS = ("reply-later", "set-aside", "clear", "bubble", "archive")


def decide(action, addr, arg=None):
    """Apply a sender ACTION to ADDR: its decision line in the db the post-new hook reads, and the tags on its mail so far."""
    frm = "from:" + addr
    if action == "screen-in":
        tag(frm, "+screened")
        db_add("screened.db", addr)
    elif action == "feed":
        tag(frm, "+thefeed", "+archived", "-inbox")
        db_add("thefeed.db", addr)
    elif action == "papertrail":
        cat = sanitize(arg, "Category")
        tag(frm, f"+ledger/{cat}", "+archived", "-inbox", "-unread")
        db_add("ledger.db", f"{cat} {addr}")
    elif action == "screen-out":
        tag(frm, "+spam", "+deleted", "+archived", "-inbox", "-unread", "-screened")
        db_add("spam.db", addr)
    elif action == "unscreen":
        for db in ("screened.db", "thefeed.db", "spam.db", "ledger.db", "autofile.db", "recycle.db"):
            db_drop(db, addr)
        tag(frm, "-screened", "-thefeed", "-spam", "-deleted", "-bubble", "+inbox")
    elif action == "autofile":
        label = sanitize(arg, "Label")
        db_add("autofile.db", f"{addr} {label}")
        tag(frm, f"+label/{label}")
    elif action == "recycle":
        if arg not in ("30", "90", "730"):
            raise MailError("recycle days must be 30, 90 or 730")
        db_add("recycle.db", f"{addr} {arg}")


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
    for tid in threads:
        q = "thread:" + tid
        if action == "reply-later":
            tag(q, "+replylater")
        elif action == "set-aside":
            tag(q, "+setaside")
        elif action == "clear":
            tag(q, "-replylater", "-setaside", "-bubbled")
        elif action == "archive":
            tag(q, "-inbox", "+archived")
        elif action == "bubble":
            db_add("bubble.db", f"{tid} {when}")
            tag(q, "+bubble", "-inbox", "-unread", "-bubbled")
    return len(threads), when
