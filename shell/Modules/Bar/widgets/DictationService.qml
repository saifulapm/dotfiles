import QtQuick
import Quickshell
import Quickshell.Io
import "DictationModel.js" as Model

// Voice dictation state, split out of the Dictation widget so ONE voxtype
// follower serves every screen (S2). The follower is the whole state source —
// `bin/voxtype-status` is our copy of omarchy-voxtype-status,
// i.e. `voxtype status --follow --format json` parsed line by line, one line
// per transition. Nothing polls and there is no cadence to gate, so the
// process runs for the life of the shell; it outlives a voxtype daemon
// restart (the state file does), and it exits only if voxtype is missing, in
// which case the helper has already printed one idle record.
//
// EVERYTHING ELSE HERE IS PANEL-GATED. The follower is all the bar indicator
// needs, and a shell where the dictation panel is never opened must not pay
// for the rest: the facts snapshot runs on open and after actions (never on a
// cadence), and the three history stores are only watched while `panelOpen`.
// The audio bridge is gated harder still — it only runs while the daemon is
// actually recording, which is the only time it has anything to say.
QtObject {
    id: root

    // "stopped" (no daemon) | "idle" | "recording" | "transcribing".
    property string dictationState: "idle"
    // voxtype's own first tooltip line ("Recording...", "Transcribing...").
    property string statusTooltip: ""

    readonly property bool recording: dictationState === "recording"
    readonly property bool busy: recording || dictationState === "transcribing"

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"
    readonly property string statePath: Quickshell.env("HOME") + "/.local/state/qshell/"

    // Set by the panel while it is on screen. Gates the facts snapshot and all
    // three file watches.
    property bool panelOpen: false

    // ------------------------------------------------------------ the stream
    // Upstream reads `alt` first and falls back to `class`; voxtype sets both.
    function update(raw) {
        let data = ({});
        try {
            data = JSON.parse(String(raw || "{}"));
        } catch (e) {
            return;
        }
        dictationState = String(data.alt || data.class || "idle");
        // The extended tooltip is several lines (model, device, backend); the
        // bar shows one, and the first line is the state in words.
        statusTooltip = String(data.tooltip || "").split("\n")[0];
    }

    readonly property Process follower: Process {
        command: [root.binDir + "voxtype-status"]
        running: true
        stdout: SplitParser {
            onRead: data => root.update(data)
        }
    }

    // ----------------------------------------------------------- the meeting
    // Meeting mode is a SECOND state machine: the daemon leaves `state` on
    // "idle" for the whole of a meeting and tracks it here instead — a
    // two-line file, `status\nmeeting_id`, rewritten on every transition.
    //
    // NOT panel-gated, unlike the history stores below. A meeting records for
    // an hour with nothing else on screen to say so, and the bar indicator is
    // the only thing that can. One small watched file is a fair price for
    // "you are being recorded" being visible.
    readonly property string runtimePath: (Quickshell.env("XDG_RUNTIME_DIR") || "/run/user/1000") + "/voxtype/"

    property string meetingState: "idle"
    readonly property bool meetingActive: meetingState === "recording" || meetingState === "paused"
    readonly property bool meetingRecording: meetingState === "recording"

    readonly property FileView meetingFile: FileView {
        path: root.runtimePath + "meeting_state"
        watchChanges: true
        printErrors: false
        onLoaded: root.meetingState = text().split("\n")[0].trim() || "idle"
        // The file does not exist until the first meeting ever started, which
        // is the ordinary state on a fresh machine, not a failure.
        onLoadFailed: root.meetingState = "idle"
        onFileChanged: reload()
    }

    // The file is created by the first `meeting start`, and a FileView pointed
    // at something that does not exist yet will not notice it appearing — so
    // the meeting actions below poke it rather than trusting the watch.
    readonly property Timer meetingSettle: Timer {
        interval: 700
        repeat: true
        triggeredOnStart: true
        // Runs only in the seconds after a meeting action; `stop` is
        // asynchronous (the daemon finishes its last chunk first), so a single
        // re-read would miss the transition back to idle.
        property int ticks: 0
        onTriggered: {
            root.meetingFile.reload();
            ticks += 1;
            if (ticks > 12)
                stop();
        }
    }

    function meeting(action) {
        run([binDir + "voxtype-meeting", action]);
        meetingSettle.ticks = 0;
        meetingSettle.restart();
    }

    // ------------------------------------------------------------- the facts
    // One JSON blob from bin/voxtype-facts: version, daemon and unit state,
    // engine/model/language, the choices the panel may offer, `info accel`,
    // and the capture hook's own status. Its header explains why it is one
    // command and not nine.
    property var facts: ({})
    property bool factsLoading: false
    property string lastError: ""

    readonly property string model: facts.model || ""
    readonly property string language: facts.language || ""
    readonly property string engine: facts.engine || ""
    readonly property var models: facts.models || []
    readonly property var languages: facts.languages || []
    readonly property bool unitActive: facts.unit ? facts.unit.active === "active" : false
    readonly property bool unitFailed: facts.unit ? facts.unit.active === "failed" : false
    readonly property int rssMb: facts.unit ? Number(facts.unit.rssMb || 0) : 0
    // Tri-state on purpose: `null` is "no wpctl to ask", which is not "live".
    readonly property var micMuted: facts.micMuted === undefined ? null : facts.micMuted
    readonly property var accelBadge: Model.accelBadge(facts.accel, facts.gpuPresent)
    readonly property bool capturePaused: facts.capture ? facts.capture.paused === true : false
    // The daemon is running a different build from the binary on disk, which
    // an in-place upgrade leaves behind (the old process keeps the old inode).
    // Worth saying out loud: every setting below is read from the NEW binary's
    // schema, so the panel would otherwise report what the running daemon is
    // about to do rather than what it is doing.
    readonly property bool daemonStale: facts.daemonVersionDiffers === true

    readonly property string factsLine: Model.factsLine({
        engine: root.engine,
        model: root.model,
        language: root.language,
        unitState: root.facts.unit ? root.facts.unit.active : "",
        rssMb: root.rssMb
    })

    function refreshFacts() {
        if (factsProcess.running)
            return;
        factsLoading = true;
        factsProcess.running = true;
    }

    // A dictation moves the daemon: the first one of the session STARTS it,
    // and the facts line would otherwise sit there reading "unit inactive"
    // while the hero above it says "Listening" (seen, 2026-09-04). Gated on
    // the panel, so a shell with nothing open still takes no snapshots — and
    // three per dictation at 0.1 s each is nothing next to the transcription.
    onDictationStateChanged: if (panelOpen)
        refreshFacts()

    readonly property Process factsProcess: Process {
        command: [root.binDir + "voxtype-facts"]
        stdout: StdioCollector {
            onStreamFinished: {
                root.factsLoading = false;
                try {
                    root.facts = JSON.parse(text);
                    root.lastError = "";
                } catch (e) {
                    // A snapshot that will not parse is a broken helper, not a
                    // broken voxtype; say so rather than blanking the panel.
                    root.lastError = "could not read voxtype facts";
                }
            }
        }
    }

    // ----------------------------------------------------------- the history
    // Written by bin/voxtype-capture on voxtype's post_process hook. Watched
    // rather than polled — the writer replaces both files atomically, so a
    // change notification is a complete file every time.
    property string historyRaw: ""
    property var days: ({})
    property var pins: []

    readonly property var history: Model.parseHistory(historyRaw)
    readonly property var bars: Model.dayBars(days, new Date())
    readonly property var totals: Model.chartTotals(bars)
    readonly property var destinations: Model.destinationTotals(history)

    readonly property FileView historyFile: FileView {
        // The empty path is what makes this panel-gated: a FileView with no
        // path holds nothing open and reads nothing.
        path: root.panelOpen ? root.statePath + "dictation.jsonl" : ""
        watchChanges: true
        printErrors: false
        onLoaded: root.historyRaw = text()
        // No log yet is the normal state on a fresh machine and on any machine
        // where nothing has been dictated since the hook was wired — an empty
        // history, not an error.
        onLoadFailed: root.historyRaw = ""
        onFileChanged: reload()
    }

    readonly property FileView daysFile: FileView {
        path: root.panelOpen ? root.statePath + "dictation-days.json" : ""
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                root.days = JSON.parse(text());
            } catch (e) {
                root.days = ({});
            }
        }
        onLoadFailed: root.days = ({})
        onFileChanged: reload()
    }

    readonly property FileView pinsFile: FileView {
        path: root.panelOpen ? root.statePath + "dictation-pins.json" : ""
        watchChanges: true
        printErrors: false
        onLoaded: {
            try {
                const got = JSON.parse(text());
                root.pins = Array.isArray(got) ? got : [];
            } catch (e) {
                root.pins = [];
            }
        }
        onLoadFailed: root.pins = []
        onFileChanged: reload()
    }

    function isPinned(id) {
        return pins.indexOf(id) !== -1;
    }

    // -------------------------------------------------------------- the mic
    // The daemon broadcasts 16-byte audio frames at 100 Hz on a unix socket,
    // which QML cannot read; upstream's voxtype-audio-bridge re-emits them as
    // NDJSON on stdout. Gated on `recording` because that is the only time
    // frames exist — an idle daemon leaves the bridge connected and silent,
    // and running it anyway would be a process per shell for nothing.
    //
    // Also gated on the OSD or panel actually wanting it: a bar with no
    // dictation surface on screen has nothing to draw with.
    property bool levelsWanted: false

    // Newest last. Fixed length so the OSD can index it directly and the array
    // never grows.
    property var levels: new Array(64).fill(0)
    property real peak: 0

    property real _pending: 0

    readonly property Process bridge: Process {
        command: [Quickshell.env("HOME") + "/.local/bin/voxtype-audio-bridge"]
        running: root.levelsWanted && root.recording
        stdout: SplitParser {
            onRead: data => {
                let frame = ({});
                try {
                    frame = JSON.parse(String(data));
                } catch (e) {
                    return;
                }
                // Connection notices ({"status":"connected"}) carry no peak.
                if (frame.peak === undefined)
                    return;
                // Keep the LOUDEST frame since the last repaint rather than
                // the latest: at 100 Hz in and 30 Hz out, taking the last
                // sample would drop two frames in three and make a spoken
                // syllable look like whatever the tail of it happened to be.
                root._pending = Math.max(root._pending, Number(frame.peak) || 0);
            }
        }
        onRunningChanged: {
            if (!running) {
                root.levels = new Array(64).fill(0);
                root.peak = 0;
                root._pending = 0;
            }
        }
    }

    // 30 Hz, not 100: the bridge's rate is an audio rate, and rebuilding the
    // waveform a hundred times a second would spend the shell's frame budget
    // on samples no one can see.
    readonly property Timer levelTimer: Timer {
        interval: 33
        repeat: true
        running: root.bridge.running
        onTriggered: {
            const next = root.levels.slice(1);
            next.push(root._pending);
            root.levels = next;
            root.peak = root._pending;
            root._pending = 0;
        }
    }

    // ------------------------------------------------------------- actions
    // Every write goes through one Process so the facts snapshot that follows
    // it cannot race a second write. `pending` is what the panel disables its
    // controls on.
    property bool pending: false
    property var _queue: []

    function run(argv) {
        _queue.push(argv);
        _drain();
    }

    function _drain() {
        if (actionProcess.running || _queue.length === 0)
            return;
        pending = true;
        actionProcess.command = _queue.shift();
        actionProcess.running = true;
    }

    readonly property Process actionProcess: Process {
        stdout: StdioCollector {}
        stderr: StdioCollector {
            onStreamFinished: {
                if (text.trim() !== "")
                    root.lastError = text.trim().split("\n")[0];
            }
        }
        onExited: (code, status) => {
            root.pending = false;
            if (root._queue.length > 0) {
                root._drain();
                return;
            }
            // One snapshot after the last queued write, so the panel redraws
            // from measurement rather than from what it hoped it just did.
            root.refreshFacts();
        }
    }

    // Recording goes through bin/voxtype-toggle, never `voxtype record toggle`
    // directly: the wrapper starts the on-demand daemon, opens the muted
    // microphone for the length of the take and stamps it for the log. A bare
    // toggle would skip all three and record silence into nowhere.
    function toggleRecording() {
        run([binDir + "voxtype-toggle"]);
    }

    function startDaemon() {
        run(["systemctl", "--user", "start", "voxtype.service"]);
    }

    function stopDaemon() {
        run(["systemctl", "--user", "stop", "voxtype.service"]);
    }

    function restartDaemon() {
        run(["systemctl", "--user", "restart", "voxtype.service"]);
    }

    // `config set` is atomic, validating and comment-preserving, and the
    // choices the panel offers come from the same schema it validates against
    // — so a value the panel can show is a value this cannot reject.
    function setKey(key, value) {
        run(["voxtype", "config", "set", key, String(value)]);
        // Every Engine-section key is restart_required. try-restart rather
        // than restart, because the daemon is normally stopped and starting
        // one here would park the model in RAM for a setting that will be read
        // at the next dictation anyway.
        run(["systemctl", "--user", "try-restart", "voxtype.service"]);
    }

    function setModel(name) {
        setKey(engine + ".model", name);
    }

    function setLanguage(code) {
        setKey(engine + ".language", code);
    }

    function capture(argv) {
        run([binDir + "voxtype-capture"].concat(argv));
    }

    function togglePin(id) {
        capture([isPinned(id) ? "unpin" : "pin", String(id)]);
    }

    // Detached, not through `run`: wl-copy has to outlive this call to serve
    // the selection, so it must not be a Process the shell reaps on exit.
    property string actionStatus: ""

    function copyText(text) {
        if (!text)
            return;
        Quickshell.execDetached(["wl-copy", "--type", "text/plain", String(text)]);
        actionStatus = "Copied to the clipboard";
        statusClear.restart();
    }

    readonly property Timer statusClear: Timer {
        interval: 2500
        onTriggered: root.actionStatus = ""
    }

    function openConfigurator() {
        Quickshell.execDetached(["foot-run", "--app-id=qshell-float", "-e", "voxtype", "configure"]);
    }

    // A shell rather than a bare argv: `meeting list` prints and exits, and a
    // terminal that closes on the same frame shows nothing. The read is the
    // point, so the window waits.
    function openMeetings() {
        Quickshell.execDetached(["foot-run", "--app-id=qshell-float", "-e", "sh", "-c", "voxtype meeting list; echo; echo 'voxtype meeting show|export|summarize <id>'; echo 'Press enter to close.'; read _"]);
    }
}
