import QtQuick
import QtQuick.Window
import Quickshell
import Quickshell.Io
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

    DeenApi {
        id: surahsReq
        onLoaded: data => deenRoot.surahs = data.surahs || []
    }

    property var ayah: null
    property string loadError: ""

    DeenApi {
        id: ayahReq
        onLoaded: data => {
            deenRoot.ayah = data.ayah || null;
            deenRoot.loadError = "";
        }
        onFailed: message => {
            deenRoot.ayah = null;
            deenRoot.loadError = message;
        }
    }

    onReferenceChanged: ayahReq.fetch(["ayah", deenRoot.reference])

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
            surahsReq.fetch(["surahs"]);
        // The surface is evictable, so a reopen after the grace period starts
        // from nothing and has to ask again; within it, the ayah is still here
        // and asking twice would be a process for an answer we hold.
        if (!deenRoot.ayah)
            ayahReq.fetch(["ayah", deenRoot.reference]);
        Qt.callLater(() => keyRoot.forceActiveFocus());
    }

    function didClose() {
        // A recitation in flight belongs to a panel that is no longer there.
        // Closing stdin is the same stop the button uses, so deen tears its
        // recording down and puts the microphone back the way it found it —
        // which matters more than the result nobody will now read.
        recite.stop();
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
    function reciteAyah(ref) {
        show();
        goTo(ref);
    }

    // The recitation pedal, reachable from outside the window as well as from
    // the button and Space. A keybind can start a recitation without the hub
    // having the keyboard, which is the difference between "press Recite, then
    // start reciting" and just reciting.
    function pedal() {
        show();
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
        Shortcut {
            sequence: "Escape"
            onActivated: deenRoot.hide()
        }

        // Space is the recitation pedal — start, then stop — but ONLY when the
        // reference field does not have the keyboard, or typing a space into
        // "1:1" would begin a recording.
        Shortcut {
            sequence: "Space"
            enabled: !recite.editingReference
            onActivated: recite.toggleRecording()
        }

        FocusScope {
            id: keyRoot

            anchors.fill: parent
            focus: true

            ReciteScreen {
                id: recite

                anchors.fill: parent
                style: deenRoot.style
                reference: deenRoot.reference
                ayah: deenRoot.ayah
                loadError: deenRoot.loadError
                onReferenceChanged_: ref => deenRoot.goTo(ref)
            }
        }
    }
}
