import Quickshell.Io

// One `dekho api …` call site. Declarative on purpose: a hub open fires four
// of these at once, and four named instances in the tree beat a dynamically
// created pool that nothing can read at a glance.
//
// `dekho api` answers with exactly one JSON object on stdout and puts its
// diagnostics on stderr, so success is "stdout parsed" and nothing here has to
// interpret log text. A verb that fails still prints `{"error": …}` and exits
// non-zero; both paths land on failed().
//
// Restarting a running Process would leave its exit to arrive later with no
// way to tell which run it belonged to, so a request that arrives mid-flight
// is QUEUED and replayed instead — which is also exactly the behaviour a
// debounced search field wants.
Process {
    id: req

    // Set by the caller before fetch(); the argv after `dekho api`.
    property var lastArgs: []
    property var queuedArgs: null
    property bool inFlight: false
    property string lastError: ""

    // Optional per-open answer cache (Dekho.qml `memo`). When it is set, an
    // argv it already holds answers from it SYNCHRONOUSLY and no process is
    // spawned — which is what makes walking back down the navigation stack
    // instant instead of a fresh round of `dekho api` calls. Left null at the
    // call sites whose answer must be live (history after a film, a search),
    // because staleness is a property of the verb, not of the plumbing.
    property var memo: null

    signal loaded(var data)
    signal failed(string message)

    function fetch(args) {
        if (memo) {
            const hit = memo.lookup(args);
            if (hit !== null) {
                lastArgs = args;
                lastError = "";
                req.loaded(hit);
                return;
            }
        }
        if (inFlight) {
            queuedArgs = args;
            return;
        }
        lastArgs = args;
        inFlight = true;
        lastError = "";
        // setpriv --pdeathsig: a `dekho api` left behind by a shell that died
        // mid-request would sit on a TMDB connection with nobody to answer.
        // Playback deliberately does NOT run this way (see bin/dekho-play).
        command = ["setpriv", "--pdeathsig", "TERM", "--", "dekho", "api"].concat(args);
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
            if (req.memo)
                req.memo.remember(req.lastArgs, parsed);
            req.loaded(parsed);
        } else if (exitCode === 127 || exitCode === 126) {
            // The one failure worth naming: dekho is not installed on this
            // machine yet. Everything else is a network or TMDB problem and
            // stderr says so better than we could.
            req.lastError = "dekho is not installed — run `chezmoi apply` to build it";
            req.failed(req.lastError);
        } else {
            const line = String(err.text || "").trim().split("\n").pop();
            req.lastError = line || ("dekho api " + req.lastArgs.join(" ") + " failed");
            req.failed(req.lastError);
        }

        if (req.queuedArgs !== null) {
            const next = req.queuedArgs;
            req.queuedArgs = null;
            req.fetch(next);
        }
    }
}
