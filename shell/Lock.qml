import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import "." as Root
import "services" as Services
import "lib/lock-look.mjs" as L
import "lib/lease.mjs" as Lease

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

    // Every surface's field clears on this, so no screen keeps a typed password.
    signal cleared

    // A shell restarted while locked may start before the theme loads, and the lock must draw anyway.
    readonly property var c: theme.tokens ? theme.color : L.FALLBACK
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({ display: "", ui: "" })
    readonly property var look: L.lockLook(theme.tokens, Quickshell.env("USER") || "")
    // The clock a lock surface drew last, so state() reports what is on screen rather than the lookup.
    property Item clockItem: null
    property Item fieldItem: null
    property Item statusItem: null
    // just dev points this at a fake, so no check messages the phone.
    readonly property string notifyPhone: Quickshell.env("DOTS_NOTIFY_PHONE") || Quickshell.shellDir + "/../bin/dots-notify-phone"
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
            statusText: statusItem ? statusItem.text : "",
            statusBox: box(statusItem)
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
        configDirectory: Quickshell.env("DOTS_PAM_DIR") || "/etc/pam.d"
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
            color: screenLock.c.paper

            readonly property var look: screenLock.look
            readonly property string date: Qt.formatDate(clock.now, look.date.format)

            Services.Clock {
                id: clock
            }

            Text {
                id: statusText
                textFormat: Text.PlainText
                x: 32
                y: 16
                text: surface.look.status.text
                color: surface.look.status.color
                font.family: screenLock.fonts.ui
                font.pixelSize: 12
                font.weight: Font.DemiBold
                Component.onCompleted: screenLock.statusItem = statusText
            }

            // Artboard's selected card: handles and outline come from Surface, the date is its frame label.
            Root.Surface {
                id: card
                x: Math.round((surface.width - width) / 2)
                y: Math.round(surface.height * 0.3)
                width: 460
                height: 36 + face.height + 22 + entry.height + 32
                tokens: screenLock.theme.tokens
                label: surface.date
            }

            Column {
                id: face
                anchors.horizontalCenter: parent.horizontalCenter
                y: card.y + 36
                spacing: 4

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
            }

            Column {
                id: entry
                x: Math.round((surface.width - width) / 2) + screenLock.shakeX
                y: face.y + face.height + 22
                width: 380
                spacing: 10

                Item {
                    width: parent.width
                    height: 46

                    // Artboard's field: a tinted rounded well with a 2 px accent ring.
                    Rectangle {
                        id: well
                        anchors.fill: parent
                        radius: 12
                        color: Qt.tint(screenLock.c.surface ?? "white", Qt.alpha(screenLock.c.ink, 0.05))
                        border.width: 2
                        border.color: screenLock.c.accent
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
