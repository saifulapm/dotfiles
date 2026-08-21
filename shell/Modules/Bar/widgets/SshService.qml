import QtQuick
import Quickshell
import Quickshell.Io
import "SshModel.js" as Model

// SSH service — the host list behind the ssh widget and panel. ONE instance
// however many screens carry the widget (S2); it is created at the bar root.
//
// Nothing here polls. The list changes exactly when ~/.ssh/config does, so a
// FileView watcher on that file is the whole cadence (DufsService's flag-file
// pattern), plus the usual one-shot probes at startup and panel open.
//
// UPSTREAM DIFFERENCE, deliberate: omassh also re-reads on a timer to catch
// edits inside `Include`d files, which a single watcher cannot see. This shell
// does not get to do that — no polling is the rule, and a timer covering the
// rare case of an included file edited while the panel is shut is exactly the
// kind of cadence the rule exists to refuse. Panel-open re-reads everything
// anyway, so the worst case is a stale list in a panel nobody has opened.
//
// The reading itself is bin/ssh-hosts: alias collection, Include following,
// and `ssh -G` resolution live there, and SshModel.js does the ranking. This
// file is the wiring between them.
QtObject {
    id: root

    // The presence probe has answered at least once. Until then the widget
    // draws nothing rather than flashing an icon it will take back.
    property bool probed: false
    // There is an ssh config with at least one literal host in it. A machine
    // with none keeps the widget in the registry but gives it no width.
    property bool available: false

    // Model.parseRows output, newest listing wins. Replaced wholesale, never
    // mutated, so the derived bindings fire.
    property var hosts: []

    readonly property int hostCount: hosts.length
    readonly property string tooltip: Model.tooltipText(hosts)

    readonly property string configPath: Quickshell.env("HOME") + "/.ssh/config"

    property bool refreshing: false
    property string lastError: ""

    // Which terminal a connection opens in. bin/foot-run is the wrapper the
    // rest of the shell launches terminals through (it reuses the foot
    // server, so a window costs 5 ms rather than 135).
    readonly property string terminal: "foot-run"

    property string _output: ""
    property string _error: ""

    function refresh() {
        if (listProcess.running)
            return;
        _output = "";
        _error = "";
        refreshing = true;
        listProcess.running = true;
    }

    function applyList(raw) {
        const parsed = Model.parseRows(raw);
        probed = true;
        // A config that exists but declares only `Host *` is the same as no
        // config for this widget's purposes: there is nothing to connect to.
        // Git-forge aliases count for nothing here either — they answer SSH
        // but never give you a shell, so a config holding only those leaves
        // this widget with no reason to be on the bar.
        available = Model.shellHostCount(parsed) > 0;
        hosts = parsed;
        lastError = "";
    }

    // The rows the panel draws for a query.
    function ranked(query) {
        return Model.rank(hosts, query);
    }

    // ------------------------------------------------------------- actions
    // Open a terminal on the host, and record the use so it sorts to the top
    // next time. Two processes rather than one shell line: the recording must
    // not be able to affect the connection, and neither string is ever handed
    // to a shell to re-split (Model.connectCommand documents the `--`).
    function connect(host) {
        if (!host || !host.alias)
            return;
        const command = Model.connectCommand(host, terminal);
        if (command.length === 0)
            return;
        Quickshell.execDetached(command);
        Quickshell.execDetached(["ssh-hosts", "--used", String(host.alias)]);
        // Reflect the new recency without waiting for a re-read: the panel is
        // usually closing on this click, and the next open should already
        // show the host at the top.
        touch(host.alias);
    }

    // Bump one host's lastUsed in the in-memory list, to the same clock
    // bin/ssh-hosts writes (epoch SECONDS, not milliseconds — a millisecond
    // value here would outrank every real entry forever).
    function touch(alias) {
        const now = Math.floor(Date.now() / 1000);
        hosts = hosts.map(host => host.alias === alias ? Object.assign({}, host, {
                lastUsed: now
            }) : host);
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // --------------------------------------------------------- the processes
    // One `ssh -G` per alias, all of it inside bin/ssh-hosts — 86 ms for
    // seven hosts on this machine, and it opens no connection.
    readonly property Process listProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "ssh-hosts"]
        stdout: StdioCollector {
            id: listStdout
            waitForEnd: true
            onStreamFinished: root._output = text
        }
        stderr: StdioCollector {
            id: listStderr
            waitForEnd: true
            onStreamFinished: root._error = text
        }
        onExited: exitCode => {
            root.refreshing = false;
            const out = String(listStdout.text || root._output || "");
            const err = String(listStderr.text || root._error || "");
            if (exitCode === 0) {
                root.applyList(out);
            } else {
                root.probed = true;
                root.lastError = root.elideStatus(err || "Could not read ~/.ssh/config");
            }
        }
    }

    // The cadence, such as it is: the config file itself. `watchChanges` plus
    // an explicit reload() at startup, because the view stays unloaded (and
    // neither signal ever fires) until something reads it — DufsService
    // documents the same trap.
    //
    // The content is not used; only the fact that it changed. Re-reading goes
    // through bin/ssh-hosts, which knows about Include files this view cannot
    // see.
    readonly property FileView configFile: FileView {
        path: root.configPath
        watchChanges: true
        onFileChanged: {
            reload();
            root.refresh();
        }
        // An unreadable or absent config is a legitimate machine state, and
        // the probe below reports it properly — nothing to do here.
        onLoadFailed: root.probed = true
        Component.onCompleted: reload()
    }

    Component.onCompleted: refresh()
}
