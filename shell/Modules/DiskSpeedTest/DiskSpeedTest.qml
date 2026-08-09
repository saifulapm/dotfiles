import Quickshell
import Quickshell.Io
import "../Bar/widgets"

// The disk speed test — omarchy's Trigger > Tests > Disk Speed Test (2521b11),
// which pairs their disk test with the network one behind the same dial
// overlay. Ours reuses SpeedTestPanel directly: this file IS that overlay,
// relabelled READ/WRITE in MB/s and driven by bin/disk-speedtest.
//
// Unlike the network test — one process per direction, restarted for the
// second leg — bin/disk-speedtest runs both phases in a single process and
// names each line's phase, so there is nothing to sequence here: every line
// lands on whichever dial it names. The last line of a phase is the script's
// steady-state mean, so the dial settles on the figure worth reading rather
// than on whatever the final second caught.
SpeedTestPanel {
    id: root

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"

    firstLabel: "READ"
    secondLabel: "WRITE"
    firstPhase: "read"
    secondPhase: "write"
    unit: "MB/s"
    surfaceNamespace: "qshell-disk-speedtest"

    // Set when we stop the process ourselves (the overlay was closed mid-run),
    // so the non-zero exit that follows is not reported as a failure.
    property bool expectedStop: false
    property string stderrText: ""

    // The SurfaceLoader contract: summon calls show(), dismissal calls hide(),
    // and `opened` is what the loader reads back as the surface's open state.
    function show() {
        if (!root.opened) {
            root.opened = true;
            root.run();
        }
    }

    function hide() {
        root.stop();
        root.opened = false;
    }

    function run() {
        root.error = "";
        root.caption = "";
        root.firstReading = "";
        root.secondReading = "";
        root.stderrText = "";
        root.stop();
        root.running = true;
        root.phase = root.firstPhase;
        proc.command = [root.binDir + "disk-speedtest"];
        proc.running = true;
    }

    function stop() {
        if (proc.running) {
            root.expectedStop = true;
            proc.running = false;
        }
        root.running = false;
        root.phase = "";
    }

    // A run holds four dd workers against the device for ~16 s; closing the
    // overlay has to end it, not leave it grinding in the background.
    onCloseRequested: root.hide()
    onRunAgainRequested: root.run()

    Process {
        id: proc

        stdout: SplitParser {
            onRead: line => root.consume(line)
        }
        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: root.stderrText = String(text || "").trim()
        }
        onExited: exitCode => {
            root.running = false;
            root.phase = "";
            if (root.expectedStop) {
                root.expectedStop = false;
                return;
            }
            if (exitCode !== 0)
                root.error = root.stderrText || "Disk speed test failed";
        }
    }

    // `disk <model>` once, then `read <MB/s>` / `write <MB/s>` per second.
    function consume(line) {
        const text = String(line || "").trim();
        if (text === "")
            return;
        const gap = text.indexOf(" ");
        if (gap < 0)
            return;
        const key = text.slice(0, gap);
        const value = text.slice(gap + 1).trim();

        if (key === "disk") {
            root.caption = value;
            return;
        }
        if (key === root.firstPhase) {
            root.phase = root.firstPhase;
            root.firstReading = value;
        } else if (key === root.secondPhase) {
            root.phase = root.secondPhase;
            root.secondReading = value;
        }
    }
}
