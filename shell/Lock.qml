import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import Quickshell.Services.UPower
import QtQuick
import QtQuick.Effects
import "." as Root
import "services" as Services
import "lib/lock-look.mjs" as L
import "lib/lease.mjs" as Lease
import "lib/hifi.mjs" as H
import "lib/margins.mjs" as M

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
    // hostFile loads after start, and text() alone gives the binding nothing to follow, so loaded makes it read again.
    readonly property var look: L.lockLook(theme.tokens, Quickshell.env("USER") || "", hostFile.loaded ? hostFile.text().trim() : "")
    // The clock a lock surface drew last, so state() reports what is on screen rather than the lookup.
    property Item clockItem: null
    property Item dialItem: null
    property Item fieldItem: null
    property Item labelItem: null
    // Hi-Fi's top row reads the words the margins show; the desk's Power service is not made here, so its low-battery notice is not sent twice.
    readonly property string meter: [network.wifi, UPower.displayDevice.ready && UPower.displayDevice.isLaptopBattery && UPower.displayDevice.isPresent ? M.batteryText(UPower.displayDevice.percentage, UPower.displayDevice.state === UPowerDeviceState.Charging) : ""].filter(w => w !== "").join(" ").toUpperCase()
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
        const d = dialItem && dialItem.visible ? dialItem : null;
        const q = d ? d.mapToItem(null, 0, 0) : null;
        const f = fieldItem && fieldItem.visible ? fieldItem : null;
        const r = f ? f.mapToItem(null, 0, 0) : null;
        const l = labelItem && labelItem.visible ? labelItem : null;
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
            host: look.host ?? "",
            fieldMarks: look.fieldMarks ?? [],
            clockFamily: t ? t.font.family : "",
            clockPx: t ? t.font.pixelSize : 0,
            clockWeight: t ? t.font.weight : 0,
            clockFill: t ? String(t.color) : "",
            clockStroke: t && t.style === Text.Outline ? String(t.styleColor) : "transparent",
            clockBox: t ? { x: p.x, y: p.y, w: t.width, h: t.height } : null,
            dialBox: d ? { x: q.x, y: q.y, w: d.width, h: d.height } : null,
            fieldBox: f ? { x: r.x, y: r.y, w: f.width, h: f.height } : null,
            label: l ? l.text : ""
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

    // Blueprint's sheet caption names the machine, like a drawing's title block, and so does Hi-Fi's receiver front.
    FileView {
        id: hostFile
        path: "/etc/hostname"
        printErrors: false
    }

    Services.Network {
        id: network
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

            // Frost's heavier frost over the whole screen; the other locks pass no tokens, so they draw no paper shader.
            Root.PaperFill {
                anchors.fill: parent
                tokens: surface.kind === "frost" ? screenLock.theme.tokens : null
                dir: screenLock.theme.dir
                frostStart: surface.look.paper?.start ?? 0.8
                veinAlpha: surface.look.paper?.vein ?? 0
                grainAlpha: surface.look.paper?.grain ?? 0
            }

            // Hi-Fi's walnut cheeks, a dark grain line every 9 px and a faint light one between.
            Repeater {
                model: surface.kind === "receiver" ? 2 : 0

                Rectangle {
                    required property int index
                    x: index === 0 ? 0 : surface.width - 32
                    width: 32
                    height: surface.height
                    color: H.HIFI.walnut

                    Repeater {
                        model: 7

                        Rectangle {
                            required property int index
                            x: index % 2 === 0 ? index / 2 * 9 : (index - 1) / 2 * 9 + 5
                            width: 1
                            height: parent.height
                            color: index % 2 === 0 ? Qt.alpha("black", 0.2) : Qt.alpha(screenLock.c.ink, 0.04)
                        }
                    }
                }
            }

            Root.Lamp {
                visible: surface.kind === "receiver"
                tokens: screenLock.theme.tokens
                light: "red"
                x: 56
                y: Math.round(statusText.y + (statusText.height - height) / 2)
            }

            Text {
                id: statusText
                textFormat: Text.PlainText
                x: surface.kind === "receiver" ? 69 : surface.kind === "frost" ? 24 : 32
                y: 16
                text: surface.look.status.text
                color: surface.look.status.color
                font.family: screenLock.fonts.ui
                font.pixelSize: surface.kind === "card" ? 12 : surface.kind === "frost" ? 13 : 11
                font.weight: surface.kind === "card" ? Font.DemiBold : Font.Normal
                font.letterSpacing: surface.kind === "card" || surface.kind === "frost" ? 0 : 1.32
            }

            Text {
                visible: surface.kind === "receiver"
                textFormat: Text.PlainText
                anchors.right: parent.right
                anchors.rightMargin: 56
                y: 16
                text: screenLock.meter
                color: screenLock.c.muted
                font.family: screenLock.fonts.ui
                font.pixelSize: 11
                font.letterSpacing: 1.32
            }

            // Hi-Fi's dial window: the machine's name over it, a tuning scale and the clock lit inside it.
            Text {
                visible: surface.kind === "receiver"
                textFormat: Text.PlainText
                anchors.horizontalCenter: parent.horizontalCenter
                y: dial.y - 38
                text: surface.look.host ?? ""
                color: screenLock.c.muted
                font.family: screenLock.fonts.ui
                font.pixelSize: 11
                font.letterSpacing: 3.3
            }

            Root.Glass {
                id: dial
                visible: surface.kind === "receiver"
                tokens: screenLock.theme.tokens
                x: Math.round((surface.width - width) / 2)
                y: Math.round(surface.height * 0.167)
                width: 960
                height: 320
                Component.onCompleted: screenLock.dialItem = dial

                Repeater {
                    model: ["88", "92", "96", "100", "104", "108"]

                    Text {
                        required property string modelData
                        required property int index
                        textFormat: Text.PlainText
                        x: 60 + index * (840 - width) / 5
                        y: 24
                        text: modelData
                        color: screenLock.c.muted
                        font.family: screenLock.fonts.ui
                        font.pixelSize: 11
                        font.letterSpacing: 1.32
                    }
                }

                Root.TuningScale {
                    tokens: screenLock.theme.tokens
                    x: 60
                    y: 48
                    width: 840
                    at: 0.64
                }
            }

            // Hi-Fi's knobs either side of the password field.
            Repeater {
                model: surface.kind === "receiver" ? ["TUNING", "VOLUME"] : []

                Column {
                    required property string modelData
                    required property int index
                    x: Math.round(surface.width / 2 + (index === 0 ? -398 : 398) - width / 2)
                    y: entry.y
                    spacing: 12

                    Rectangle {
                        anchors.horizontalCenter: parent.horizontalCenter
                        width: 80
                        height: 80
                        radius: 40
                        color: screenLock.c.surface ?? screenLock.c.paper
                        border.width: 1
                        border.color: screenLock.c.line ?? screenLock.c.muted

                        Item {
                            anchors.fill: parent
                            rotation: index === 0 ? -50 : 18

                            Rectangle {
                                x: 39
                                y: 8
                                width: 2
                                height: 16
                                color: screenLock.c.ink
                            }
                        }
                    }

                    Text {
                        anchors.horizontalCenter: parent.horizontalCenter
                        textFormat: Text.PlainText
                        text: modelData
                        color: screenLock.c.muted
                        font.family: screenLock.fonts.ui
                        font.pixelSize: 10
                        font.letterSpacing: 2
                    }
                }
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
                y: surface.kind === "card" ? card.y + 36 : surface.kind === "receiver" ? dial.y + 68 : Math.round(surface.height * (surface.kind === "sheet" || surface.kind === "frost" ? 0.22 : 0.167))
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
                    // One weight binding: font.bold writes the same weight, and of two bindings the later evaluated wins.
                    font.weight: surface.look.clock.weight === "light" ? Font.Light : surface.look.clock.bold ? Font.Bold : Font.Normal
                    font.letterSpacing: surface.look.clock.tracking
                    // Hi-Fi's clock glows like a lit display; the layer is made only for a look that asks for it.
                    layer.enabled: (surface.look.clock.glow ?? "") !== ""
                    layer.effect: MultiEffect {
                        shadowEnabled: true
                        shadowColor: surface.look.clock.glow || "transparent"
                        shadowOpacity: 0.45
                        shadowBlur: 1
                        blurMax: 18
                        shadowHorizontalOffset: 0
                        shadowVerticalOffset: 0
                    }
                    Component.onCompleted: screenLock.clockItem = clockText
                }

                Text {
                    visible: surface.kind === "print" || surface.kind === "receiver" || surface.kind === "frost"
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: surface.date
                    color: surface.look.date.color
                    font.family: surface.look.date.family
                    font.italic: surface.look.date.italic
                    font.pixelSize: surface.look.date.px
                    font.letterSpacing: surface.look.date.tracking
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
                readonly property bool centred: surface.kind !== "print" && surface.kind !== "frost"
                x: Math.round((surface.width - width) / 2) + screenLock.shakeX
                y: surface.kind === "card" ? face.y + face.height + 22 : surface.kind === "receiver" ? dial.y + dial.height + 90 : Math.round(surface.height * (surface.kind === "sheet" ? 0.71 : surface.kind === "frost" ? 0.55 : 0.69))
                width: surface.kind === "card" || surface.kind === "frost" ? 380 : 400
                spacing: surface.kind === "sheet" || surface.kind === "receiver" ? 12 : surface.kind === "frost" ? 8 : 10

                Text {
                    id: promptText
                    visible: surface.look.prompt !== ""
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: entry.centred ? Text.AlignHCenter : Text.AlignLeft
                    text: surface.look.prompt
                    color: screenLock.c.muted
                    font.family: screenLock.fonts.ui
                    font.pixelSize: surface.kind === "frost" ? 13 : 10
                    font.letterSpacing: surface.kind === "sheet" || surface.kind === "receiver" ? 2 : surface.kind === "frost" ? 0 : 1.6
                    Component.onCompleted: screenLock.labelItem = promptText
                }

                Item {
                    width: parent.width
                    height: surface.kind === "card" ? 46 : surface.kind === "receiver" ? 48 : surface.kind === "frost" ? 50 : input.implicitHeight

                    // Frost's field is glass over the frost: a fill only, since a session lock surface is no layer niri can blur behind.
                    Rectangle {
                        id: glassField
                        visible: surface.kind === "frost"
                        anchors.fill: parent
                        radius: screenLock.theme.tokens?.niri.radius ?? 10
                        color: screenLock.c.glass ?? screenLock.c.surface ?? "transparent"
                        border.width: 1
                        border.color: screenLock.c.edge ?? screenLock.c.line ?? "transparent"
                        Component.onCompleted: screenLock.fieldItem = glassField

                        Rectangle {
                            id: unlockChip
                            anchors.right: parent.right
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            width: chipText.implicitWidth + 24
                            height: 34
                            radius: 7
                            color: Qt.alpha(screenLock.c.accent, 0.16)

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: surface.look.hint
                                color: surface.look.dots ?? screenLock.c.ink
                                font.family: screenLock.fonts.ui
                                font.pixelSize: 13
                                font.weight: Font.Medium
                            }
                        }
                    }

                    // Hi-Fi's field is a glass well.
                    Root.Glass {
                        visible: surface.kind === "receiver"
                        tokens: screenLock.theme.tokens
                        anchors.centerIn: parent
                        width: 320
                        height: 48
                    }

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
                        model: surface.kind === "sheet" ? surface.look.fieldMarks : []

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
                        // Frost's dots start 16 px in and stop 12 px short of the chip.
                        anchors.horizontalCenterOffset: surface.kind === "frost" ? (16 - 12 - unlockChip.width - 8) / 2 : 0
                        width: surface.kind === "sheet" || surface.kind === "receiver" ? 240 : surface.kind === "card" ? parent.width - 32 : surface.kind === "frost" ? parent.width - 16 - 12 - unlockChip.width - 8 : parent.width
                        horizontalAlignment: entry.centred ? TextInput.AlignHCenter : TextInput.AlignLeft
                        color: surface.kind === "sheet" || surface.kind === "receiver" ? screenLock.c.accent : surface.look.dots ?? screenLock.c.ink
                        font.family: screenLock.fonts.ui
                        font.pixelSize: surface.kind === "card" ? 16 : 20
                        font.letterSpacing: surface.kind === "card" ? 4.8 : surface.kind === "frost" ? 3.6 : 7
                        echoMode: TextInput.Password
                        inputMethodHints: Qt.ImhSensitiveData | Qt.ImhNoPredictiveText
                        // Blueprint's and Hi-Fi's cursor is a block, the others a 2 px bar.
                        cursorDelegate: Rectangle {
                            width: surface.kind === "sheet" ? 11 : surface.kind === "receiver" ? 9 : 2
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

                // Frost's hint is the chip inside its field.
                Text {
                    visible: surface.kind !== "frost"
                    textFormat: Text.PlainText
                    width: parent.width
                    horizontalAlignment: entry.centred ? Text.AlignHCenter : Text.AlignLeft
                    text: surface.look.hint
                    color: screenLock.c.muted
                    font.family: surface.kind === "print" ? screenLock.fonts.display : screenLock.fonts.ui
                    font.italic: surface.kind === "print"
                    font.pixelSize: surface.kind === "print" ? 16 : surface.kind === "card" ? 12 : 10
                    font.letterSpacing: surface.kind === "sheet" ? 1.6 : surface.kind === "receiver" ? 2 : 0
                }
            }
        }
    }
}
