import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import "." as Root
import "services" as Services
import "lib/lock-look.mjs" as L
import "lib/lease.mjs" as Lease
import "lib/lock-pam.mjs" as Pam

// The session lock: a WlSessionLock cannot live in the Overlay host, so it is the one surface outside it.
Scope {
    id: screenLock

    required property var theme
    property int failures: 0
    // Length of the focused field's text; the text itself never leaves the field.
    property int field: 0
    property real shakeX: 0
    // The submitted text, held only until PAM asks for it.
    property string pending: ""
    // A failed attempt can end in both completed and error, and counts once.
    property bool trying: false
    // An agent's lease on the unlocked session, in ms since the epoch; heldBy is empty when none holds.
    property string heldBy: ""
    property real unlockedAt: 0
    property real leaseUntil: 0
    readonly property bool leased: heldBy !== ""
    // The compositor's lock state: session.locked set back to false in accept() never notifies a binding, so presence follows this.
    readonly property bool secure: session.secure
    // How often an agent unlock asked niri to turn the monitors off, so a check can see the request.
    property int monitorsOff: 0
    // The day's other passage, walked back from the paper's; shell.qml sets it after the paper's first frame, so a lock before then draws none.
    property var passage: null

    // Every surface's field clears on this, so no screen keeps a typed password.
    signal cleared

    // A shell restarted while locked may start before the theme loads, and the lock must draw anyway.
    readonly property var c: theme.tokens ? theme.color : L.FALLBACK
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({ display: "", ui: "" })
    readonly property var look: L.lockLook(theme.tokens, Quickshell.env("USER") || "")
    // The clock a lock surface drew last, so state() reports what is on screen rather than the lookup.
    property Item clockItem: null
    property Item fieldItem: null
    property Item dateItem: null
    property Item passageItem: null
    // just dev points this at a fake, so no check messages the phone.
    readonly property string notifyPhone: Quickshell.env("DOTS_NOTIFY_PHONE") || Quickshell.shellDir + "/bin/dots-notify-phone"
    readonly property string marker: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/locked"

    // The marker goes down before the lock does, so a shell killed at any point after this relocks on restart.
    function lockNow() {
        endLease();
        // FileView skips a write of the text it last wrote, so each lock writes its own time.
        markerFile.setText(new Date().toISOString() + "\n");
        session.locked = true;
    }

    function submit(text) {
        cleared();
        if (trying)
            return;
        if (text === "") {
            shake.restart();
            return;
        }
        pending = text;
        trying = true;
        if (!pam.start())
            reject();
    }

    function reject() {
        if (!trying)
            return;
        trying = false;
        pending = "";
        failures += 1;
        shake.restart();
    }

    // Only a PAM success gets here, and one for an attempt an agent's unlock already ended changes nothing, or it would empty the lease's marker; the marker empties after the lock goes, so a crash in between relocks, and through the lock's own synchronous write, so a lock right after cannot lose its marker to a late rm.
    function accept() {
        if (!trying)
            return;
        trying = false;
        pending = "";
        session.locked = false;
        markerFile.setText("");
    }

    function endLease() {
        heldBy = "";
        unlockedAt = 0;
        leaseUntil = 0;
    }

    // An agent's unlock: no PAM, the same release order as accept(), but the marker keeps the lease, so a shell killed mid-lease relocks on restart.
    function leaseUnlock(who, minutes) {
        if (!session.locked)
            return JSON.stringify({ error: "not locked" });
        const name = Lease.holder(who);
        const m = Lease.minutesOf(minutes);
        const now = Date.now();
        cleared();
        trying = false;
        pending = "";
        heldBy = name;
        unlockedAt = now;
        leaseUntil = Lease.leaseEnd(now, now, m);
        console.info(Lease.unlockLine(name, m));
        session.locked = false;
        darken.restart();
        Quickshell.execDetached([notifyPhone, "Agent unlock by " + name, "holds the session for " + m + " min, until " + Qt.formatTime(new Date(leaseUntil), "HH:mm")]);
        markerFile.setText("lease " + name + " until " + new Date(leaseUntil).toISOString() + "\n");
        return stateText();
    }

    function renewLease(who, minutes) {
        if (!leased)
            return JSON.stringify({ error: "no lease" });
        const name = Lease.holder(who);
        const m = Lease.minutesOf(minutes);
        heldBy = name;
        leaseUntil = Lease.leaseEnd(unlockedAt, Date.now(), m);
        console.info("lock: lease renewed by " + name + " for " + m + " min");
        return stateText();
    }

    function stateText() {
        const t = clockItem;
        const p = t ? t.mapToItem(null, 0, 0) : null;
        const f = fieldItem && fieldItem.visible ? fieldItem : null;
        const r = f ? f.mapToItem(null, 0, 0) : null;
        // A drawn item's box in window pixels, or null when it is hidden or not made.
        const box = item => {
            if (!item || !item.visible)
                return null;
            const at = item.mapToItem(null, 0, 0);
            return { x: at.x, y: at.y, w: item.width, h: item.height };
        };
        return JSON.stringify({
            locked: session.locked,
            secure: session.secure,
            heldBy: heldBy,
            unlockedAt: unlockedAt,
            leaseUntil: leaseUntil,
            monitorsOff: monitorsOff,
            field: field,
            failures: failures,
            shaking: shake.running,
            look: look.kind,
            clockFamily: t ? t.font.family : "",
            clockPx: t ? t.font.pixelSize : 0,
            clockWeight: t ? t.font.weight : 0,
            clockFill: t ? String(t.color) : "",
            clockStroke: t && t.style === Text.Outline ? String(t.styleColor) : "transparent",
            clockBox: t ? { x: p.x, y: p.y, w: t.width, h: t.height } : null,
            fieldBox: f ? { x: r.x, y: r.y, w: f.width, h: f.height } : null,
            dateText: dateItem ? dateItem.text : "",
            dateBox: box(dateItem),
            passage: passage && passage.pick ? { kind: passage.pick.kind, entry: passage.pick.entry, box: box(passageItem) } : null
        });
    }

    // niri lights the monitors as it unlocks, so they go dark a moment after, and nothing shows on an empty desk.
    Root.Tick {
        id: darken
        interval: 1000
        onTriggered: {
            screenLock.monitorsOff += 1;
            Quickshell.execDetached(["niri", "msg", "action", "power-off-monitors"]);
        }
    }

    // Runs only while a lease holds; the lease's end locks.
    Root.Tick {
        interval: 1000
        repeat: true
        running: screenLock.leased
        onTriggered: {
            if (Date.now() >= screenLock.leaseUntil)
                screenLock.lockNow();
        }
    }

    Root.Ipc {
        target: "lock"

        function lock(): void {
            screenLock.lockNow();
        }

        function unlock(who: string, minutes: string): string {
            return screenLock.leaseUnlock(who, minutes);
        }

        function renew(who: string, minutes: string): string {
            return screenLock.renewLease(who, minutes);
        }

        function state(): string {
            return screenLock.stateText();
        }
    }

    // Read once at start: a marker with a time in it, left by a killed shell, means niri still holds the lock; an unlock leaves it empty.
    FileView {
        id: markerFile
        path: screenLock.marker
        blockLoading: true
        blockWrites: true
        printErrors: false
        onLoaded: {
            if (text().trim() !== "")
                session.locked = true;
        }
    }

    // PAM's other service refuses every password, so with no dots-lock installed the lock uses login rather than shutting the user out.
    FileView {
        id: pamService
        path: pam.configDirectory + "/dots-lock"
        blockLoading: true
        printErrors: false
    }

    PamContext {
        id: pam
        config: pamService.loaded ? "dots-lock" : "login"
        configDirectory: Pam.pamDir(Quickshell.env("DOTS_PAM_DIR"), Quickshell.env("DOTS_DEV_DIR"))
        // A second prompt gets an empty answer, which no password matches.
        onPamMessage: {
            if (responseRequired) {
                respond(screenLock.pending);
                screenLock.pending = "";
            }
        }
        onCompleted: result => {
            if (result === PamResult.Success)
                screenLock.accept();
            else
                screenLock.reject();
        }
        onError: screenLock.reject()
    }

    SequentialAnimation {
        id: shake
        NumberAnimation { target: screenLock; property: "shakeX"; to: -14; duration: 50 }
        NumberAnimation { target: screenLock; property: "shakeX"; to: 12; duration: 70 }
        NumberAnimation { target: screenLock; property: "shakeX"; to: -8; duration: 70 }
        NumberAnimation { target: screenLock; property: "shakeX"; to: 5; duration: 70 }
        NumberAnimation { target: screenLock; property: "shakeX"; to: 0; duration: 60 }
    }

    WlSessionLock {
        id: session

        WlSessionLockSurface {
            id: surface
            color: surface.look.ground

            readonly property var look: screenLock.look
            readonly property string date: Qt.formatDate(clock.now, look.date.format)

            Services.Clock {
                id: clock
            }

            // No card: the clock and date high on the bare ground.
            Column {
                id: face
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(surface.height * 0.2)
                spacing: 6

                Text {
                    id: clockText
                    objectName: "lockClock"
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(clock.now, "HH:mm")
                    color: surface.look.clock.fill
                    font.family: surface.look.clock.family
                    font.pixelSize: surface.look.clock.px
                    font.weight: Font.Bold
                    font.letterSpacing: surface.look.clock.tracking
                    Component.onCompleted: screenLock.clockItem = clockText
                }

                Text {
                    id: dateText
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: surface.date
                    color: surface.look.date.color
                    font.family: surface.look.date.family
                    font.pixelSize: surface.look.date.px
                    Component.onCompleted: screenLock.dateItem = dateText
                }
            }

            // Centred between the date and the field, and smaller as a whole where it would crowd them.
            Loader {
                id: words
                readonly property real start: face.y + face.height + 48
                readonly property real room: entry.y - 48 - start
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(start + (room - height) / 2)
                scale: item ? Math.min(1, room / height) : 1
                active: screenLock.passage !== null && screenLock.passage.text !== null
                opacity: status === Loader.Ready ? 1 : 0
                Behavior on opacity {
                    NumberAnimation { duration: 400 }
                }
                Component.onCompleted: screenLock.passageItem = words

                sourceComponent: Root.LockPassage {
                    look: surface.look.passage
                    text: screenLock.passage.text
                }
            }

            Column {
                id: entry
                x: Math.round((surface.width - width) / 2) + screenLock.shakeX
                y: surface.height - height - 72
                width: 320
                spacing: 12

                Item {
                    width: parent.width
                    height: 44

                    // A quiet pill, framed in line, that takes the accent once something is typed.
                    Rectangle {
                        id: well
                        anchors.fill: parent
                        radius: height / 2
                        color: Qt.tint(surface.look.ground, Qt.alpha(screenLock.c.ink, 0.05))
                        border.width: 1
                        border.color: screenLock.field > 0 ? screenLock.c.accent : screenLock.c.line ?? screenLock.c.muted
                        Component.onCompleted: screenLock.fieldItem = well
                    }

                    TextInput {
                        id: input
                        anchors.centerIn: parent
                        width: parent.width - 32
                        horizontalAlignment: TextInput.AlignHCenter
                        color: screenLock.c.ink
                        font.family: screenLock.fonts.ui
                        font.pixelSize: 16
                        font.letterSpacing: 4.8
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        cursorDelegate: Rectangle {
                            width: 2
                            color: screenLock.c.accent
                        }
                        focus: true
                        clip: true
                        onTextChanged: screenLock.field = text.length
                        Keys.onReturnPressed: screenLock.submit(text)
                        Keys.onEnterPressed: screenLock.submit(text)
                        // Waking a blanked screen can stall niri until a key's release arrives late, so a repeat types nothing; Backspace and Delete keep theirs to clear a field.
                        Keys.onPressed: event => {
                            if (event.isAutoRepeat && event.key !== Qt.Key_Backspace && event.key !== Qt.Key_Delete)
                                event.accepted = true;
                        }
                        Component.onCompleted: forceActiveFocus()

                        Connections {
                            target: screenLock
                            function onCleared() {
                                input.text = "";
                            }
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: surface.look.hint
                    color: screenLock.c.muted
                    font.family: screenLock.fonts.ui
                    font.pixelSize: 12
                }
            }
        }
    }
}
