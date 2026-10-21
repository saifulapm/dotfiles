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

    // Only a PAM success gets here; the marker empties after the lock goes, so a crash in between relocks, and through the lock's own synchronous write, so a lock right after cannot lose its marker to a late rm.
    // A success for an attempt an agent's unlock already ended changes nothing, or it would empty the lease's marker.
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
            clockFill: t ? String(t.color) : "",
            clockStroke: t && t.style === Text.Outline ? String(t.styleColor) : "transparent",
            clockBox: t ? { x: p.x, y: p.y, w: t.width, h: t.height } : null
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

    // Blueprint's sheet caption names the machine, like a drawing's title block.
    FileView {
        id: hostFile
        path: "/etc/hostname"
        printErrors: false
    }

    WlSessionLock {
        id: session

        WlSessionLockSurface {
            id: surface
            color: screenLock.c.paper

            readonly property var look: screenLock.look
            readonly property string kind: look.kind
            readonly property string date: {
                const d = Qt.formatDate(clock.now, look.date.format);
                return look.date.caps ? d.toUpperCase() : d;
            }

            Services.Clock {
                id: clock
            }

            Text {
                textFormat: Text.PlainText
                x: 32
                y: 16
                text: surface.look.status.text
                color: surface.look.status.color
                font.family: screenLock.fonts.ui
                font.pixelSize: surface.kind === "card" ? 12 : 11
                font.weight: surface.kind === "card" ? Font.DemiBold : Font.Normal
                font.letterSpacing: surface.kind === "card" ? 0 : 1.32
            }

            // Paper's running head: a ruled line under the status row.
            Rectangle {
                visible: surface.kind === "print"
                x: 32
                y: 40
                width: surface.width - 64
                height: 1
                color: screenLock.c.ink
            }

            // Blueprint's crop marks: a 14 px L in the accent, 8 px in from each corner.
            Repeater {
                model: surface.kind === "sheet" ? 4 : 0

                Item {
                    required property int index
                    readonly property bool atRight: index % 2 === 1
                    readonly property bool atBottom: index >= 2
                    x: atRight ? surface.width - 22 : 8
                    y: atBottom ? surface.height - 22 : 8
                    width: 14
                    height: 14

                    Rectangle {
                        x: parent.atRight ? 13 : 0
                        width: 1
                        height: 14
                        color: screenLock.c.accent
                    }

                    Rectangle {
                        y: parent.atBottom ? 13 : 0
                        width: 14
                        height: 1
                        color: screenLock.c.accent
                    }
                }
            }

            // Artboard's selected card: handles, outline and soft shadow come from Surface, the date is its frame label.
            Root.Surface {
                id: card
                visible: surface.kind === "card"
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
                y: surface.kind === "card" ? card.y + 36 : Math.round(surface.height * (surface.kind === "sheet" ? 0.22 : 0.167))
                spacing: surface.kind === "sheet" ? 18 : 4

                Text {
                    visible: surface.kind === "sheet"
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "SHEET 01 OF 01 · " + hostFile.text().trim().toUpperCase()
                    color: screenLock.c.muted
                    font.family: screenLock.fonts.ui
                    font.pixelSize: 11
                    font.letterSpacing: 3.3
                }

                Text {
                    id: clockText
                    objectName: "lockClock"
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(clock.now, "HH:mm")
                    color: surface.look.clock.fill
                    // An outline with a transparent fill draws the digits hollow.
                    style: surface.look.clock.stroke === "transparent" ? Text.Normal : Text.Outline
                    styleColor: surface.look.clock.stroke
                    font.family: surface.look.clock.family
                    font.pixelSize: surface.look.clock.px
                    font.bold: surface.look.clock.bold
                    font.letterSpacing: surface.look.clock.tracking
                    Component.onCompleted: screenLock.clockItem = clockText
                }

                Text {
                    visible: surface.kind === "print"
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: surface.date
                    color: surface.look.date.color
                    font.family: surface.look.date.family
                    font.italic: surface.look.date.italic
                    font.pixelSize: surface.look.date.px
                }

                // Blueprint's dimension line: end ticks, a rule each side and the date in the middle.
                Row {
                    visible: surface.kind === "sheet"
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 640
                    spacing: 12

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 12
                        color: screenLock.c.accent
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: (640 - 2 - 4 * 12 - dimDate.width) / 2
                        height: 1
                        color: screenLock.c.accent
                    }

                    Text {
                        id: dimDate
                        textFormat: Text.PlainText
                        text: surface.date
                        color: surface.look.date.color
                        font.family: surface.look.date.family
                        font.pixelSize: surface.look.date.px
                        font.letterSpacing: surface.look.date.tracking
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: (640 - 2 - 4 * 12 - dimDate.width) / 2
                        height: 1
                        color: screenLock.c.accent
                    }

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: 1
                        height: 12
                        color: screenLock.c.accent
                    }
                }
            }

            Column {
                id: entry
                readonly property bool centred: surface.kind !== "print"
                x: Math.round((surface.width - width) / 2) + screenLock.shakeX
                y: surface.kind === "card" ? face.y + face.height + 22 : Math.round(surface.height * (surface.kind === "sheet" ? 0.71 : 0.69))
                width: surface.kind === "card" ? 380 : 400
                spacing: surface.kind === "sheet" ? 12 : 10

                Text {
                    visible: surface.look.prompt !== ""
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: entry.centred ? Text.AlignHCenter : Text.AlignLeft
                    text: surface.look.prompt
                    color: screenLock.c.muted
                    font.family: screenLock.fonts.ui
                    font.pixelSize: 10
                    font.letterSpacing: surface.kind === "sheet" ? 2 : 1.6
                }

                Item {
                    width: parent.width
                    height: surface.kind === "card" ? 46 : input.implicitHeight

                    // Artboard's field: a tinted rounded well with a 2 px accent ring.
                    Rectangle {
                        visible: surface.kind === "card"
                        anchors.fill: parent
                        radius: 12
                        color: Qt.tint(screenLock.c.surface ?? "white", Qt.alpha(screenLock.c.ink, 0.05))
                        border.width: 2
                        border.color: screenLock.c.accent
                    }

                    // Blueprint brackets the field.
                    Repeater {
                        model: surface.kind === "sheet" ? ["[", "]"] : []

                        Text {
                            required property string modelData
                            required property int index
                            textFormat: Text.PlainText
                            anchors.verticalCenter: parent.verticalCenter
                            x: index === 0 ? 50 : parent.width - 50 - width
                            text: modelData
                            color: screenLock.c.accent
                            font.family: screenLock.fonts.ui
                            font.pixelSize: 20
                        }
                    }

                    TextInput {
                        id: input
                        anchors.centerIn: parent
                        width: surface.kind === "sheet" ? 240 : surface.kind === "card" ? parent.width - 32 : parent.width
                        horizontalAlignment: entry.centred ? TextInput.AlignHCenter : TextInput.AlignLeft
                        color: surface.kind === "sheet" ? screenLock.c.accent : screenLock.c.ink
                        font.family: screenLock.fonts.ui
                        font.pixelSize: surface.kind === "card" ? 16 : 20
                        font.letterSpacing: surface.kind === "card" ? 4.8 : 7
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        // Blueprint's cursor is a block, the others a 2 px bar.
                        cursorDelegate: Rectangle {
                            width: surface.kind === "sheet" ? 11 : 2
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

                Rectangle {
                    visible: surface.kind === "print"
                    width: parent.width
                    height: 1.5
                    color: screenLock.c.ink
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: entry.centred ? Text.AlignHCenter : Text.AlignLeft
                    text: surface.look.hint
                    color: screenLock.c.muted
                    font.family: surface.kind === "print" ? screenLock.fonts.display : screenLock.fonts.ui
                    font.italic: surface.kind === "print"
                    font.pixelSize: surface.kind === "print" ? 16 : surface.kind === "card" ? 12 : 10
                    font.letterSpacing: surface.kind === "sheet" ? 1.6 : 0
                }
            }
        }
    }
}
