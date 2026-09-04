import QtQuick
import Quickshell.Io

// One recitation attempt: start it, stop it, get a verdict.
//
// Extracted because two screens need exactly this and a second copy would
// drift — the Recite screen scores an ayah you can see, the Hifz screen scores
// one you are recalling from memory, and the difference between them is what
// is on screen, not how the microphone works.
//
// STOPPING IS A CLOSED PIPE, NOT A SIGNAL. `deen recite` records until its
// stdin reaches EOF, so stop() is `stdinEnabled = false` — no PID bookkeeping,
// no kill, and no way to leave the microphone open by losing track of a child.
// deen's own --max-seconds is the backstop if this object dies mid-recitation.
QtObject {
    id: reciter

    /// The ayah being recited, e.g. "1:6".
    property string reference: ""

    /// "idle" | "recording" | "checking" | "done" | "error"
    property string state_: "idle"
    property var result: null
    property string error: ""

    readonly property bool busy: state_ === "recording" || state_ === "checking"

    /// A result worth PAINTING, which is not the same as a result.
    ///
    /// When VAD hears no speech deen returns an empty transcription and the
    /// aligner — correctly — reports every word as missed. Painting that puts
    /// the whole ayah in red under the words "nothing was heard", which tells
    /// someone whose microphone was muted that they got every word wrong. A
    /// recitation that did not happen has no verdict.
    readonly property var verdict: (result && String(result.heard).trim()) ? result : null

    readonly property bool heardNothing: state_ === "done" && !verdict

    signal finished(var result)

    function start() {
        if (busy || reference === "")
            return;
        reciter.result = null;
        reciter.error = "";
        reciter.state_ = "recording";
        proc.command = ["setpriv", "--pdeathsig", "TERM", "--", "deen", "recite", reciter.reference];
        proc.stdinEnabled = true;
        proc.running = true;
    }

    function stop() {
        if (reciter.state_ !== "recording")
            return;
        reciter.state_ = "checking";
        proc.stdinEnabled = false;
    }

    function toggle() {
        if (reciter.state_ === "recording")
            stop();
        else if (!busy)
            start();
    }

    /// Throw away the last verdict without touching a recording in flight.
    function reset() {
        if (reciter.busy)
            return;
        reciter.result = null;
        reciter.error = "";
        reciter.state_ = "idle";
    }

    readonly property Process proc: Process {
        running: false

        stdout: StdioCollector {
            id: out
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: err
            waitForEnd: true
        }

        onExited: exitCode => {
            let parsed = null;
            try {
                parsed = JSON.parse(String(out.text || ""));
            } catch (e) {
                parsed = null;
            }
            if (parsed && !parsed.error) {
                reciter.result = parsed;
                reciter.state_ = "done";
                reciter.finished(parsed);
                return;
            }
            reciter.state_ = "error";
            if (parsed && parsed.error)
                reciter.error = String(parsed.error);
            else if (exitCode === 127 || exitCode === 126)
                reciter.error = "deen is not installed — run `chezmoi apply` to build it";
            else
                reciter.error = String(err.text || "").trim().split("\n").pop() || "recitation failed";
        }
    }
}
