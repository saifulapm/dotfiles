import Quickshell
import Quickshell.Io
import QtQuick
import "." as Root
import "lib/passage.mjs" as P

// The day's passage: the list's entry for the local date, its text from deen, and the passage IPC target; shell.qml makes it after the paper's first frame.
Scope {
    id: passage

    required property var theme
    // Each output's paper; state reads what each one's sheets drew.
    required property var papers
    readonly property string backend: Quickshell.env("DOTS_DEEN") || "deen"
    // The date the IPC set; "" is today.
    property string pinned: ""
    readonly property var entries: P.parse(list.text()).entries
    readonly property var pick: entries.length ? P.pick(P.dayOf(pinned || P.today(new Date())), entries) : null
    // `deen api surahs`, read once, the first time an ayah needs its surah's name.
    property string surahs: ""
    // What the sheets draw, null until deen answers; a new pick clears it, so no sheet draws another day's text.
    property var text: null
    readonly property var voiced: text && theme.tokens ? P.voiced(theme.tokens.type.voice, pick.kind, text.ref) : null

    onPickChanged: read()
    Component.onCompleted: read()

    function read() {
        text = null;
        if (!pick)
            return;
        const args = P.deenArgs(pick.item);
        if (!args) {
            text = P.shape(pick.item, "", "");
            return;
        }
        if (pick.kind === "ayah" && !surahs) {
            surahsRead.running = true;
            return;
        }
        // A run already going keeps its pick; it reads again once it exits.
        if (entryRead.running)
            return;
        entryRead.reading = pick;
        entryRead.command = [backend].concat(args);
        entryRead.running = true;
    }

    FileView {
        id: list
        path: Quickshell.shellPath("data/passages.txt")
        blockLoading: true
    }

    Process {
        id: surahsRead
        command: [passage.backend, "api", "surahs"]
        stdout: StdioCollector {
            onStreamFinished: {
                passage.surahs = text;
                passage.read();
            }
        }
    }

    // reading is the pick this run was started for, so a pick that changed while deen ran never takes its answer.
    Process {
        id: entryRead
        property var reading: null
        stdout: StdioCollector {
            id: entryOut
        }
        onExited: {
            if (reading === passage.pick)
                passage.text = P.shape(reading.item, entryOut.text, passage.surahs);
            else
                passage.read();
        }
    }

    Root.Ipc {
        target: "passage"

        function state(): string {
            const p = passage.pick;
            const t = passage.text;
            const drawn = passage.papers.instances.map(paper => paper.passageDrawn());
            const shown = drawn.length && drawn[0].length ? drawn[0][0] : null;
            return JSON.stringify({
                day: p ? p.day : null,
                date: p ? p.date : "",
                kind: p ? p.kind : "",
                entry: p ? p.entry : null,
                fallback: false,
                ref: passage.voiced ? passage.voiced.ref : "",
                label: passage.voiced ? passage.voiced.label : "",
                ar: t ? t.ar : "",
                en: t ? t.en : "",
                family: shown ? shown.family : null,
                // Per output, what each of its sheets draws; one entry each once a theme switch settles.
                drawn: drawn
            });
        }

        // "" returns to today; anything but a real YYYY-MM-DD is refused.
        function date(iso: string): void {
            if (iso !== "" && P.dayOf(iso) === null) {
                console.warn("passage date: not a YYYY-MM-DD date: " + iso);
                return;
            }
            passage.pinned = iso;
        }
    }
}
