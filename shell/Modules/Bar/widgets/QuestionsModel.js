.pragma library

// Open questions from the local hub: the bar's waiting count, the popups this
// machine rings, and the `mem answer` argv a reply runs. Pure data, with no
// Process and no state.
//
// The input is $XDG_RUNTIME_DIR/hub-questions.json, which the local hub
// writes whole (temp + rename) whenever its open set changes:
//
//     {"self":"mini","questions":[{"id":"ABCD1234","project":"workflow",
//       "machine":"nuc","text":"...","options":["yes","no"],
//       "person":true,"popup":true}]}
//
// `person` marks a question for Saiful, which counts as waiting. `popup`
// marks one that rings on this machine. Question text and answers are
// untrusted, so they only ever travel as argv elements.

// A file that is absent, unparseable or has no question list means no hub
// runs here, and the bar falls back to the route file's count.
// The hub names machines by MagicDNS host, perhaps with a port; a card
// shows the first label only. An address stays whole.
function shortMachine(host) {
    if (/^[0-9.:]+$/.test(host))
        return host;
    return host.split(".")[0].split(":")[0];
}

function parseState(raw) {
    var data = null;
    try {
        data = JSON.parse(String(raw || ""));
    } catch (e) {
        return { valid: false, questions: [] };
    }
    if (!data || typeof data !== "object" || !Array.isArray(data.questions))
        return { valid: false, questions: [] };
    var questions = [];
    for (var i = 0; i < data.questions.length; i++) {
        var q = data.questions[i];
        if (!q || typeof q.id !== "string" || q.id === "")
            continue;
        questions.push({
            id: q.id,
            project: typeof q.project === "string" ? q.project : "",
            machine: typeof q.machine === "string" ? shortMachine(q.machine) : "",
            text: typeof q.text === "string" ? q.text : "",
            options: Array.isArray(q.options) ? q.options.filter(function (o) {
                return typeof o === "string";
            }) : [],
            person: q.person === true,
            popup: q.popup === true
        });
    }
    return { valid: true, questions: questions };
}

// routeState is RouteModel.parseState's result for workflow-route.json.
function waitingCount(state, routeState) {
    if (!state || !state.valid)
        return routeState && routeState.valid ? routeState.waiting : 0;
    return state.questions.filter(function (q) {
        return q.person;
    }).length;
}

// `dismissed` maps an id to true once its popup is closed with the x. A
// closed popup does not answer, so the question still counts as waiting.
function dismiss(dismissed, id) {
    var next = {};
    for (var key in dismissed)
        next[key] = true;
    next[id] = true;
    return next;
}

function popups(state, dismissed) {
    if (!state || !state.valid)
        return [];
    return state.questions.filter(function (q) {
        return q.popup && !dismissed[q.id];
    });
}

// Keeps only the dismissals whose question is still in the file, so an id
// that leaves and comes back rings again.
function pruneDismissed(dismissed, state) {
    var next = {};
    var questions = state && state.valid ? state.questions : [];
    for (var i = 0; i < questions.length; i++) {
        if (dismissed[questions[i].id])
            next[questions[i].id] = true;
    }
    return next;
}

// The question the Reply modal shows, or null once it no longer rings here
// (answered elsewhere, or routed to Phone), which closes the modal.
function modalFor(id, state) {
    if (!id || !state || !state.valid)
        return null;
    for (var i = 0; i < state.questions.length; i++) {
        if (state.questions[i].id === id && state.questions[i].popup)
            return state.questions[i];
    }
    return null;
}

// `--` ends mem's options, so an answer that starts with a dash stays text.
function answerArgv(id, text, screenshotPath) {
    var argv = ["mem", "answer", "--by", "popup"];
    if (screenshotPath)
        argv.push("--screenshot", screenshotPath);
    return argv.concat(["--", id, text]);
}
