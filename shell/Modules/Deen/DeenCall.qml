import Quickshell.Io

// One `deen …` call site, the same shape as Dekho's ApiRequest.
//
// The argv is the WHOLE command after `deen`, not just the part after
// `deen api` — `hifz` and `audio` are top-level verbs, and a wrapper that
// assumed `api` sent `deen api hifz due` and got a clap parse error back.
//
// Every deen verb answers with exactly one JSON object on stdout and puts its
// diagnostics on stderr, so success is "stdout parsed" and nothing here has to
// interpret log text. A verb that fails still prints `{"error": …}` and exits
// non-zero; both paths land on failed().
//
// A request that arrives while one is in flight is QUEUED rather than
// restarting the Process — an exit from a restarted run would arrive with no
// way to tell which call it belonged to.
Process {
    id: req

    property var lastArgs: []
    property var queuedArgs: null
    property bool inFlight: false
    property string lastError: ""

    signal loaded(var data)
    signal failed(string message)

    function fetch(args) {
        if (inFlight) {
            queuedArgs = args;
            return;
        }
        lastArgs = args;
        inFlight = true;
        lastError = "";
        // --pdeathsig: a shell that dies mid-call must not leave the child
        // holding the 4 MB text file open with nobody to answer.
        command = ["setpriv", "--pdeathsig", "TERM", "--", "deen"].concat(args);
        running = true;
    }

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
        req.inFlight = false;

        let parsed = null;
        try {
            parsed = JSON.parse(String(out.text || ""));
        } catch (e) {
            parsed = null;
        }

        if (parsed && parsed.error) {
            req.lastError = String(parsed.error);
            req.failed(req.lastError);
        } else if (parsed) {
            req.loaded(parsed);
        } else if (exitCode === 127 || exitCode === 126) {
            req.lastError = "deen is not installed — run `chezmoi apply` to build it";
            req.failed(req.lastError);
        } else {
            // clap puts the real complaint on the FIRST line and "For more
            // information, try '--help'." on the last, so a naive tail shows
            // the one line that says nothing.
            const lines = String(err.text || "").trim().split("\n").filter(l => l.trim() !== "");
            const line = lines.find(l => l.startsWith("error:")) || lines[0] || "";
            req.lastError = line || ("deen " + req.lastArgs.join(" ") + " failed");
            req.failed(req.lastError);
        }

        if (req.queuedArgs !== null) {
            const next = req.queuedArgs;
            req.queuedArgs = null;
            req.fetch(next);
        }
    }
}
