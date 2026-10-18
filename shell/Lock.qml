import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Pam
import QtQuick
import "services" as Services

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

    // Every surface's field clears on this, so no screen keeps a typed password.
    signal cleared

    // A shell restarted while locked may start before the theme loads, and the lock must draw anyway.
    readonly property var c: theme.tokens ? theme.color : ({ paper: "black", ink: "white", muted: "gray", accent: "white" })
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({ display: "", ui: "" })
    readonly property string marker: (Quickshell.env("XDG_STATE_HOME") || Quickshell.env("HOME") + "/.local/state") + "/dots/locked"

    // The marker goes down before the lock does, so a shell killed at any point after this relocks on restart.
    function lockNow() {
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

    // Only a PAM success gets here; the marker goes after the lock, so a crash in between relocks.
    function accept() {
        trying = false;
        pending = "";
        session.locked = false;
        Quickshell.execDetached(["rm", "-f", marker]);
    }

    IpcHandler {
        target: "lock"

        function lock(): void {
            screenLock.lockNow();
        }

        function state(): string {
            return JSON.stringify({
                locked: session.locked,
                secure: session.secure,
                field: screenLock.field,
                failures: screenLock.failures,
                shaking: shake.running
            });
        }
    }

    // Read once at start: a marker left by a killed shell means niri still holds the lock.
    FileView {
        id: markerFile
        path: screenLock.marker
        blockLoading: true
        blockWrites: true
        printErrors: false
        onLoaded: session.locked = true
    }

    PamContext {
        id: pam
        config: "dots-lock"
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

            Services.Clock {
                id: clock
            }

            Column {
                anchors.horizontalCenter: parent.horizontalCenter
                y: Math.round(surface.height * 0.2)
                spacing: 4

                Text {
                    objectName: "lockClock"
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatTime(clock.now, "HH:mm")
                    color: screenLock.c.ink
                    font.family: screenLock.fonts.display
                    font.pixelSize: Math.round(Math.min(220, surface.height / 4))
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: Qt.formatDate(clock.now, "dddd, d MMMM")
                    color: screenLock.c.muted
                    font.family: screenLock.fonts.display
                    font.italic: true
                    font.pixelSize: 30
                }
            }

            Column {
                x: Math.round((surface.width - width) / 2) + screenLock.shakeX
                y: Math.round(surface.height * 0.68)
                width: 400
                spacing: 10

                Text {
                    textFormat: Text.PlainText
                    text: "PASSWORD FOR " + (Quickshell.env("USER") || "").toUpperCase()
                    color: screenLock.c.muted
                    font.family: screenLock.fonts.ui
                    font.pixelSize: 10
                    font.letterSpacing: 1.6
                }

                TextInput {
                    id: input
                    width: parent.width
                    color: screenLock.c.ink
                    font.family: screenLock.fonts.ui
                    font.pixelSize: 20
                    font.letterSpacing: 7
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
                    Component.onCompleted: forceActiveFocus()

                    Connections {
                        target: screenLock
                        function onCleared() {
                            input.text = "";
                        }
                    }
                }

                Rectangle {
                    width: parent.width
                    height: 1.5
                    color: screenLock.c.ink
                }

                Text {
                    textFormat: Text.PlainText
                    text: "press return to unlock"
                    color: screenLock.c.muted
                    font.family: screenLock.fonts.display
                    font.italic: true
                    font.pixelSize: 16
                }
            }
        }
    }
}
