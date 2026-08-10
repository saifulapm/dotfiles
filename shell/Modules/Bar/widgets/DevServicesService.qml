import QtQuick
import Quickshell
import Quickshell.Io
import "DevServicesModel.js" as Model

// Dev-services service — ours, in the shape of omarchy's dropbox service
// (CREDITS.md):
// it owns everything the widget and the panel read about the on-demand dev
// databases (podman quadlet containers behind systemd-socket-proxyd; the
// catalog and lifecycle live in DevServicesModel.js). ONE instance however
// many screens carry the widget (S2) — it is created at the bar root.
//
// State observation is event-driven, never polled: a long-lived
// `busctl --user monitor` follower on systemd's JobRemoved signal is the
// whole cadence, DictationService's pattern. Every transition here IS a
// systemd job (socket wakes proxy, proxy's Requires= raises the container,
// StopWhenUnneeded lowers it), so the bus sees all of them. A job says which
// unit moved but not where to, so a recognized signal schedules the probe
// rather than being applied — the probe stays the only thing that decides
// state. The other one-shot probes are the startup presence check and the
// panel-open refresh — probe-on-open is the family-sanctioned pattern
// (Dropbox, rclone remotes).
//
// Actions are systemctl verbs on the USER units. Start raises the container
// AND its proxy service (the proxy holds the container up until its usual
// 10-minute idle exit; a bare container start would be reaped at the next
// StopWhenUnneeded evaluation). Stop lowers the proxies then the container.
// Sockets are never touched — the ports stay armed. Commands run through a
// small queue rather than a guarded single Process: a health-gated MySQL
// start blocks systemctl for up to ~30 s, and that must not swallow a click
// on another row. Every child is wrapped in `setpriv --pdeathsig TERM`
// (quickshell does not signal Process children when the shell exits, and the
// follower would otherwise outlive us indefinitely).
//
// That wrapper only started working when the follower stopped being podman.
// PDEATHSIG is cleared across fork, and rootless podman re-execs itself into
// a user namespace — so the process setpriv armed was never the one left
// holding the stream, and a SIGKILLed shell leaked a 53 MB `podman events`
// every time (five of them found running at once on 2026-08-10, from a
// morning of dev-instance testing). busctl does not fork: verified by
// SIGKILLing the shell and watching the follower go with it.
QtObject {
    id: root

    // The presence probe has answered at least once. Until then the widget
    // shows nothing at all, rather than flashing an icon it will take back.
    property bool probed: false
    // podman exists and the proxy socket units are installed on this machine.
    property bool available: false

    // Container name → true while running. Replaced wholesale by the probe
    // snapshot, patched per event line; always reassigned, never mutated, so
    // the derived bindings below fire.
    property var runningContainers: ({})
    // Service key → "starting" | "stopping" while an action settles. The
    // matching podman event clears it; a failed systemctl or the expiry
    // sweep clears a pending reality never confirms.
    property var pendingByKey: ({})

    // The per-service rows the widget and the panel render.
    readonly property var services: Model.SERVICES.map(def => ({
                key: def.key,
                label: def.label,
                container: def.container,
                portLabel: def.portLabel,
                glyph: def.glyph,
                webUrl: def.webUrl,
                running: root.runningContainers[def.container] === true,
                pending: root.pendingByKey[def.key] || ""
            }))

    readonly property int serviceCount: Model.SERVICES.length
    readonly property int runningCount: services.filter(s => s.running).length

    property bool refreshing: false
    property string lastError: ""

    property var _queue: []
    property string _controlKey: ""
    property int _eventRetries: 0
    property string _probeOutput: ""
    property string _probeError: ""
    property string _controlError: ""

    // Presence + a `podman ps` snapshot. Startup, panel open, and explicit
    // refresh only — there is no timer anywhere in this file.
    function refresh() {
        if (probed && !available)
            return;
        if (probeProcess.running)
            return;
        _probeOutput = "";
        _probeError = "";
        refreshing = true;
        probeProcess.running = true;
    }

    function applyProbe(raw) {
        const parsed = Model.parseProbe(raw);
        probed = true;
        available = parsed.available;
        if (!available)
            return;
        runningContainers = parsed.running;
        reconcilePending();
        lastError = "";
        ensureFollower();
    }

    // Clear any pending whose desired state reality already reports.
    function reconcilePending() {
        for (const def of Model.SERVICES) {
            const pending = pendingByKey[def.key];
            if (pending === undefined)
                continue;
            const running = runningContainers[def.container] === true;
            if ((pending === "starting" && running) || (pending === "stopping" && !running))
                clearPending(def.key);
        }
    }

    // One follower line. A JobRemoved names the unit that moved but not what
    // it moved to, so this schedules a probe rather than applying anything —
    // see Model.parseUnitEvent for why that is the trade. Any recognized line
    // also proves the follower is healthy, so the restart budget refills.
    function applyEvent(line) {
        const unit = Model.parseUnitEvent(line);
        if (!unit)
            return;
        _eventRetries = 0;
        // One wake runs jobs for the socket, the proxy and the container, so
        // the signals arrive in a burst; coalesce them into a single probe.
        eventProbeDebounce.restart();
    }

    function setRunning(container, on) {
        const next = {};
        for (const k in runningContainers)
            next[k] = runningContainers[k];
        if (on)
            next[container] = true;
        else
            delete next[container];
        runningContainers = next;
        const def = Model.SERVICES.find(d => d.container === container);
        if (def && pendingByKey[def.key] === (on ? "starting" : "stopping"))
            clearPending(def.key);
    }

    function setPending(key, kind) {
        const next = {};
        for (const k in pendingByKey)
            next[k] = pendingByKey[k];
        next[key] = kind;
        pendingByKey = next;
        pendingExpiry.restart();
    }

    function clearPending(key) {
        if (pendingByKey[key] === undefined)
            return;
        const next = {};
        for (const k in pendingByKey) {
            if (k !== key)
                next[k] = pendingByKey[k];
        }
        pendingByKey = next;
    }

    // ------------------------------------------------------------- actions
    function startService(key) {
        const def = Model.SERVICES.find(d => d.key === key);
        if (!def || !available)
            return;
        setPending(key, "starting");
        queueControl(["systemctl", "--user", "start"].concat(def.startUnits), key);
    }

    function stopService(key) {
        const def = Model.SERVICES.find(d => d.key === key);
        if (!def || !available)
            return;
        setPending(key, "stopping");
        queueControl(["systemctl", "--user", "stop"].concat(def.stopUnits), key);
    }

    function toggleService(svc) {
        if (!svc || svc.pending !== "")
            return;
        if (svc.running)
            stopService(svc.key);
        else
            startService(svc.key);
    }

    // Running services only: the web socket could wake mailpit by itself,
    // but the affordance would read as "already up" — the row's Start is the
    // deliberate warm-up.
    function openWeb(svc) {
        if (!svc || svc.webUrl === "" || !svc.running)
            return;
        Quickshell.execDetached(["xdg-open", svc.webUrl]);
    }

    function queueControl(command, key) {
        _queue.push({
            command: ["setpriv", "--pdeathsig", "TERM", "--"].concat(command),
            key: key
        });
        pumpQueue();
    }

    function pumpQueue() {
        if (controlProcess.running || _queue.length === 0)
            return;
        const job = _queue.shift();
        _controlKey = job.key;
        _controlError = "";
        controlProcess.command = job.command;
        controlProcess.running = true;
    }

    function ensureFollower() {
        if (!available || eventsProcess.running)
            return;
        // A fresh probe re-arms a follower that gave up — the manual
        // recovery path behind right-click / panel open.
        _eventRetries = 0;
        eventsProcess.running = true;
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // ------------------------------------------------------------ the clocks
    // No periodic timer: only the pending failsafe and the follower restart
    // delay. A pending is normally cleared by its podman event within
    // seconds; whatever is left after this long is stuck, and the rows must
    // not read "Starting…" forever.
    readonly property Timer pendingExpiry: Timer {
        interval: 45000
        repeat: false
        onTriggered: root.pendingByKey = ({})
    }

    // Coalesces a burst of JobRemoved signals into one probe. Long enough to
    // cover socket → proxy → container, short enough that a dot lights up
    // while the user is still looking at it.
    readonly property Timer eventProbeDebounce: Timer {
        interval: 400
        repeat: false
        onTriggered: root.refresh()
    }

    readonly property Timer eventsRestartTimer: Timer {
        interval: 3000
        repeat: false
        onTriggered: {
            if (root.available && !root.eventsProcess.running)
                root.eventsProcess.running = true;
        }
    }

    // --------------------------------------------------------- the processes
    // The one question asked unconditionally, and its cost is one podman ps:
    // is this the machine with the on-demand stack? Exit 3 = "no", quietly.
    readonly property Process probeProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", "command -v podman >/dev/null 2>&1 || exit 3; systemctl --user list-unit-files mysql84-proxy.socket >/dev/null 2>&1 || exit 3; echo OK; exec podman ps --format '{{.Names}}'"]
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
            const out = String(probeStdout.text || root._probeOutput || "");
            const err = String(probeStderr.text || root._probeError || "");
            if (exitCode === 0) {
                root.applyProbe(out);
            } else if (exitCode === 3) {
                // Not this machine. The gate closes for good, like the
                // dropbox widget's on a missing CLI.
                root.probed = true;
                root.available = false;
            } else {
                root.probed = true;
                root.lastError = root.elideStatus(err || out || "Could not probe dev services");
            }
        }
    }

    // The whole event source: every systemd job completion on the session
    // bus, filtered down to ours as it arrives. Started once the probe says
    // the stack exists; restarted with a short delay if it drops, up to a
    // small budget so a broken bus cannot turn the restart into a poll — any
    // recognized line, or the next probe, refills the budget.
    //
    // This was `podman events` until it was measured: 53.5 MB resident to
    // watch four containers that are stopped almost always, against 5.6 MB
    // here. Both are event-driven; only the runtime differs (Go vs C).
    readonly property Process eventsProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "busctl", "--user", "monitor", "--json=short", "--match", "type='signal',sender='org.freedesktop.systemd1',interface='org.freedesktop.systemd1.Manager',member='JobRemoved'"]
        stdout: SplitParser {
            onRead: line => root.applyEvent(line)
        }
        onExited: {
            if (!root.available)
                return;
            if (root._eventRetries >= 5) {
                root.lastError = "systemd job follower stopped — refresh to reconnect";
                return;
            }
            root._eventRetries += 1;
            root.eventsRestartTimer.restart();
        }
    }

    readonly property Process controlProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: controlStderr
            waitForEnd: true
            onStreamFinished: root._controlError = text
        }
        onExited: exitCode => {
            if (exitCode !== 0) {
                root.lastError = root.elideStatus(root._controlError || "systemctl command failed");
                root.clearPending(root._controlKey);
            } else {
                root.lastError = "";
            }
            root._controlKey = "";
            root.pumpQueue();
        }
    }

    Component.onCompleted: refresh()
}
