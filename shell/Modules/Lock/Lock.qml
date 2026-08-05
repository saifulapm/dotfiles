import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Services.Pam

// Session lock: ext-session-lock-v1 via WlSessionLock, PAM auth via our own
// pam.d/qshell-lock config (auth include system-auth) — no /etc writes.
//
// Unlock happens ONLY through PAM success. forceUnlock() exists for the
// nested dev session and is IPC-reachable only when QSHELL_DEV=1.
Scope {
    id: lockRoot

    required property var theme

    readonly property bool locked: sessionLock.locked
    property bool authenticating: false
    property string errorText: ""
    property string _password: ""

    function lock() {
        errorText = "";
        sessionLock.locked = true;
    }

    function forceUnlock() {
        sessionLock.locked = false;
    }

    function submit(password) {
        if (authenticating || password === "")
            return;
        authenticating = true;
        errorText = "";
        _password = password;
        if (!pam.start()) {
            authenticating = false;
            errorText = "could not start authentication";
        }
    }

    PamContext {
        id: pam
        config: "qshell-lock"
        configDirectory: "pam.d"

        onResponseRequiredChanged: {
            if (responseRequired)
                respond(lockRoot._password);
        }

        onCompleted: result => {
            lockRoot._password = "";
            lockRoot.authenticating = false;
            if (result === PamResult.Success) {
                sessionLock.locked = false;
            } else if (result === PamResult.MaxTries) {
                lockRoot.errorText = "too many attempts — wait a moment";
            } else {
                lockRoot.errorText = "authentication failed";
            }
        }

        onError: e => {
            console.warn("Lock: pam error:", e);
        }
    }

    WlSessionLock {
        id: sessionLock

        WlSessionLockSurface {
            id: surface
            color: lockRoot.theme.surface0

            Column {
                anchors.centerIn: parent
                spacing: lockRoot.theme.space(6)

                SystemClock {
                    id: clock
                    precision: SystemClock.Minutes
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: lockRoot.theme.textPrimary
                    font.family: lockRoot.theme.fontMono
                    font.pixelSize: lockRoot.theme.fontPx(5)
                    text: Qt.formatDateTime(clock.date, "HH:mm")
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    color: lockRoot.theme.textMuted
                    font.family: lockRoot.theme.fontUi
                    font.pixelSize: lockRoot.theme.fontPx(1.1)
                    text: Qt.formatDateTime(clock.date, "dddd, d MMMM")
                }

                Rectangle {
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 260
                    height: lockRoot.theme.space(9)
                    radius: lockRoot.theme.radius(1)
                    color: lockRoot.theme.surface2
                    border.width: lockRoot.theme.borderWidth
                    border.color: lockRoot.errorText !== "" ? lockRoot.theme.error : (lockRoot.authenticating ? lockRoot.theme.accent : lockRoot.theme.surface3)

                    Behavior on border.color {
                        ColorAnimation {
                            duration: lockRoot.theme.time(1)
                            easing.type: lockRoot.theme.easing
                        }
                    }

                    TextInput {
                        id: passwordInput
                        anchors.fill: parent
                        anchors.leftMargin: lockRoot.theme.space(3)
                        anchors.rightMargin: lockRoot.theme.space(3)
                        verticalAlignment: TextInput.AlignVCenter
                        echoMode: TextInput.Password
                        passwordCharacter: "•"
                        color: lockRoot.theme.textPrimary
                        font.family: lockRoot.theme.fontMono
                        font.pixelSize: lockRoot.theme.fontPx(1.1)
                        enabled: !lockRoot.authenticating
                        focus: true

                        onAccepted: {
                            lockRoot.submit(text);
                            text = "";
                        }

                        Keys.onEscapePressed: text = ""

                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            visible: passwordInput.text === "" && !lockRoot.authenticating
                            color: lockRoot.theme.textMuted
                            font.family: lockRoot.theme.fontUi
                            font.pixelSize: lockRoot.theme.fontPx(1.0)
                            text: "password"
                        }
                    }
                }

                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    visible: lockRoot.errorText !== "" || lockRoot.authenticating
                    color: lockRoot.authenticating ? lockRoot.theme.textMuted : lockRoot.theme.error
                    font.family: lockRoot.theme.fontUi
                    font.pixelSize: lockRoot.theme.fontPx(0.917)
                    text: lockRoot.authenticating ? "checking…" : lockRoot.errorText
                }
            }
        }
    }
}
