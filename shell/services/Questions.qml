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

    function load(text) {
        all = Q.parseQuestions(text);
        const kept = {};
        for (const q of all) {
            if (away[q.id])
                kept[q.id] = true;
        }
        away = kept;
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
        answerer.command = Q.answerArgv(id, text);
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
