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
//       "recommend":"yes","person":true,"popup":true}]}
//
// `recommend` is the option the asker recommends, "" for none. `person` marks a question for Saiful, which counts as waiting. `popup`
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
            recommend: typeof q.recommend === "string" ? q.recommend : "",
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
// A reply needs words or at least one image; mem takes an empty answer
// when images carry it.
function canSend(text, attachments) {
    return String(text).trim() !== "" || attachments.length > 0;
}

// mem takes --screenshot once per attachment, in the order given.
function answerArgv(id, text, attachments) {
    var argv = ["mem", "answer", "--by", "popup"];
    for (var i = 0; i < attachments.length; i++)
        argv.push("--screenshot", attachments[i]);
    return argv.concat(["--", id, text]);
}

// The reply's attachments: new paths go on the end, and a path already
// attached is not attached twice.
function attach(list, paths) {
    var next = list.slice();
    for (var i = 0; i < paths.length; i++) {
        if (next.indexOf(paths[i]) === -1)
            next.push(paths[i]);
    }
    return next;
}

function detach(list, index) {
    return list.filter(function (_, i) {
        return i !== index;
    });
}

// Ctrl+V in the Reply modal reads `wl-paste --list-types` and takes, in
// order: a png, any other image, a copied file (text/uri-list), then text.
function pasteAction(typesText) {
    var types = String(typesText || "").split("\n").map(function (t) {
        return t.trim();
    }).filter(function (t) {
        return t !== "";
    });
    if (types.indexOf("image/png") !== -1)
        return { kind: "image", mime: "image/png" };
    for (var i = 0; i < types.length; i++) {
        if (types[i].indexOf("image/") === 0)
            return { kind: "image", mime: types[i] };
    }
    if (types.indexOf("text/uri-list") !== -1)
        return { kind: "file" };
    for (var j = 0; j < types.length; j++) {
        if (types[j].indexOf("text/") === 0 || types[j] === "UTF8_STRING" || types[j] === "STRING" || types[j] === "TEXT")
            return { kind: "text" };
    }
    return { kind: "none" };
}

// One file per pasted image in the runtime dir, numbered by `n` so a second
// paste does not overwrite the first. The id and the extension keep only
// letters and digits, so neither can name another path.
function shotPath(dir, id, n, mime) {
    var ext = String(mime).replace(/^image\//, "").replace(/[^A-Za-z0-9]/g, "");
    return dir + "/qshell-question-" + String(id).replace(/[^A-Za-z0-9]/g, "") + "-" + n + "." + (ext === "jpeg" ? "jpg" : ext);
}

var IMAGE_GLOBS = ["*.png", "*.jpg", "*.jpeg"];

function isImage(path) {
    return /\.(png|jpe?g)$/i.test(path);
}

// The local png and jpeg files in a text/uri-list, as paths.
function imagesFromUriList(text) {
    var lines = String(text || "").split(/\r?\n/);
    var paths = [];
    for (var i = 0; i < lines.length; i++) {
        var line = lines[i].trim();
        if (line.indexOf("file://") !== 0)
            continue;
        var path = decodeURIComponent(line.replace(/^file:\/\/[^\/]*/, ""));
        if (isImage(path))
            paths.push(path);
    }
    return paths;
}

// The request the shell's own FilePicker takes, in the portal's flattened
// shape, minus the FIFO an in-shell caller does not need.
function pickerRequest() {
    return {
        title: "Attach images",
        mode: "open",
        multiple: true,
        directory: false,
        filters: [{ name: "Images", globs: IMAGE_GLOBS, mimes: ["image/png", "image/jpeg"] }]
    };
}

function pickedImages(paths) {
    return (paths || []).filter(isImage);
}

// A picked file's name may hold a # or ?, which a bare "file://" + path
// would read as a fragment or a query.
function fileUrl(path) {
    return path ? "file://" + path.split("/").map(encodeURIComponent).join("/") : "";
}
