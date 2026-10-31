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
    // The desk's clock, whose per-minute tick turns the day at local midnight.
    required property var clock
    readonly property string backend: Quickshell.env("DOTS_DEEN") || "deen"
    // The date the IPC set; "" is today.
    property string pinned: ""
    readonly property var entries: P.parse(list.text()).entries
    // A string, so a tick on the same date, or a pinned date at midnight, leaves the pick and its read alone.
    readonly property string date: pinned || P.today(clock.now)
    readonly property var pick: entries.length ? P.pick(P.dayOf(date), entries) : null
    // `deen api surahs`, read once, the first time an ayah needs its surah's name; a day it failed for asks no more, and a later day asks again.
    property string surahs: ""
    property var surahsFor: null
    // What the sheets draw, with the kind it is and whether it stands in for a day deen could not answer; null until deen answers, and a new pick clears it, so no sheet draws another day's text.
    property var text: null
    readonly property var voiced: text && theme.tokens ? P.voiced(theme.tokens.type.voice, text.kind, text.ref) : null

    onPickChanged: read()
    Component.onCompleted: read()

    function read() {
        text = null;
        if (!pick)
            return;
        const args = P.deenArgs(pick.item);
        if (!args) {
            show(pick, P.shape(pick.item, "", ""));
            return;
        }
        if (pick.kind === "ayah" && !surahs && surahsFor !== pick) {
            surahsFor = pick;
            // A run already going reads on for this pick when it ends; set running again, it would run twice.
            if (!surahsRead.running) {
                surahsRead.startedAt = Date.now();
                surahsRead.began = false;
                surahsRead.running = true;
            }
            return;
        }
        // A run already going keeps its pick; it reads again once it exits.
        if (entryRead.running)
            return;
        entryRead.reading = pick;
        entryRead.command = [backend].concat(args);
        entryRead.startedAt = Date.now();
        entryRead.began = false;
        entryRead.running = true;
    }

    // A deen run still going 30 s after it started ends at the clock's tick, so a deen that hangs falls back rather than leaving the paper empty.
    function endHung() {
        for (const run of [surahsRead, entryRead])
            if (run.running && Date.now() - run.startedAt >= 30000)
                run.running = false;
    }

    Connections {
        target: passage.clock
        function onNowChanged() {
            passage.endHung();
        }
    }

    // A day deen could not answer, or answered past the list's limits, draws its fallback quote instead.
    function show(day, shaped) {
        const f = P.within(shaped) ? null : P.fallback(day.day, entries);
        text = Object.assign({
            kind: f ? "quote" : day.kind,
            fallback: f !== null
        }, f ? P.shape(f.item, "", "") : shaped);
    }

    // The surahs read for an ayah day ends, answered or not; only the pick it was for reads on.
    function surahsDone(answer) {
        surahs = answer;
        if (surahsFor === pick)
            read();
    }

    // The day's read ends; one for a pick no longer wanted reads the new pick instead.
    function entryDone(code) {
        if (entryRead.reading === pick)
            show(pick, code === 0 ? P.shape(pick.item, entryOut.text, surahs) : null);
        else
            read();
    }

    FileView {
        id: list
        path: Quickshell.shellPath("data/passages.txt")
        blockLoading: true
    }

    Process {
        id: surahsRead
        // When read() started it; running turns true only once the process is up.
        property real startedAt: 0
        // Whether it started: a deen that is not there to run ends with no exit and no stream, only running turning false.
        property bool began: false
        command: [passage.backend, "api", "surahs"]
        onStarted: began = true
        onRunningChanged: if (!running && !began)
            passage.surahsDone("")
        stdout: StdioCollector {
            onStreamFinished: passage.surahsDone(text)
        }
    }

    // reading is the pick this run was started for, so a pick that changed while deen ran never takes its answer.
    Process {
        id: entryRead
        property var reading: null
        property real startedAt: 0
        property bool began: false
        stdout: StdioCollector {
            id: entryOut
        }
        onStarted: began = true
        onRunningChanged: if (!running && !began)
            passage.entryDone(-1)
        onExited: code => passage.entryDone(code)
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
                fallback: t ? t.fallback : false,
                ref: passage.voiced ? passage.voiced.ref : "",
                label: passage.voiced ? passage.voiced.label : "",
                ar: t ? t.ar : "",
                bn_pron: t ? t.bn_pron : "",
                bn: t ? t.bn : "",
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
