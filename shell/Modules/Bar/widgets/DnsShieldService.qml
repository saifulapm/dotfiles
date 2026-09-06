import QtQuick
import Quickshell
import Quickshell.Io
import "DnsShieldModel.js" as Model

// DNS Shield service — owns everything the widget and panel read about the
// family DNS helper (see DnsShieldModel.js for the chain). ONE instance
// however many screens carry the widget (S2) — created at the bar root.
//
// Probe-on-open only, the family-sanctioned cadence (Dropbox, DevServices):
// startup presence check, panel open, right-click. No follower — the chain
// has no user-session event source (system units, not user units), and a
// system-bus monitor for two services that change a few times a month is not
// worth a resident process. The live block test inside the probe is the real
// health signal anyway.
//
// The probe is one bash child wrapped in `setpriv --pdeathsig TERM` like
// every long-running family child; it exits 3 on machines without the
// helper unit, which closes the gate for good (DevServices' pattern).
QtObject {
    id: root

    readonly property string helper: Quickshell.env("HOME") + "/.dotfiles/bin/dns-filter"

    property bool probed: false
    property bool available: false
    property bool refreshing: false
    property string lastError: ""

    // The parsed probe snapshot, or null before the first answer.
    property var state: null

    readonly property bool healthy: state !== null && Model.chainHealthy(state)

    // Is THIS machine actually resolving through the filter right now — the
    // header's right-hand verdict, and all that survives of the five CHAIN
    // rows the panel used to carry.
    readonly property var deviceStatus: Model.deviceStatus(state)

    // The uBlockDNS category toggles, read from `dns-filter status --json`.
    // Its own probe and its own error string: this one talks to the network,
    // and a uBlockDNS outage must degrade the toggles WITHOUT making the
    // local chain rows — which are still perfectly knowable — look broken.
    property var filters: null
    property bool filtersRefreshing: false
    property string filtersError: ""

    // The category with a write in flight, so the panel can dim exactly that
    // row. One at a time by design: dns-filter serialises on a lock anyway,
    // and every write is a read-modify-write of one shared config object.
    property string pending: ""

    readonly property var categories: Model.categoryRows(filters)

    property string _probeOutput: ""
    property string _probeError: ""
    property string _filtersOutput: ""
    property string _filtersError: ""
    property bool _refreshQueued: false

    function refresh() {
        refreshFilters();
        if (probed && !available)
            return;
        if (probeProcess.running)
            return;
        _probeOutput = "";
        _probeError = "";
        refreshing = true;
        probeProcess.running = true;
    }

    function refreshFilters() {
        // Gated on the same "is this a helper machine" answer as the chain: a
        // box with no profile has nothing to toggle, and dns-filter would only
        // say so once per open.
        if (probed && !available)
            return;
        // A second read while one is in flight is remembered, not dropped: the
        // refresh that follows a write MUST happen, and dropping it silently
        // left the switch showing the state from before the change.
        if (filtersProcess.running) {
            _refreshQueued = true;
            return;
        }
        _filtersOutput = "";
        _filtersError = "";
        filtersRefreshing = true;
        filtersProcess.running = true;
    }

    // block = true  → start blocking again, and cancel any timer
    // block = false → stop blocking; seconds > 0 makes it temporary
    //
    // Deliberately NOT gated on filtersProcess: opening the panel fires a
    // network read, and gating writes on it made every click in the first
    // second after opening do nothing at all, silently (found on the first
    // click test, 2026-09-06). A read in flight cannot invalidate a write —
    // dns-filter serialises on its own lock, and the write re-reads when it
    // lands — so the only thing worth refusing is a second concurrent write.
    function setCategory(id, block, seconds) {
        if (id === "" || actionProcess.running)
            return;
        const args = block ? ["on", id] : ["off", id];
        if (!block && seconds > 0)
            args.push(seconds + "s");
        root.pending = id;
        root.filtersError = "";
        actionProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", root.helper].concat(args);
        actionProcess.running = true;
    }

    // The allowlist. Same one-writer-at-a-time rule as the categories — they
    // all end up in the same custom_rules array, and dns-filter re-reads the
    // whole config before every write.
    function allowDomain(domain) {
        const value = String(domain || "").trim();
        if (value === "" || actionProcess.running)
            return;
        root.pending = value;
        root.filtersError = "";
        actionProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", root.helper, "allow", value];
        actionProcess.running = true;
    }

    function unallowDomain(domain) {
        const value = String(domain || "").trim();
        if (value === "" || actionProcess.running)
            return;
        root.pending = value;
        root.filtersError = "";
        actionProcess.command = ["setpriv", "--pdeathsig", "TERM", "--", root.helper, "unallow", value];
        actionProcess.running = true;
    }

    function toggleCategory(id) {
        const row = root.categories.find(c => c.id === id);
        if (!row)
            return;
        setCategory(id, !row.on, 0);
    }

    function openDashboard() {
        Quickshell.execDetached(["xdg-open", Model.DASHBOARD_URL]);
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // The one probe: unit presence gate, then every fact the model renders.
    // dig gets one second and one try — the panel opens instantly and a
    // hung client reads as "No answer", which is itself the diagnosis.
    readonly property Process probeProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", "systemctl cat ublockdns.service >/dev/null 2>&1 || exit 3; " + "echo client=$(systemctl is-active ublockdns 2>/dev/null); " + "echo dnsmasq=$(systemctl is-active dnsmasq 2>/dev/null); " + "b=$(ss -lnu 2>/dev/null); " + "case \"$b\" in *'127.0.0.1:53 '*) echo bind_client=yes;; *) echo bind_client=no;; esac; " + "case \"$b\" in *'127.0.0.2:53 '*) echo bind_fwd=yes;; *) echo bind_fwd=no;; esac; " + "iface=$(head -1 \"$HOME/.config/dns-helper/serve\" 2>/dev/null | tr -cd 'a-z0-9'); " + "cur=; [ -n \"$iface\" ] && cur=$(ip -4 addr show \"$iface\" 2>/dev/null | grep -oE 'inet [0-9.]+' | head -1 | cut -d' ' -f2); " + "echo lan_ips=$cur; " + "bound=; [ -n \"$cur\" ] && case \"$b\" in *\"$cur:53 \"*) bound=$cur;; esac; " + "echo lan_bound=$bound; " + "dev=$(ip route get 1.1.1.1 2>/dev/null | sed -n 's/.*dev \\([^ ]*\\).*/\\1/p' | head -1); " + "echo laptop_dns=$(resolvectl status $dev 2>/dev/null | sed -n 's/.*Current DNS Server: //p' | head -1); " + "echo block_test=$(dig @127.0.0.1 doubleclick.net +short +time=1 +tries=1 2>/dev/null | head -1)"]
        stdout: StdioCollector {
            id: probeStdout
            waitForEnd: true
            onStreamFinished: root._probeOutput = text
        }
        stderr: StdioCollector {
            id: probeStderr
            waitForEnd: true
            onStreamFinished: root._probeError = text
        }
        onExited: exitCode => {
            root.refreshing = false;
            root.probed = true;
            const out = String(probeStdout.text || root._probeOutput || "");
            const err = String(probeStderr.text || root._probeError || "");
            if (exitCode === 0) {
                root.available = true;
                root.state = Model.parseProbe(out);
                root.lastError = "";
            } else if (exitCode === 3) {
                // Not the helper machine — inert for good, no width, no probe.
                root.available = false;
            } else {
                root.lastError = root.elideStatus(err || out || "Could not probe the DNS helper");
            }
        }
    }

    // Reading the toggles. Separate from the chain probe so a slow round trip
    // to uBlockDNS never delays the rows that are knowable locally.
    readonly property Process filtersProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", root.helper, "status", "--json"]
        stdout: StdioCollector {
            id: filtersStdout
            waitForEnd: true
            onStreamFinished: root._filtersOutput = text
        }
        stderr: StdioCollector {
            id: filtersStderr
            waitForEnd: true
            onStreamFinished: root._filtersError = text
        }
        onExited: exitCode => {
            root.filtersRefreshing = false;
            const out = String(filtersStdout.text || root._filtersOutput || "");
            const err = String(filtersStderr.text || root._filtersError || "");
            const parsed = Model.parseFilters(out);
            if (parsed !== null) {
                // Covers ok:false too — dns-filter puts its own message in
                // .error, which is more specific than anything we'd invent.
                root.filters = parsed;
                root.filtersError = parsed.ok ? "" : root.elideStatus(parsed.error);
            } else {
                root.filters = null;
                root.filtersError = root.elideStatus(err || out || "Could not read the filters (exit " + exitCode + ")");
            }
            if (root._refreshQueued) {
                root._refreshQueued = false;
                root.refreshFilters();
            }
        }
    }

    // Writing one. Re-reads afterwards rather than trusting the write: the
    // config is shared with the dashboard and the other machines, so the
    // server's answer is the only honest source for what the switch now shows.
    readonly property Process actionProcess: Process {
        running: false
        stderr: StdioCollector {
            id: actionStderr
            waitForEnd: true
            onStreamFinished: root._filtersError = text
        }
        onExited: exitCode => {
            const err = String(actionStderr.text || root._filtersError || "");
            root.pending = "";
            if (exitCode !== 0)
                root.filtersError = root.elideStatus(err || "Could not change the filter (exit " + exitCode + ")");
            root.refreshFilters();
        }
    }

    Component.onCompleted: refresh()
}
