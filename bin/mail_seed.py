"""mail_seed: sorts the senders already in the notmuch store into HEY classes, for `mail seed`.

Its functions return data and raise MailError; bin/mail prints the report.
"""

import fcntl
import os
import re
import sys
import time
from collections import Counter
from email.parser import BytesHeaderParser
from email.utils import parseaddr

# Python would write bin/__pycache__ into the checkout on the first import.
sys.dont_write_bytecode = True
import mail_engine as E

FREEMAIL = {"gmail.com", "googlemail.com", "outlook.com", "hotmail.com", "live.com", "yahoo.com", "icloud.com", "me.com",
            "mac.com", "proton.me", "protonmail.com", "aol.com"}
NOTIFY_DOMAINS = ("github.com", "gitlab.com", "linkedin.com", "facebookmail.com", "x.com", "twitter.com", "slack.com",
                  "discord.com", "atlassian.net")
NOREPLY = {"noreply", "no-reply", "donotreply", "do-not-reply"}
RECEIPT = re.compile(r"\b(receipt|invoice|order|payment|shipping|statement)\b", re.I)
YEAR = 365 * 86400
# The classes in the order the report lists their lines.
ORDER = ("own", "screened", "feed", "paper", "junk", "screener", "archived")

# Each class: the report's label, and the db file and line a decision writes (None writes nothing).
LABELS = (("screened in", ("own", "screened")), ("feed", ("feed",)), ("paper trail", ("paper",)), ("junk only", ("junk",)),
          ("screener", ("screener",)), ("archived unclear", ("archived",)))
DB_LINE = {"own": ("screened.db", "{}"), "screened": ("screened.db", "{}"), "feed": ("thefeed.db", "{}"),
           "paper": ("ledger.db", "receipts {}")}
# The tags each class puts on its sender's mail as (add, remove); unread stays as iCloud has it.
TAGS = {"own": ({"screened"}, set()), "screened": ({"screened"}, set()), "feed": ({"thefeed", "archived"}, {"inbox"}),
        "paper": ({"ledger/receipts", "archived"}, {"inbox"}), "archived": ({"archived"}, {"inbox"}), "junk": (set(), set())}

FOLDER_SYNC = os.path.join(os.path.dirname(os.path.abspath(__file__)), "hey-folder-sync")
RULE = re.compile(r"""^rule "([^"]+)"\s+"([^"]+)"\s+'([^']+)'$""", re.M)
MOVABLE = re.compile(r"^MOVABLE=\(([^)]*)\)", re.M)
TERM = re.compile(r"(not )?tag:(?:/(.+)/|([^\s/()]+))")


def read_lines(name):
    # Read without db_path(), which makes the db dir, so a dry run writes nothing.
    try:
        with open(os.path.join(E.DB_DIR, name)) as f:
            return f.read().splitlines()
    except FileNotFoundError:
        return []


def decided_keys():
    """Every address and @domain a class file decides already."""
    return {got[0] for name in E.CLASS_FILES for got in filter(None, (E.class_line(name, l) for l in read_lines(name)))}


def messages():
    """Every message in the store, spam and deleted mail too, as notmuch's JSON gives it, without bodies."""
    out = []

    def walk(pairs):
        for msg, replies in pairs:
            if msg:
                out.append(msg)
            walk(replies)
    for thread in E.show_json("--body=false", "--entire-thread=false", "--exclude=false", "*"):
        walk(thread)
    return out


def file_headers(msg):
    """The header block of MSG's first file; notmuch's JSON carries only From, To, Cc, Subject and Date."""
    for path in msg.get("filename", []):
        try:
            with open(path, "rb") as f:
                head = b""
                for line in f:
                    if line in (b"\n", b"\r\n"):
                        break
                    head += line
            return BytesHeaderParser().parsebytes(head)
        except OSError:
            continue
    return BytesHeaderParser().parsebytes(b"")


def classify(addr, msgs, mine, wrote_to, junk_dir, now):
    """ADDR's class, first match wins: own, screened, junk, feed, paper, feed again by list headers, then screener or archived."""
    if addr in mine:
        return "own"
    if addr in wrote_to:
        return "screened"
    if all(m.get("filename") and all(p.startswith(junk_dir) for p in m["filename"]) for m in msgs):
        return "junk"
    local, _, domain = addr.rpartition("@")
    heads = [file_headers(m) for m in msgs]
    if any(v.strip().lower() != "no" for h in heads for v in h.get_all("Auto-Submitted", [])) \
            or any(domain == d or domain.endswith("." + d) for d in NOTIFY_DOMAINS):
        return "feed"
    if local in NOREPLY or any(RECEIPT.search(m["headers"].get("Subject", "")) for m in msgs):
        return "paper"
    if any(h.get("List-Id") is not None or h.get("List-Unsubscribe") is not None
           or (h.get("Precedence") or "").strip().lower() in ("bulk", "list") for h in heads):
        return "feed"
    return "screener" if max(m["timestamp"] for m in msgs) >= now - YEAR else "archived"


def folder_rules():
    """hey-folder-sync's rules as (folder, terms) in its order, and the folders it may move out of."""
    with open(FOLDER_SYNC) as f:
        text = f.read()
    rules = []
    for folder, _, query in RULE.findall(text):
        terms = []
        for term in ([] if query == "*" else query.split(" and ")):
            m = TERM.fullmatch(term)
            if not m:
                raise E.MailError(f"hey-folder-sync rule {folder} has a query seed cannot read: {query}")
            terms.append((bool(m[1]), re.compile(m[2]) if m[2] else m[3]))
        rules.append((folder, terms))
    movable = MOVABLE.search(text)
    if not rules or not movable:
        raise E.MailError(f"no rule or MOVABLE line in {FOLDER_SYNC}")
    return rules, set(re.findall(r'"([^"]+)"', movable[1]))


def holds(terms, tags):
    for negate, want in terms:
        hit = any(want.search(t) for t in tags) if isinstance(want, re.Pattern) else want in tags
        if hit == negate:
            return False
    return True


def plan():
    """What seeding would do: counts per class, the db lines, the tag batch and the folder moves."""
    now = time.time()
    root = E.nm("config", "get", "database.path").strip()
    store = os.path.join(root, os.environ.get("HEY_MAIL_STORE") or "icloud")
    mine = {parseaddr(i)[1].lower() for i in E.identities()}
    wrote_to = {a.lower() for a in E.nm("address", "--output=recipients", "--output=address", "--exclude=false", "tag:sent").split()}
    decided = decided_keys()
    by_sender = {}
    for m in messages():
        addr = parseaddr(m["headers"].get("From", ""))[1].lower()
        if "@" in addr:
            by_sender.setdefault(addr, []).append(m)

    def is_decided(addr):
        return addr in decided or "@" + addr.rpartition("@")[2] in decided
    classes = {a: classify(a, ms, mine, wrote_to, os.path.join(store, "Junk") + "/", now)
               for a, ms in by_sender.items() if not is_decided(a)}
    already = len(by_sender) - len(classes)

    # One @domain key for a company whose senders all land in one class; own addresses and freemail keep a key per address.
    by_domain = {}
    for a in by_sender:
        by_domain.setdefault(a.rpartition("@")[2], []).append(a)
    keys = {}
    for domain, addrs in by_domain.items():
        kinds = {classes.get(a) for a in addrs}
        if domain not in FREEMAIL and len(addrs) >= 2 and len(kinds) == 1 and None not in kinds and "own" not in kinds:
            keys["@" + domain] = addrs
        else:
            keys.update((a, [a]) for a in addrs if a in classes)

    counts = {c: [0, 0] for c in ORDER}
    batch, after, lines, screener = [], {}, [], []
    for key, addrs in sorted(keys.items(), key=lambda kv: (ORDER.index(classes[kv[1][0]]), kv[0])):
        cls = classes[addrs[0]]
        if cls in DB_LINE:
            db, form = DB_LINE[cls]
            lines.append((db, form.format(key), key))
        if cls == "screener":
            screener.append(key if len(addrs) == 1 else f"{key} ({len(addrs)} senders)")
        counts[cls][0] += len(addrs)
        for m in (m for a in addrs for m in by_sender[a]):
            tags = set(m["tags"])
            if cls == "screener":
                recent, gone = m["timestamp"] >= now - YEAR, tags & {"spam", "deleted"}
                add, drop = ({"inbox"}, {"archived"}) if recent and not gone else ({"archived"}, {"inbox"}) if not recent else (set(), set())
                counts[cls][1] += recent and not gone
            else:
                add, drop = TAGS[cls]
                counts[cls][1] += 1
            ops = [f"+{t}" for t in sorted(add - tags)] + [f"-{t}" for t in sorted(drop & tags)]
            if ops:
                batch.append(" ".join(ops) + " -- " + E.idq(m["id"]) + "\n")
                after[m["id"]] = (tags | add) - drop

    rules, movable = folder_rules()
    enabled = {"INBOX", *read_lines("foldersync.db")}
    moves = Counter()
    for ms in by_sender.values():
        for m in ms:
            files = [p for p in m.get("filename", []) if p.startswith(store + "/")]
            if len(files) != 1:
                continue
            folder = os.path.dirname(os.path.dirname(os.path.relpath(files[0], store)))
            if folder not in movable:
                continue
            tags = after.get(m["id"], set(m["tags"]))
            to = next((f for f, terms in rules if holds(terms, tags)), None)
            if to in enabled and to != folder:
                moves[(folder, to)] += 1
    return {"counts": counts, "already": already, "lines": lines, "screener": screener, "batch": batch, "moves": moves}


def report(p, applied):
    c = p["counts"]
    out = ["mail seed: applied" if applied else "mail seed: dry run, nothing changed; mail seed --apply writes this"]
    for label, kinds in LABELS:
        out.append(f"{label}: {sum(c[k][0] for k in kinds)} senders, {sum(c[k][1] for k in kinds)} messages")
    out.append(f"already decided: {p['already']} senders")
    out += [f"{db} {line}" for db, line, _ in p["lines"]]
    out += [f"screener {s}" for s in p["screener"]]
    moves = sorted(p["moves"].items(), key=lambda kv: (-kv[1], kv[0]))
    out += [f"{n:>3}  {src} -> {to}" for (src, to), n in moves]
    out.append(f"HEY/Read moves: {sum(n for (src, _), n in moves if src == 'HEY/Read')}")
    return "\n".join(out) + "\n"


def lock():
    """Hold mail-sync's lock, as dots-sync-mail does, so neither post-new nor hey-folder-sync runs mid-apply."""
    state = os.path.join(os.environ.get("XDG_STATE_HOME") or E.HOME + "/.local/state", "hey-mail")
    os.makedirs(state, exist_ok=True)
    fd = os.open(os.path.join(state, "sync.lock"), os.O_WRONLY | os.O_CREAT, 0o644)
    for _ in range(300):
        try:
            fcntl.flock(fd, fcntl.LOCK_EX | fcntl.LOCK_NB)
            return fd
        except BlockingIOError:
            time.sleep(1)
    os.close(fd)
    raise E.MailError("a mail sync held its lock for 5 minutes, so seed changed nothing")


def run(apply=False):
    """The report of a dry run, or with APPLY the report of what it wrote, or `nothing to change`."""
    if not apply:
        return report(plan(), False)
    fd = lock()
    try:
        p = plan()
        if not p["batch"] and not p["lines"]:
            return "nothing to change\n"
        if p["batch"]:
            E.nm("tag", "--batch", stdin="".join(p["batch"]))
        for db, line, _ in p["lines"]:
            E.db_add(db, line)
        for _, _, key in p["lines"]:
            E.stamp("sender " + key)
        E.refresh_count()
        return report(p, True)
    finally:
        os.close(fd)
