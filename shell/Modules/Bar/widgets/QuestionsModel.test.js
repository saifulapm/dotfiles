// Unit tests for QuestionsModel.js. Run with:
//
//     node shell/Modules/Bar/widgets/QuestionsModel.test.js
//
// QuestionsModel.js is a `.pragma library` file, which node cannot parse, so
// it is evaluated in a fresh context with that one line stripped; its
// top-level functions land on the context. Covers the map from the local
// hub's question file to the bar's waiting count, the popups this machine
// rings, and the `mem answer` argv a reply runs.

const assert = require("node:assert/strict");
const fs = require("node:fs");
const path = require("node:path");
const vm = require("node:vm");

function load(file) {
    const source = fs.readFileSync(path.join(__dirname, file), "utf8").replace(/^\.pragma library$/m, "");
    const context = vm.createContext({});
    vm.runInContext(source, context);
    return context;
}

const Model = load("QuestionsModel.js");
const Route = load("RouteModel.js");

let failures = 0;
function test(name, fn) {
    try {
        fn();
        console.log(`  ok  ${name}`);
    } catch (error) {
        failures += 1;
        console.log(`FAIL  ${name}\n      ${error.message}`);
    }
}

// The vm context has its own Object prototype, so compare through JSON.
function plain(value) {
    return JSON.parse(JSON.stringify(value));
}

const FILE = JSON.stringify({
    self: "mini",
    questions: [
        { id: "AAAA1111", project: "workflow", machine: "nuc", text: "Ship it?", options: ["yes", "no"], person: true, popup: true },
        { id: "BBBB2222", project: "dotfiles", machine: "mini", text: "Which theme?", options: [], person: true, popup: false },
        { id: "CCCC3333", project: "workflow", machine: "nuc", text: "for dulali", options: ["ok"], person: false, popup: true }
    ]
});

const ROUTE = Route.parseState('{"route":"device","machine":"mini","waiting":7,"self":"mini"}');

test("the waiting count is the number of person questions in the file", () => {
    assert.equal(Model.waitingCount(Model.parseState(FILE), ROUTE), 2);
    assert.equal(Model.waitingCount(Model.parseState('{"self":"mini","questions":[]}'), ROUTE), 0);
});

test("with no readable question file the count is the route file's waiting", () => {
    assert.equal(Model.waitingCount(Model.parseState(""), ROUTE), 7);
    assert.equal(Model.waitingCount(Model.parseState("{not json"), ROUTE), 7);
    assert.equal(Model.waitingCount(Model.parseState('{"self":"mini"}'), ROUTE), 7);
    assert.equal(Model.waitingCount(Model.parseState(""), Route.parseState("")), 0);
});

test("popups are the questions that ring here and were not closed", () => {
    const state = Model.parseState(FILE);
    assert.deepEqual(plain(Model.popups(state, {}).map(q => q.id)), ["AAAA1111", "CCCC3333"]);
    assert.deepEqual(plain(Model.popups(state, {}))[0], {
        id: "AAAA1111",
        project: "workflow",
        machine: "nuc",
        text: "Ship it?",
        options: ["yes", "no"],
        person: true,
        popup: true
    });
    const closed = Model.dismiss({}, "AAAA1111");
    assert.deepEqual(plain(Model.popups(state, closed).map(q => q.id)), ["CCCC3333"]);
});

test("a closed question still counts as waiting", () => {
    const state = Model.parseState(FILE);
    const closed = Model.dismiss({}, "AAAA1111");
    assert.equal(Model.popups(state, closed).length, 1);
    assert.equal(Model.waitingCount(state, ROUTE), 2);
});

test("a question gone from the file drops its popup and its dismissal", () => {
    const closed = Model.dismiss(Model.dismiss({}, "AAAA1111"), "CCCC3333");
    const later = Model.parseState(JSON.stringify({
        self: "mini",
        questions: [
            { id: "BBBB2222", project: "dotfiles", machine: "mini", text: "Which theme?", options: [], person: true, popup: false },
            { id: "CCCC3333", project: "workflow", machine: "nuc", text: "for dulali", options: ["ok"], person: false, popup: true }
        ]
    }));
    assert.deepEqual(plain(Model.pruneDismissed(closed, later)), { CCCC3333: true });
    assert.deepEqual(plain(Model.pruneDismissed(closed, Model.parseState(""))), {});
    // Asked again under the same id, it would ring again.
    assert.deepEqual(plain(Model.popups(Model.parseState(FILE), Model.pruneDismissed(closed, later)).map(q => q.id)), ["AAAA1111"]);
});

test("the modal keeps its question only while that question rings here", () => {
    const state = Model.parseState(FILE);
    assert.equal(Model.modalFor("AAAA1111", state).text, "Ship it?");
    assert.equal(Model.modalFor("BBBB2222", state), null);
    assert.equal(Model.modalFor("ZZZZ9999", state), null);
    assert.equal(Model.modalFor("AAAA1111", Model.parseState("")), null);
    assert.equal(Model.modalFor("", state), null);
});

test("an option click answers with the option by argv", () => {
    assert.deepEqual(plain(Model.answerArgv("AAAA1111", "yes", "")), ["mem", "answer", "--by", "popup", "--", "AAAA1111", "yes"]);
});

test("Send passes untrusted text through unchanged", () => {
    const text = "-rf \"quoted\" 'single' $(whoami) `x`\nsecond line: ঠিক আছে ✓";
    assert.deepEqual(plain(Model.answerArgv("AAAA1111", text, "")), ["mem", "answer", "--by", "popup", "--", "AAAA1111", text]);
    assert.deepEqual(plain(Model.answerArgv("AAAA1111", "--help", "")), ["mem", "answer", "--by", "popup", "--", "AAAA1111", "--help"]);
});

test("Send with a screenshot puts the flag before the separator", () => {
    assert.deepEqual(plain(Model.answerArgv("AAAA1111", "see this", "/run/user/1000/qshell-question-AAAA1111.png")), [
        "mem", "answer", "--by", "popup", "--screenshot", "/run/user/1000/qshell-question-AAAA1111.png", "--", "AAAA1111", "see this"
    ]);
});

test("a card names the asking machine by its short tailnet name", () => {
    const file = JSON.stringify({ self: "mini.tail.ts.net", questions: [
        { id: "A1", project: "p", machine: "nuc.taila27604.ts.net", text: "t", options: [], person: true, popup: true },
        { id: "A2", project: "p", machine: "macbook.taila27604.ts.net:8790", text: "t", options: [], person: true, popup: true },
        { id: "A3", project: "p", machine: "100.101.46.37:8789", text: "t", options: [], person: true, popup: true },
    ] });
    const machines = Model.parseState(file).questions.map((q) => q.machine);
    assert.equal(JSON.stringify(machines), JSON.stringify(["nuc", "macbook", "100.101.46.37:8789"]));
});

test("Ctrl+V takes a png first, then any image, then a copied file, then text", () => {
    assert.deepEqual(plain(Model.pasteAction("text/plain\nimage/jpeg\nimage/png\n")), { kind: "image", mime: "image/png" });
    assert.deepEqual(plain(Model.pasteAction("image/webp\ntext/html")), { kind: "image", mime: "image/webp" });
    assert.deepEqual(plain(Model.pasteAction("x-special/gnome-copied-files\ntext/uri-list\ntext/plain;charset=utf-8")), { kind: "file" });
    assert.deepEqual(plain(Model.pasteAction("text/plain;charset=utf-8\nUTF8_STRING")), { kind: "text" });
    assert.deepEqual(plain(Model.pasteAction("UTF8_STRING")), { kind: "text" });
    assert.deepEqual(plain(Model.pasteAction("")), { kind: "none" });
    assert.deepEqual(plain(Model.pasteAction("application/x-unknown")), { kind: "none" });
});

test("a pasted image lands at the question's shot path with its own extension", () => {
    assert.equal(Model.shotPath("/run/user/1000", "7A48KQAA", "image/png"), "/run/user/1000/qshell-question-7A48KQAA.png");
    assert.equal(Model.shotPath("/run/user/1000", "7A48KQAA", "image/jpeg"), "/run/user/1000/qshell-question-7A48KQAA.jpg");
    assert.equal(Model.shotPath("/run/user/1000", "../../x/7A48", "image/png"), "/run/user/1000/qshell-question-x7A48.png");
});

test("a copied file attaches when it is a png or jpeg", () => {
    assert.equal(Model.imageFromUriList("file:///home/saiful/Pictures/Screen%20Shot%201.PNG\r\n"), "/home/saiful/Pictures/Screen Shot 1.PNG");
    assert.equal(Model.imageFromUriList("# comment\nfile:///tmp/a.txt\nfile:///tmp/b.jpeg\n"), "/tmp/b.jpeg");
    assert.equal(Model.imageFromUriList("file:///tmp/notes.txt"), "");
    assert.equal(Model.imageFromUriList("https://example.com/a.png"), "");
    assert.equal(Model.imageFromUriList(""), "");
});

test("the file button asks the shell's picker for one png or jpeg", () => {
    assert.deepEqual(plain(Model.pickerRequest()), {
        title: "Attach an image",
        mode: "open",
        multiple: false,
        directory: false,
        filters: [{ name: "Images", globs: ["*.png", "*.jpg", "*.jpeg"], mimes: ["image/png", "image/jpeg"] }]
    });
    assert.equal(Model.pickedImage(["/home/saiful/a.jpg", "/home/saiful/b.png"]), "/home/saiful/a.jpg");
    assert.equal(Model.pickedImage(["/home/saiful/a.gif"]), "");
    assert.equal(Model.pickedImage([]), "");
});

test("the thumbnail's url survives a # or ? in the image's path", () => {
    assert.equal(Model.fileUrl("/home/saiful/shots/bug #2?.png"), "file:///home/saiful/shots/bug%20%232%3F.png");
    assert.equal(Model.fileUrl(""), "");
});

if (failures > 0) {
    console.log(`\n${failures} failing`);
    process.exit(1);
}
console.log("\nall passing");
