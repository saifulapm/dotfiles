import QtQuick
import Quickshell
import Quickshell.Io
import "NightLightModel.js" as Model

// Night-light service — everything the nightlight widget and panel read
// about sunsetr. ONE instance however many screens carry the widget (S2); it
// is created at the bar root.
//
// NOTHING HERE POLLS, and the feature made that easy rather than hard:
// `sunsetr status --json --follow` is a long-lived process that prints one
// compact JSON object per state change and nothing in between, so a
// SplitParser over its stdout is the entire cadence — DictationService's
// shape, and DevServicesService's busctl follower's. A colour temperature
// that moves once at dusk would have been the obvious thing to poll for; it
// never has to be.
//
// The one-shot probe (startup, panel open, explicit refresh) answers two
// questions the stream cannot: whether sunsetr is installed at all, and what
// `day_temp` is — the threshold everything warm/neutral is measured against,
// which lives in the config rather than in the status payload.
//
// Actions go through bin/nightlight rather than `sunsetr preset` directly.
// That script owns the toggle policy (a hold releases to auto; auto forces
// the opposite of the current state), and having the keybinding and the
// panel share one implementation is what keeps them from drifting apart.
// Every child is wrapped in `setpriv --pdeathsig TERM` — quickshell does not
// signal Process children when the shell exits, and the follower would
// otherwise outlive us indefinitely.
QtObject {
    id: root

    // The presence probe has answered at least once. Until then the widget
    // draws nothing rather than flashing an icon it will take back.
    property bool probed: false
    // sunsetr is installed on this machine. False closes the gate for good:
    // the widget stays in the registry so "nightlight" can be added to a bar
    // section, and takes no width anywhere it would have nothing to say.
    property bool available: false
    // The daemon is up and answering. Unlike `available` this comes and
    // goes — the unit is Requisite=graphical-session.target, and it can be
    // stopped by hand.
    property bool running: false

    // Last state the stream (or the probe) reported. Replaced wholesale,
    // never mutated, so the derived bindings below fire.
    property var state: ({})
    // From `sunsetr get day_temp`: the neutral point this machine is
    // configured for, and therefore what "warm" means here. Model falls back
    // to 6500 until the probe answers.
    property int dayTemp: Model.DEFAULT_DAY_TEMP

    readonly property bool warm: running && Model.isWarm(state, dayTemp)
    readonly property bool forced: running && Model.isForced(state)
    readonly property string modeKey: running ? Model.activeModeKey(state) : "auto"
    readonly property bool transitioning: running && Model.isTransitioning(state)
    readonly property int temp: Number(state.temp) || 0

    readonly property string tooltip: Model.tooltipText(state, dayTemp, running)
    readonly property string heroMeta: Model.heroMeta(state, dayTemp, running)
    readonly property string nextText: running ? Model.nextTransitionText(state, dayTemp) : ""
    readonly property string toggleLabel: Model.toggleLabel(state, dayTemp)

    property bool refreshing: false
    property string lastError: ""

    // Escalating restart budget for the follower. Deliberately not a fixed
    // short delay: the shell and sunsetr.service both start at
    // graphical-session.target, so the first follow attempt of a session can
    // legitimately land before the daemon is answering. A flat 5x3s would
    // burn the whole budget inside the startup race and then declare the
    // feature off exactly as it came up. These five cover ~60 s instead, and
    // any successful connection refills them.
    readonly property var _retryDelays: [1000, 2000, 5000, 15000, 30000]
    property int _retries: 0
    property string _probeOutput: ""
    property string _probeError: ""
    property string _actionError: ""

    // Presence + day_temp + one state snapshot, in a single process.
    // Startup, panel open and explicit refresh only — there is no timer
    // anywhere in this file except the follower's restart delay.
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

    // key<TAB>value lines, bin/system-stats' shape. `status` is absent
    // entirely when no daemon is answering, which is how `running` is
    // decided — an empty value would be indistinguishable from a failure.
    function applyProbe(raw) {
        probed = true;
        available = true;
        let sawStatus = false;
        for (const line of String(raw || "").split("\n")) {
            const tab = line.indexOf("\t");
            if (tab <= 0)
                continue;
            const key = line.substring(0, tab);
            const value = line.substring(tab + 1);
            if (key === "day_temp") {
                const parsed = parseInt(value, 10);
                if (isFinite(parsed) && parsed > 0)
                    dayTemp = parsed;
            } else if (key === "status") {
                const event = Model.parseEvent(value);
                if (event && event.kind === "state") {
                    state = event;
                    sawStatus = true;
                }
            }
        }
        running = sawStatus;
        if (sawStatus) {
            lastError = "";
            ensureFollower();
        }
    }

    // One follower line. A config echo carries target values rather than
    // applied ones, so it is deliberately NOT written into `state`: the
    // display has not moved yet, and the `state_applied` that follows it
    // within the same fade is what says it has.
    function applyEvent(line) {
        const event = Model.parseEvent(line);
        if (!event)
            return;
        _retries = 0;
        if (event.kind !== "state")
            return;
        state = event;
        running = true;
        lastError = "";
    }

    function ensureFollower() {
        if (!available || followProcess.running)
            return;
        // A fresh probe re-arms a follower that gave up — the manual
        // recovery path behind right-click and panel open.
        _retries = 0;
        followProcess.running = true;
    }

    // ------------------------------------------------------------- actions
    // Every one of these is bin/nightlight, which starts the unit itself if
    // it has to. The probe that follows squares us with whatever happened;
    // the follower normally beats it to the answer.
    function setMode(key) {
        if (!available)
            return;
        runAction([key === "auto" ? "auto" : key]);
    }

    function toggle() {
        if (!available)
            return;
        runAction(["toggle"]);
    }

    function turnOn() {
        if (!available)
            return;
        // `status` on a stopped daemon is a clean "off" and starts nothing;
        // `auto` is the cheapest verb that does start it.
        runAction(["auto"]);
    }

    function turnOff() {
        if (!available)
            return;
        // Straight to systemd: bin/nightlight has no "stop" verb on purpose
        // (it exists to put the filter somewhere, not to take the daemon
        // away), and this is the one place that wants it.
        runAction([], ["systemctl", "--user", "stop", "sunsetr.service"]);
    }

    // Nudge the night temperature by a step, persisted into the config the
    // way `sunsetr set` does. Only meaningful while the schedule or the
    // night hold is in charge — the panel hides the control under a day
    // hold, where it would change nothing visible.
    function nudgeNightTemp(delta) {
        if (!available || !running)
            return;
        const op = delta >= 0 ? "+=" : "-=";
        runAction([], ["sunsetr", "set", "night_temp" + op + Math.abs(delta)]);
    }

    function runAction(nightlightArgs, rawCommand) {
        if (actionProcess.running)
            return;
        _actionError = "";
        actionProcess.command = ["setpriv", "--pdeathsig", "TERM", "--"].concat(rawCommand !== undefined ? rawCommand : ["nightlight"].concat(nightlightArgs));
        actionProcess.running = true;
    }

    function elideStatus(text) {
        const value = String(text || "").replace(/\s+/g, " ").trim();
        return value.length > 140 ? value.substring(0, 137) + "…" : value;
    }

    // ----------------------------------------------------------- the clocks
    // The only timer in this file, and it is a reconnect delay rather than a
    // cadence: it fires once per follower death, at an escalating interval,
    // and stops for good once the budget is spent.
    readonly property Timer followRestartTimer: Timer {
        interval: 1000
        repeat: false
        onTriggered: {
            if (root.available && !root.followProcess.running)
                root.followProcess.running = true;
        }
    }

    // --------------------------------------------------------- the processes
    // Asked unconditionally once: is this a machine with sunsetr, what is
    // its neutral point, and is the daemon answering? Exit 3 = "no sunsetr
    // here", quietly and permanently.
    //
    // `status --json` is pretty-printed, so it is flattened to one line with
    // tr before being tagged — the key<TAB>value contract is per line, and a
    // multi-line value would break it.
    readonly property Process probeProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", "export PATH=\"$HOME/.cargo/bin:$PATH\"; command -v sunsetr >/dev/null 2>&1 || exit 3; printf 'day_temp\\t%s\\n' \"$(sunsetr get day_temp 2>/dev/null | tr -cd '0-9')\"; status=$(sunsetr status --json 2>/dev/null | tr -d '\\n'); [ -n \"$status\" ] && printf 'status\\t%s\\n' \"$status\"; exit 0"]
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
                // Not this machine. The gate closes for good.
                root.probed = true;
                root.available = false;
                root.running = false;
            } else {
                root.probed = true;
                root.lastError = root.elideStatus(err || out || "Could not probe sunsetr");
            }
        }
    }

    // The whole event source. Exits immediately and non-zero when no daemon
    // is answering, which is the normal state before sunsetr.service comes
    // up — hence the escalating budget rather than a tight retry.
    readonly property Process followProcess: Process {
        running: false
        command: ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", "export PATH=\"$HOME/.cargo/bin:$PATH\"; exec sunsetr status --json --follow"]
        stdout: SplitParser {
            onRead: line => root.applyEvent(line)
        }
        onExited: {
            // The stream is the only thing that knows the daemon is alive;
            // losing it means we no longer know, so say so rather than
            // leaving a stale temperature on the bar.
            root.running = false;
            if (!root.available)
                return;
            if (root._retries >= root._retryDelays.length) {
                root.lastError = "sunsetr is not running";
                return;
            }
            root.followRestartTimer.interval = root._retryDelays[root._retries];
            root._retries += 1;
            root.followRestartTimer.restart();
        }
    }

    readonly property Process actionProcess: Process {
        running: false
        command: []
        stdout: StdioCollector {
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: actionStderr
            waitForEnd: true
            onStreamFinished: root._actionError = text
        }
        onExited: exitCode => {
            if (exitCode !== 0)
                root.lastError = root.elideStatus(root._actionError || "nightlight command failed");
            else
                root.lastError = "";
            // An action that started or stopped the daemon changes whether
            // there is a stream to follow at all, so re-arm and re-probe.
            root.ensureFollower();
            root.refresh();
        }
    }

    Component.onCompleted: refresh()
}
