.pragma library

// Question-route parsing and phrasing for the route widget: the pure data the
// service, the glyph and the panel read, with no Process and no state.
//
// The input is $XDG_RUNTIME_DIR/workflow-route.json, which this machine's
// local hub rewrites whole at its start and on every change of route:
//
//     {"route":"phone"|"device","machine":<host|null>,"self":"<host>"}
//
// `machine` and `self` are local hubs' hosts (e.g. "mini.taila27604.ts.net",
// with ":<port>" off the usual port), read here as their first label ("mini"),
// which is not always qshell's own name for the machine (e.g. "mac-mini-m2");
// when present `self` is the name compared with `machine`.
//
// The bar draws only what that file says. A click runs `workflow route ...`
// and waits for the hub's rewrite, so two machines changing the route at
// once both end on whatever the local hubs settle on.
//
// Glyphs are Material Design marks from the installed Symbols Nerd Font,
// checked present with `fc-list :charset=<cp>`.

var PHONE_GLYPH = "󰄜"; // md-cellphone
var DEVICE_GLYPH = "󰍹"; // md-monitor
// The hub web, which "open hub" opens.
var HUB_URL = "https://hub.on-rexa.com";

// A host's first label, without a port: "mini.taila27604.ts.net:8790" -> "mini".
function shortMachine(host) {
    return host.split(".")[0].split(":")[0];
}

// A file that is absent, unparseable or names an unknown route means the
// local hub is not running or predates the route, so the glyph hides.
function parseState(raw) {
    var data = null;
    try {
        data = JSON.parse(String(raw || ""));
    } catch (e) {
        return { valid: false };
    }
    if (!data || typeof data !== "object" || Array.isArray(data))
        return { valid: false };
    if (data.route !== "phone" && data.route !== "device")
        return { valid: false };
    var waiting = Math.floor(Number(data.waiting) || 0);
    return {
        valid: true,
        route: data.route,
        machine: typeof data.machine === "string" ? shortMachine(data.machine) : "",
        waiting: waiting > 0 ? waiting : 0,
        self: typeof data.self === "string" ? shortMachine(data.self) : ""
    };
}

function visible(state) {
    return !!(state && state.valid);
}

function glyph(state) {
    return visible(state) && state.route === "device" ? DEVICE_GLYPH : PHONE_GLYPH;
}

// `waiting` is QuestionsModel.waitingCount: the hub's question file when one
// exists, else this file's own count.
function badge(waiting) {
    return waiting > 0 ? String(waiting) : "";
}

// "phone", "device" (this machine) or "elsewhere" (Device on another machine).
// A device route with no machine named is read as this one's.
// This machine's name as the hub knows it, else qshell's.
function here(state, thisMachine) {
    return state && state.self ? state.self : thisMachine;
}

function currentChoice(state, thisMachine) {
    if (!visible(state))
        return "";
    thisMachine = here(state, thisMachine);
    if (state.route === "phone")
        return "phone";
    return state.machine === "" || state.machine === thisMachine ? "device" : "elsewhere";
}

function deviceLabel(state, thisMachine) {
    thisMachine = here(state, thisMachine);
    return thisMachine ? "Device (" + thisMachine + ")" : "Device";
}

function elsewhereLabel(state, thisMachine) {
    return currentChoice(state, thisMachine) === "elsewhere" ? "Device (" + state.machine + ")" : "";
}

function waitingLine(waiting) {
    return waiting + " waiting";
}

function hubUrl(state) {
    return visible(state) ? HUB_URL : "";
}

// The local hub names this machine itself, so Device takes no argument here.
function commandFor(choice) {
    return ["workflow", "route", choice === "device" ? choice : "phone"];
}
