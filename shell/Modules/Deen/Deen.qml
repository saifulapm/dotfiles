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

    // Which room you are in: "recite", "mushaf", "hifz", "duas" or "hadith".
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
        // 268 duas is a quarter of a megabyte and every chapter of it is drawn
        // from the same answer, so it is one call on the first visit and none
        // after — the book does not change while the hub is open.
        if (deenRoot.view === "duas" && deenRoot.duaList.length === 0)
            duaReq.fetch(["dua", "list"]);
        // The corpus is 104 MB and is never handed over whole — this asks only
        // for the ten collection names, which is what the filter row draws.
        if (deenRoot.view === "hadith") {
            if (deenRoot.hadithCollections.length === 0)
                hadithMetaReq.fetch(["hadith", "collections"]);
            // The search line is this screen's subject, so it starts with the
            // keyboard rather than waiting to be clicked.
            Qt.callLater(() => hadithScreen.takeFocus());
        }
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

    onMushafSurahChanged: {
        // A queue of references belongs to one surah. Changing surah while it
        // plays would go on reciting the old one under the new one's text.
        stopPlayback();
        surahReq.fetch(["api", "surah", String(deenRoot.mushafSurah)]);
    }

    // --------------------------------------------------------------- the duas
    // Hisn al-Muslim, whole, in one answer: `deen dua list` carries the source
    // block, the 132 chapters and all 268 duas with the book's own reference
    // footnote on each. NOTHING HERE COMPOSES CONTENT — the screen draws what
    // the file says and shows where it came from, which is the rule this hub is
    // built around and the reason the Duas screen was allowed to exist at all.
    property var duaSource: null
    property var duaChapters: []
    property var duaList: []
    // Opens on the morning-and-evening adhkar, because that is what "daily"
    // means for someone rebuilding a practice.
    property int duaChapter: 27
    property string duaError: ""

    DeenCall {
        id: duaReq
        onLoaded: data => {
            deenRoot.duaSource = data.source || null;
            deenRoot.duaChapters = data.chapters || [];
            deenRoot.duaList = data.duas || [];
            deenRoot.duaError = "";
        }
        onFailed: message => {
            deenRoot.duaList = [];
            deenRoot.duaError = message;
        }
    }

    onDuaChapterChanged: stopPlayback()

    // ------------------------------------------------------------------ hadith
    // 36,512 narrations in ten collections, on disk, never loaded whole. The
    // shell asks two questions of it — what are the collections, and what
    // matches this phrase — and draws exactly what comes back: no ranking of
    // our own, no summary, and the grades kept under the names of the scholars
    // who gave them.
    property var hadithSource: null
    property var hadithCollections: []
    property var hadithHits: []
    property int hadithTotal: 0
    property string hadithQuery: ""
    property string hadithCollection: ""
    property bool hadithSearching: false
    property string hadithError: ""

    DeenCall {
        id: hadithMetaReq
        onLoaded: data => {
            deenRoot.hadithSource = data.source || null;
            deenRoot.hadithCollections = data.collections || [];
            deenRoot.hadithError = "";
        }
        onFailed: message => deenRoot.hadithError = message
    }

    // A second request object, for the reason the hifz screen has one: a search
    // must not queue behind the collections call that opened the screen.
    DeenCall {
        id: hadithSearchReq
        onLoaded: data => {
            deenRoot.hadithHits = data.hits || [];
            deenRoot.hadithTotal = data.total || 0;
            deenRoot.hadithSearching = false;
            deenRoot.hadithError = "";
        }
        onFailed: message => {
            deenRoot.hadithHits = [];
            deenRoot.hadithTotal = 0;
            deenRoot.hadithSearching = false;
            deenRoot.hadithError = message;
        }
    }

    function searchHadith(query) {
        deenRoot.hadithQuery = String(query || "").trim();
        if (deenRoot.hadithQuery === "") {
            deenRoot.hadithHits = [];
            deenRoot.hadithTotal = 0;
            deenRoot.hadithSearching = false;
            return;
        }
        const args = ["hadith", "search", deenRoot.hadithQuery, "--limit", "40"];
        if (deenRoot.hadithCollection !== "")
            args.push("--collection", deenRoot.hadithCollection);
        deenRoot.hadithSearching = true;
        hadithSearchReq.fetch(args);
    }

    /// Narrowing to a collection re-asks the same question rather than
    /// filtering what is on screen: the answer was capped at forty, so hiding
    /// rows from it would show four Bukhari hits when there are two hundred.
    function setHadithCollection(slug) {
        deenRoot.hadithCollection = slug;
        if (deenRoot.hadithQuery !== "")
            searchHadith(deenRoot.hadithQuery);
    }

    /// Through app-run, not execDetached alone: a child of the shell dies with
    /// the next shell restart, and Notifs.qml documents the same trap.
    function openUrl(url) {
        Quickshell.execDetached(["app-run", "xdg-open", String(url)]);
    }

    // ------------------------------------------------------------------ audio
    // `deen audio` caches and answers with a path; mpv plays it. Two programs
    // because neither should be the other: deen knows which file a word is,
    // mpv knows how to make a sound.
    property string playing: ""

    // CONTINUOUS PLAYBACK IS A LIST OF REFERENCES AND AN INDEX INTO IT, not a
    // playlist handed to mpv. One `mpv file1 file2 …` would play a surah
    // gaplessly and tell us nothing about where it had got to — and knowing
    // which ayah is sounding is the entire point, because it is what highlights
    // the line and scrolls the page. One process per ayah costs a few hundred
    // milliseconds between them, which is a pause a recitation has anyway.
    property var playQueue: []
    property int playIndex: -1
    readonly property bool playingQueue: deenRoot.playIndex >= 0

    // A surah whose audio will not fetch must not spin through 286 ayat in a
    // second. Three failures in a row and it gives up.
    property int playFailures: 0

    /// One reference, on its own — a word, or an ayah tapped while nothing is
    /// playing. Cancels any surah in progress rather than fighting it for the
    /// speakers.
    function playAudio(reference) {
        deenRoot.playIndex = -1;
        deenRoot.playQueue = [];
        startAudio(reference);
    }

    function startAudio(reference) {
        deenRoot.playing = reference;
        audioProc.running = false;
        audioProc.command = ["setpriv", "--pdeathsig", "TERM", "--", "bash", "-c", 'p=$(deen audio "$1" | jq -r .path 2>/dev/null) && [ -n "$p" ] && exec mpv --no-video --really-quiet "$p"', "deen-audio", reference];
        audioProc.running = true;
    }

    /// Recite a list of references in order, each one prefetched while the one
    /// before it plays. A surah and a chapter of adhkar are the same problem
    /// once they are a list of things to fetch and sound in order.
    function playList(refs) {
        if (refs.length === 0)
            return;
        deenRoot.playQueue = refs;
        deenRoot.playFailures = 0;
        deenRoot.playIndex = 0;
        startAudio(refs[0]);
        prefetch(1);
    }

    /// Recite the whole surah, Basmala first where there is one — because that
    /// is how a surah is recited, and `deen` already tells us which surahs have
    /// one (Al-Fatiha's is its first ayah, At-Tawbah has none).
    function playSurah() {
        playList((deenRoot.surahBasmala !== "" ? ["1:1"] : []).concat(deenRoot.surahAyahs.map(a => a.s + ":" + a.a)));
    }

    /// Recite a chapter of adhkar. The duas with no recitation matched to them
    /// are left OUT of the queue rather than left in to fail: three failures in
    /// a row stops playback, and a chapter with two unmatched duas in it would
    /// otherwise stop halfway through for a reason nobody could see.
    function playChapter() {
        playList(deenRoot.duaList.filter(d => d.chapter === deenRoot.duaChapter && d.audio !== undefined).map(d => "dua:" + d.id));
    }

    /// Move a running recitation to another ayah. Tapping a number while the
    /// surah plays means "from here", not "just this one".
    function playFrom(reference) {
        const i = deenRoot.playQueue.indexOf(reference);
        if (i < 0) {
            playAudio(reference);
            return;
        }
        deenRoot.playFailures = 0;
        deenRoot.playIndex = i;
        startAudio(reference);
        prefetch(i + 1);
    }

    function stopPlayback() {
        // THE INDEX IS CLEARED FIRST, and the order is load-bearing: `onExited`
        // advances the queue, and an empty index is the only thing that tells
        // it this exit was a stop rather than the end of an ayah.
        deenRoot.playIndex = -1;
        deenRoot.playQueue = [];
        audioProc.running = false;
        deenRoot.playing = "";
    }

    /// Fetch the next ayah's audio while this one plays, so a second listen has
    /// no gap at all. `deen audio` caches and answers a path; ignoring the path
    /// is the whole of the prefetch.
    function prefetch(i) {
        if (i < 0 || i >= deenRoot.playQueue.length)
            return;
        prefetchProc.running = false;
        prefetchProc.command = ["setpriv", "--pdeathsig", "TERM", "--", "deen", "audio", deenRoot.playQueue[i]];
        prefetchProc.running = true;
    }

    Process {
        id: audioProc

        running: false

        onExited: exitCode => {
            // A newer play already took the process over — this is the corpse
            // of the one it replaced, and it does not get to clear the
            // highlight belonging to its successor.
            if (audioProc.running)
                return;
            deenRoot.playing = "";
            if (!deenRoot.playingQueue)
                return;
            deenRoot.playFailures = exitCode === 0 ? 0 : deenRoot.playFailures + 1;
            const next = deenRoot.playIndex + 1;
            if (deenRoot.playFailures >= 3 || next >= deenRoot.playQueue.length) {
                deenRoot.stopPlayback();
                return;
            }
            deenRoot.playIndex = next;
            deenRoot.startAudio(deenRoot.playQueue[next]);
            deenRoot.prefetch(next + 1);
        }
    }

    Process {
        id: prefetchProc

        running: false
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
        // A surah reciting itself to a closed window is the same bug as a
        // microphone left open, in the other direction.
        stopPlayback();
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

    // `qs ipc call deen duas` — the day's adhkar, on the morning chapter.
    function duas() {
        show();
        deenRoot.view = "duas";
    }

    // `qs ipc call deen hadith "seeking forgiveness"` — search from anywhere.
    function hadith(query) {
        show();
        deenRoot.view = "hadith";
        const q = String(query || "").trim();
        if (q !== "")
            searchHadith(q);
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
        if (deenRoot.view === "hifz") {
            hifzScreen.toggleRecording();
            return;
        }
        // Anywhere else, the pedal means Recite — and it has to SHOW Recite
        // first. Pressed from the reader it used to start a recording against
        // a screen that is not on screen, which is the bug `reciteAyah` had.
        deenRoot.view = "recite";
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
                if (duasScreen.sheetOpen) {
                    duasScreen.closeSheet();
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
            // Named rather than excluded: every room added since has been one
            // more `!==` on this line, and the hadith screen would have been
            // the one where a space in the search box starts a recording.
            enabled: !recite.editingReference && (deenRoot.view === "recite" || deenRoot.view === "hifz")
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
                            },
                            {
                                id: "duas",
                                label: "DUAS"
                            },
                            {
                                id: "hadith",
                                label: "HADITH"
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
                    playingSurah: deenRoot.playingQueue
                    onSurahStepped: delta => deenRoot.mushafSurah = Math.max(1, Math.min(114, deenRoot.mushafSurah + delta))
                    onSurahPicked: n => deenRoot.mushafSurah = n
                    onPlay: reference => deenRoot.playAudio(reference)
                    onPlayFrom: reference => deenRoot.playFrom(reference)
                    onPlaySurah: deenRoot.playSurah()
                    onStopPlayback: deenRoot.stopPlayback()
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

                DuasScreen {
                    id: duasScreen

                    anchors.fill: parent
                    visible: deenRoot.view === "duas"
                    style: deenRoot.style
                    source: deenRoot.duaSource
                    chapters: deenRoot.duaChapters
                    duas: deenRoot.duaList
                    chapter: deenRoot.duaChapter
                    loadError: deenRoot.duaError
                    playing: deenRoot.playing
                    playingSet: deenRoot.playingQueue
                    onChapterStepped: delta => deenRoot.duaChapter = Math.max(1, Math.min(deenRoot.duaChapters.length || 132, deenRoot.duaChapter + delta))
                    onChapterPicked: n => deenRoot.duaChapter = n
                    onPlay: reference => deenRoot.playAudio(reference)
                    onPlayFrom: reference => deenRoot.playFrom(reference)
                    onPlayChapter: deenRoot.playChapter()
                    onStopPlayback: deenRoot.stopPlayback()
                }

                HadithScreen {
                    id: hadithScreen

                    anchors.fill: parent
                    visible: deenRoot.view === "hadith"
                    style: deenRoot.style
                    source: deenRoot.hadithSource
                    collections: deenRoot.hadithCollections
                    hits: deenRoot.hadithHits
                    total: deenRoot.hadithTotal
                    query: deenRoot.hadithQuery
                    collection: deenRoot.hadithCollection
                    searching: deenRoot.hadithSearching
                    loadError: deenRoot.hadithError
                    onSearched: q => deenRoot.searchHadith(q)
                    onCollectionPicked: slug => deenRoot.setHadithCollection(slug)
                    onOpened: url => deenRoot.openUrl(url)
                }
            }

            Toast {
                id: toast

                style: deenRoot.style
            }
        }
    }
}
