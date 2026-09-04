import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
import "components"
import "screens"

// The Islamic hub: recite an ayah and be told which words were right.
//
// Every byte of it comes from `deen` (github.com/saifulapm/deen) — the shell
// parses one JSON object per call and never touches the model, the microphone
// or the text itself. That is the same division the movie hub draws against
// `dekho api`, and it buys the same things: no ML runtime on the shell's event
// loop, and one implementation of "was this recited correctly" that answers a
// terminal and this panel identically.
//
// Nothing here exists until the surface is summoned, and the loader in
// shell.qml marks it `evictable`: a hub closed for the grace period releases
// its whole tree. There is deliberately no Services/Deen.qml — unlike prayer
// times, nothing about reciting needs to be true while the panel is shut. The
// bar keeps Prayer and only Prayer.
//
// AND IT IS AN ORDINARY WINDOW, not a layer-shell overlay, for the same reason
// Dekho is: see that module's header and doc §12.
Scope {
    id: deenRoot

    required property var theme

    // Open is the window's own visibility, not a flag kept beside it — niri's
    // close-window (Mod+Q) unmaps a toplevel by WRITING visible=false, which
    // would strand a `visible: opened` binding at true for ever and defeat the
    // loader's eviction test. Dekho's header records the same trap.
    readonly property bool opened: panel.visible
    readonly property bool focused: panel.visible && keyRoot.Window.active

    readonly property var style: Style {
        theme: deenRoot.theme
        windowWidth: panel.width
        windowHeight: panel.height
    }

    // Which room you are in: "recite", "mushaf" or "hifz".
    property string view: "recite"

    // The mushaf is only worth a 1.16 MB Al-Baqarah parse once you actually
    // open it, so the first switch is what fetches it rather than the open.
    onViewChanged: {
        if (deenRoot.view === "mushaf" && deenRoot.surahAyahs.length === 0)
            surahReq.fetch(["api", "surah", String(deenRoot.mushafSurah)]);
        // The due list is time-sensitive in a way the text is not, so this one
        // is refetched on every visit rather than cached.
        if (deenRoot.view === "hifz")
            refreshHifz();
    }

    // ------------------------------------------------------------ the ayah
    property string reference: "1:1"
    property var surahs: []

    // Move an ayah at a time, across surah boundaries, which needs to know how
    // long each surah is. 114 rows, fetched once per open.
    function step(delta) {
        const parts = deenRoot.reference.split(":");
        let s = Number(parts[0]);
        let a = Number(parts[1]) + delta;
        if (deenRoot.surahs.length === 0) {
            // No table yet: clamp inside the surah rather than guessing at its
            // length and walking off the end of it.
            deenRoot.reference = s + ":" + Math.max(1, a);
            return;
        }
        const lengthOf = n => {
            const row = deenRoot.surahs.find(x => x.n === n);
            return row ? row.count : 1;
        };
        while (a < 1) {
            s -= 1;
            if (s < 1) {
                s = 1;
                a = 1;
                break;
            }
            a += lengthOf(s);
        }
        while (a > lengthOf(s)) {
            a -= lengthOf(s);
            s += 1;
            if (s > 114) {
                s = 114;
                a = lengthOf(114);
                break;
            }
        }
        deenRoot.reference = s + ":" + a;
    }

    function goTo(text) {
        if (text === "prev") {
            step(-1);
            return;
        }
        if (text === "next") {
            step(1);
            return;
        }
        // Anything else is a typed reference; deen rejects a bad one with a
        // message, so there is nothing to validate here.
        deenRoot.reference = String(text || "").trim();
    }

    DeenCall {
        id: surahsReq
        onLoaded: data => deenRoot.surahs = data.surahs || []
    }

    property var ayah: null
    // The same call already carries the word list with its tajweed spans, so
    // the Recite screen colours the rules while you can still act on them.
    property var ayahWords: []
    property string loadError: ""

    // The surah's row out of the 114, so a screen can say "AL-FAATIHA" instead
    // of "surah 1". Empty until `api surahs` lands, which is one call per open.
    readonly property var reciteSurah: {
        if (!deenRoot.ayah || deenRoot.surahs.length === 0)
            return null;
        return deenRoot.surahs.find(x => x.n === deenRoot.ayah.s) || null;
    }

    DeenCall {
        id: ayahReq
        onLoaded: data => {
            deenRoot.ayah = data.ayah || null;
            deenRoot.ayahWords = data.words || [];
            deenRoot.loadError = "";
        }
        onFailed: message => {
            deenRoot.ayah = null;
            deenRoot.ayahWords = [];
            deenRoot.loadError = message;
        }
    }

    onReferenceChanged: ayahReq.fetch(["api", "ayah", deenRoot.reference])

    // -------------------------------------------------------------- the mushaf
    // A whole surah, words included, in one call — `api surah` carries them for
    // exactly this reason: a reader paints every ayah at once and Al-Baqarah
    // would otherwise be 286 processes for one screen.
    property int mushafSurah: 1
    property var surahMeta: null
    property var surahAyahs: []
    property var surahWords: []
    property string surahBasmala: ""
    property string mushafError: ""

    DeenCall {
        id: surahReq
        onLoaded: data => {
            deenRoot.surahMeta = data.surah || null;
            deenRoot.surahAyahs = data.ayahs || [];
            deenRoot.surahWords = data.words || [];
            deenRoot.surahBasmala = data.basmala || "";
            deenRoot.mushafError = "";
        }
        onFailed: message => {
            deenRoot.surahAyahs = [];
            deenRoot.surahWords = [];
            deenRoot.mushafError = message;
        }
    }

    onMushafSurahChanged: surahReq.fetch(["api", "surah", String(deenRoot.mushafSurah)])

    // ------------------------------------------------------------------ audio
    // `deen audio` caches and answers with a path; mpv plays it. Two programs
    // because neither should be the other: deen knows which file a word is,
    // mpv knows how to make a sound.
    property string playing: ""

    function playAudio(reference) {
        deenRoot.playing = reference;
        audioProc.running = false;
        audioProc.command = ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", 'p=$(deen audio "$1" | jq -r .path 2>/dev/null) && [ -n "$p" ] && exec mpv --no-video --really-quiet "$p"', "deen-audio", reference];
        audioProc.running = true;
    }

    Process {
        id: audioProc
        running: false
        onExited: deenRoot.playing = ""
    }

    // ------------------------------------------------------------------- hifz
    // One Reciter per screen, owned here because a screen cannot see a type in
    // the directory above it — the same reason every DeenApi lives here. They
    // are separate instances so a verdict on the Recite screen is not the one
    // the review is being graded from.
    readonly property var reciteReciter: Reciter {
        reference: deenRoot.reference
    }

    readonly property var hifzReciter: Reciter {}

    property var hifzQueue: []
    property int hifzTotalDue: 0
    property int hifzEnrolled: 0
    property string hifzError: ""

    DeenCall {
        id: hifzReq
        onLoaded: data => {
            if (data.due !== undefined) {
                deenRoot.hifzQueue = data.due || [];
                deenRoot.hifzTotalDue = data.total_due || 0;
                deenRoot.hifzEnrolled = data.enrolled || 0;
                hifzScreen.position = 0;
            } else if (data.enrolled !== undefined) {
                // An add or a grade: the queue it was computed against is now
                // stale, so ask again rather than patching it here.
                deenRoot.hifzEnrolled = data.enrolled;
            }
            deenRoot.hifzError = "";
        }
        onFailed: message => deenRoot.hifzError = message
    }

    // A second request object: a grade and the refresh that follows it are two
    // calls, and queueing them through one would make the refresh wait on a
    // request that has already been superseded.
    DeenCall {
        id: hifzWriteReq
        onLoaded: () => deenRoot.refreshHifz()
        onFailed: message => deenRoot.hifzError = message
    }

    function refreshHifz() {
        hifzReq.fetch(["hifz", "due", "--limit", "40"]);
    }

    function gradeCard(reference, grade, accuracy) {
        const args = ["hifz", "grade", reference, grade];
        // -1 means the card was graded without a recitation ("Show me"), and a
        // made-up accuracy would poison the trend.
        if (accuracy >= 0)
            args.push("--accuracy", String(accuracy));
        hifzWriteReq.fetch(args);
    }

    function enrolSurah(n) {
        hifzWriteReq.fetch(["hifz", "add", String(n)]);
        // Adding a surah from the Read screen changed a number on a screen you
        // are not looking at, and answered with nothing at all.
        const row = deenRoot.surahs.find(x => x.n === Number(n));
        deenRoot.notify(row ? (row.en + " added to Memorise") : "Added to Memorise");
    }

    // A receipt you glance at and forget. `toast` lives inside the window, so
    // this is the handle the screens reach it through.
    function notify(message) {
        toast.show(message);
    }

    // ------------------------------------------------------------ open/close
    function show() {
        if (panel.visible) {
            raiseWindow();
            return;
        }
        panel.visible = true;
    }

    function hide() {
        panel.visible = false;
    }

    function didOpen() {
        if (deenRoot.surahs.length === 0)
            surahsReq.fetch(["api", "surahs"]);
        // The surface is evictable, so a reopen after the grace period starts
        // from nothing and has to ask again; within it, the ayah is still here
        // and asking twice would be a process for an answer we hold.
        if (!deenRoot.ayah)
            ayahReq.fetch(["api", "ayah", deenRoot.reference]);
        Qt.callLater(() => keyRoot.forceActiveFocus());
    }

    function didClose() {
        // A recitation in flight belongs to a panel that is no longer there.
        // Closing stdin is the same stop the button uses, so deen tears its
        // recording down and puts the microphone back the way it found it —
        // which matters more than the result nobody will now read.
        recite.stop();
        hifzScreen.reciter.stop();
    }

    // Toggle means three things for a toplevel: not open → open, open but not
    // focused → raise, open and focused → hide. Dekho's header explains why.
    function toggle() {
        if (!panel.visible) {
            panel.visible = true;
            return;
        }
        if (!focused) {
            raiseWindow();
            return;
        }
        hide();
    }

    // The window's own name, and the only handle that identifies it to the
    // compositor — every Quickshell toplevel here is app-id `org.quickshell`,
    // so only the title distinguishes them. Change this and change the niri
    // rule in home/dot_config/niri/config.kdl with it.
    readonly property string windowTitle: "Islamic Hub"

    function raiseWindow() {
        if (raiser.running)
            return;
        raiser.running = true;
    }

    Process {
        id: raiser

        running: false
        command: ["bash", "-c", "id=$(niri msg --json windows | jq -r --arg t \"$1\" '[.[] | select(.app_id == \"org.quickshell\" and .title == $t)] | sort_by(.id) | last | .id // empty')\n[ -n \"$id\" ] && exec niri msg action focus-window --id \"$id\"", "qshell-deen-raise", deenRoot.windowTitle]
    }

    // `qs ipc call deen recite 2:255` — open straight onto an ayah.
    //
    // It sets the view too, which it did not: called while the hub sat on the
    // reader it changed the ayah behind a screen that does not show one, and
    // the pedal then recorded against an invisible Recite screen. The other two
    // entry points always did this; this one was the odd one out.
    function reciteAyah(ref) {
        show();
        deenRoot.view = "recite";
        goTo(ref);
    }

    // `qs ipc call deen read 36` — open the mushaf on a surah.
    function readSurah(n) {
        show();
        deenRoot.view = "mushaf";
        const num = Math.max(1, Math.min(114, Number(n) || 1));
        if (deenRoot.mushafSurah === num)
            surahReq.fetch(["api", "surah", String(num)]);
        else
            deenRoot.mushafSurah = num;
    }

    // `qs ipc call deen memorise` — go straight to what is due.
    function memorise() {
        show();
        deenRoot.view = "hifz";
        refreshHifz();
    }

    // The recitation pedal, reachable from outside the window as well as from
    // the button and Space. A keybind can start a recitation without the hub
    // having the keyboard, which is the difference between "press Recite, then
    // start reciting" and just reciting.
    function pedal() {
        show();
        if (deenRoot.view === "hifz")
            hifzScreen.toggleRecording();
        else
            recite.toggleRecording();
    }

    FloatingWindow {
        id: panel

        title: deenRoot.windowTitle
        color: deenRoot.theme.surface0
        // Assigned, never bound — see `opened`.
        visible: false
        implicitWidth: panel.screen ? Math.round(panel.screen.width * 0.7) : 1280
        implicitHeight: panel.screen ? Math.round(panel.screen.height * 0.7) : 800
        minimumSize: Qt.size(640, 480)

        onVisibleChanged: {
            if (panel.visible)
                deenRoot.didOpen();
            else
                deenRoot.didClose();
        }

        // Shortcuts rather than Keys.onPressed: Qt consults the shortcut map
        // before delivering a key, so Escape works even while the reference
        // field has focus. Dekho verified the same precedence.
        // A sheet in front of the page gets Escape first. It cannot claim the
        // key itself: a Shortcut outranks key delivery, which is exactly why
        // Escape closes the hub from inside a text field, and the same
        // precedence would close the whole window out from under an open
        // surah list.
        Shortcut {
            sequence: "Escape"
            onActivated: {
                if (mushaf.sheetOpen) {
                    mushaf.closeSheet();
                    return;
                }
                deenRoot.hide();
            }
        }

        // Space is the recitation pedal — start, then stop — but ONLY when the
        // reference field does not have the keyboard, or typing a space into
        // "1:1" would begin a recording.
        Shortcut {
            sequence: "Space"
            enabled: !recite.editingReference && deenRoot.view !== "mushaf"
            onActivated: deenRoot.view === "hifz" ? hifzScreen.toggleRecording() : recite.toggleRecording()
        }

        FocusScope {
            id: keyRoot

            anchors.fill: parent
            focus: true

            // The glow, and it is the FIRST child of the window for a reason.
            // It has to reach past the header band or its dissolve lands as a
            // hard horizontal line, and the band it reaches into belongs to the
            // screen below — so drawn inside the chrome, which does not clip,
            // its bottom gradient painted the page colour straight over the
            // reader's own title row. Behind everything, it is a background.
            AmbientBackground {
                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: chrome.height * 2.2
                style: deenRoot.style
                pageWidth: keyRoot.width
                pageHeight: keyRoot.height
            }

            // THE HEADER BAND, which is the piece the hub did not have. Before
            // it, three flat QtQuick.Controls Buttons floated at the top of an
            // empty window and the module had no identity of its own on screen
            // — the same shape as a preferences dialog. This is Dekho's, and
            // for the same reason: a hub is a place, and a place says its name.
            Item {
                id: chrome

                anchors.top: parent.top
                anchors.left: parent.left
                anchors.right: parent.right
                height: deenRoot.style.ui(76)
                z: 1

                Row {
                    anchors.left: parent.left
                    anchors.leftMargin: deenRoot.style.pagePad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: deenRoot.style.ui(11)

                    Text {
                        textFormat: Text.PlainText
                        anchors.verticalCenter: parent.verticalCenter
                        text: "󱠧"  // md-mosque, the same glyph the bar's prayer widget wears
                        color: deenRoot.style.accent
                        font.family: deenRoot.style.fontFamily
                        font.pixelSize: deenRoot.style.type(26)
                    }

                    Column {
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: deenRoot.style.ui(1)

                        Text {
                            textFormat: Text.PlainText
                            text: "DEEN"
                            color: deenRoot.style.brightFg
                            font.family: deenRoot.style.fontFamily
                            font.pixelSize: deenRoot.style.type(15)
                            font.weight: Font.Bold
                            font.letterSpacing: 1.5
                        }

                        Text {
                            textFormat: Text.PlainText
                            text: "QURAN · RECITATION"
                            color: deenRoot.style.muted
                            font.family: deenRoot.style.fontFamily
                            font.pixelSize: deenRoot.style.type(8)
                            font.letterSpacing: 0.7
                        }
                    }
                }

                // The screen strip. A Row of chips rather than a TabBar because
                // the hub will grow more rooms than a tab bar reads well with,
                // and this is what the row becomes.
                Row {
                    id: nav

                    anchors.right: parent.right
                    anchors.rightMargin: deenRoot.style.pagePad
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: deenRoot.style.ui(5)

                    Repeater {
                        model: [
                            {
                                id: "recite",
                                label: "RECITE"
                            },
                            {
                                id: "mushaf",
                                label: "READ"
                            },
                            {
                                id: "hifz",
                                label: "MEMORISE"
                            }
                        ]

                        delegate: GlassButton {
                            required property var modelData

                            style: deenRoot.style
                            text: modelData.label
                            compact: true
                            // `primary`, not `selected`, and it is the one
                            // place this module reads omakade's vocabulary
                            // loosely. `selected` is a 0.12 wash over 0.045 —
                            // enough to mark one chip in a filter row, not
                            // enough to say which of three rooms you are
                            // standing in, which is the only thing the header
                            // has to answer.
                            primary: deenRoot.view === modelData.id
                            onClicked: deenRoot.view = modelData.id
                        }
                    }
                }

                Rectangle {
                    anchors.bottom: parent.bottom
                    anchors.left: parent.left
                    anchors.right: parent.right
                    height: deenRoot.style.hairline
                    color: deenRoot.style.alpha(deenRoot.style.muted, 0.16)
                }
            }

            Item {
                anchors.top: chrome.bottom
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.bottom: parent.bottom

                ReciteScreen {
                    id: recite

                    anchors.fill: parent
                    visible: deenRoot.view === "recite"
                    style: deenRoot.style
                    reference: deenRoot.reference
                    ayah: deenRoot.ayah
                    words: deenRoot.ayahWords
                    surah: deenRoot.reciteSurah
                    loadError: deenRoot.loadError
                    reciter: deenRoot.reciteReciter
                    onReferenceChanged_: ref => deenRoot.goTo(ref)
                }

                MushafScreen {
                    id: mushaf

                    anchors.fill: parent
                    visible: deenRoot.view === "mushaf"
                    style: deenRoot.style
                    surah: deenRoot.surahMeta
                    surahs: deenRoot.surahs
                    ayahs: deenRoot.surahAyahs
                    words: deenRoot.surahWords
                    basmala: deenRoot.surahBasmala
                    loadError: deenRoot.mushafError
                    playing: deenRoot.playing
                    onSurahStepped: delta => deenRoot.mushafSurah = Math.max(1, Math.min(114, deenRoot.mushafSurah + delta))
                    onSurahPicked: n => deenRoot.mushafSurah = n
                    onPlay: reference => deenRoot.playAudio(reference)
                    onEnrol: reference => deenRoot.enrolSurah(reference)
                }

                HifzScreen {
                    id: hifzScreen

                    anchors.fill: parent
                    visible: deenRoot.view === "hifz"
                    style: deenRoot.style
                    queue: deenRoot.hifzQueue
                    surahs: deenRoot.surahs
                    totalDue: deenRoot.hifzTotalDue
                    enrolled: deenRoot.hifzEnrolled
                    loadError: deenRoot.hifzError
                    reciter: deenRoot.hifzReciter
                    onGraded: (reference, grade, accuracy) => deenRoot.gradeCard(reference, grade, accuracy)
                    onEnrol: reference => deenRoot.enrolSurah(reference)
                }
            }

            Toast {
                id: toast

                style: deenRoot.style
            }
        }
    }
}
