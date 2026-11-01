import Quickshell
import Quickshell.Io
import QtQuick
import "../lib/questions.mjs" as Q

// The local hub rewrites its question file whole on every change, so watching it is enough; nothing here polls.
Scope {
    id: questions

    property var all: []
    // Ids answered or put away with Esc; each is forgotten once it leaves the file.
    property var away: ({})
    readonly property var current: Q.shown(all, away)
    // The id whose `mem answer` is running, so a failed answer shows its question again.
    property string sending: ""
    // Files attached to each question's answer, and why its last answer failed, as mem said it; each is forgotten once the question leaves the file.
    property var attached: ({})
    property var failed: ({})

    function keep(map) {
        const kept = {};
        for (const q of all) {
            if (map[q.id])
                kept[q.id] = map[q.id];
        }
        return kept;
    }

    function load(text) {
        all = Q.parseQuestions(text);
        away = keep(away);
        attached = keep(attached);
        failed = keep(failed);
    }

    function attach(id, paths) {
        const next = Object.assign({}, attached);
        next[id] = (next[id] ?? []).concat(paths.filter(p => (next[id] ?? []).indexOf(p) < 0));
        attached = next;
    }

    function detachAll(id) {
        const next = Object.assign({}, attached);
        delete next[id];
        attached = next;
    }

    function putAway(id) {
        const next = Object.assign({}, away);
        next[id] = true;
        away = next;
    }

    function answer(id, text) {
        if (answerer.running)
            return;
        putAway(id);
        sending = id;
        const next = Object.assign({}, failed);
        delete next[id];
        failed = next;
        answerer.command = Q.answerArgv(id, text, attached[id] ?? []);
        answerer.running = true;
    }

    Process {
        id: answerer
        stderr: StdioCollector {
            id: answerErr
        }
        onExited: code => {
            if (code !== 0) {
                console.warn("questions: mem answer exited " + code + ": " + answerErr.text);
                const why = Object.assign({}, questions.failed);
                why[questions.sending] = answerErr.text.trim().split("\n").pop().replace(/^mem: /, "") || "mem answer exited " + code;
                questions.failed = why;
                const next = Object.assign({}, questions.away);
                delete next[questions.sending];
                questions.away = next;
            }
            questions.sending = "";
        }
    }

    FileView {
        path: Quickshell.env("DOTS_HUB_QUESTIONS") || Quickshell.env("XDG_RUNTIME_DIR") + "/hub-questions.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: questions.load(text())
        onLoadFailed: questions.load("")
    }
}
