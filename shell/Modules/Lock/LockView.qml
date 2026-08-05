import QtQuick
import QtQuick.Effects
import Quickshell
import Quickshell.Widgets

// The lock screen's face, split out of the service exactly as omarchy splits
// theirs (CREDITS.md): the session-lock surface and the preview overlay both
// mount this, so what a preview shows is what a lock shows.
//
// Their design, our tokens: a blurred copy of the current wallpaper under one
// centered password field. Upstream draws nothing else at all — the identity
// block above the field (avatar, time, date) is ours, and the field stays
// exactly where they put it so everything hangs off dead centre.
Item {
    id: root

    required property var theme

    property string backgroundPath: ""
    property int backgroundVersion: 0
    property bool fingerprintConfigured: false
    property bool authenticatingPassword: false
    property string failureMessage: ""
    property bool inputEnabled: true
    property bool loadBackground: true
    property string passwordText: ""
    property bool syncingPasswordText: false

    readonly property string placeholderText: "Enter Password"
    // The user's portrait, the conventional path a login manager reads. There
    // is no probe: Image reports Ready or Error, and Error simply means the
    // block collapses to the clock alone.
    readonly property string facePath: Quickshell.env("HOME") + "/.face"
    readonly property int avatarSize: 96
    readonly property int fieldWidth: 381
    readonly property int fieldHeight: 67
    readonly property int outlineThickness: 3
    readonly property int fieldFontSize: theme.fontPx(1.5)
    readonly property int passwordDotFontSize: theme.fontPx(1.773)
    readonly property int passwordDotLetterSpacing: Math.round(theme.fontPx(1.333) * 0.19)

    // Colors are the roles omarchy's [lock] theme section names, resolved
    // against our token schema: their background at 0.8 alpha, their
    // foreground-mixed placeholder (their own fallback recipe), accent for the
    // live border, error for the failed one.
    readonly property color fieldColor: theme.alpha(theme.surface1, 0.8)
    readonly property color textColor: theme.textPrimary
    readonly property color placeholderColor: theme.alpha(theme.textPrimary, 0.66)
    readonly property color textErrorColor: theme.error
    readonly property color borderActiveColor: theme.accent
    readonly property color borderErrorColor: theme.error
    readonly property color selectionColor: theme.alpha(theme.accent, 0.45)

    // Space to keep clear on each side of the field for the fingerprint icon
    // (icon width plus a gap) so the centered dots never run under it.
    readonly property real fingerprintReserve: fingerprintConfigured ? Math.round(fingerprintIcon.implicitWidth + 12) : 0
    // Shrink the dots to fit once the password outgrows the field, so every
    // keystroke stays visible — otherwise long passwords clip with no feedback.
    readonly property real passwordDotScale: dotMetrics.advanceWidth > 0 ? Math.min(1, (passwordInput.width - 4) / dotMetrics.advanceWidth) : 1
    readonly property bool showPasswordCursor: inputEnabled && !authenticatingPassword && failureMessage.length === 0
    readonly property bool errorState: failureMessage.length > 0

    signal submitPassword(string password)
    signal passwordTextEdited(string password)
    signal clearFailureRequested
    signal wakeRequested

    // Cache-busts the lock background by appending `?v=`. Adding a query
    // string keeps Image's loader happy while forcing it to reload when the
    // user picks a new background mid-session.
    function fileUrl(path) {
        if (!path)
            return "";
        const encoded = String(path).split("/").map(encodeURIComponent).join("/");
        return "file://" + encoded + "?v=" + backgroundVersion;
    }

    function forcePasswordFocus() {
        passwordInput.forceActiveFocus();
    }

    function clearPassword() {
        passwordTextEdited("");
    }

    function syncPasswordText() {
        if (passwordInput.text === passwordText)
            return;
        syncingPasswordText = true;
        passwordInput.text = passwordText;
        syncingPasswordText = false;
    }

    onPasswordTextChanged: syncPasswordText()
    onInputEnabledChanged: {
        if (inputEnabled)
            Qt.callLater(forcePasswordFocus);
    }

    Component.onCompleted: {
        syncPasswordText();
        if (inputEnabled)
            Qt.callLater(forcePasswordFocus);
    }

    // Only ticks while this view is up — the lock module is lazy, so nothing
    // here exists on an unlocked desktop.
    SystemClock {
        id: lockClock
        precision: SystemClock.Minutes
    }

    // Measures the masked password at full size; passwordDotScale compares this
    // against the field width to decide how far the dots must shrink to fit.
    TextMetrics {
        id: dotMetrics
        font.family: root.theme.fontUi
        font.pixelSize: root.passwordDotFontSize
        font.letterSpacing: root.passwordDotLetterSpacing
        text: "●".repeat(passwordInput.text.length)
    }

    Rectangle {
        anchors.fill: parent
        color: root.theme.surface1

        Image {
            id: wallpaper
            anchors.fill: parent
            source: root.loadBackground ? root.fileUrl(root.backgroundPath) : ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true
            cache: false
            sourceSize.width: width
            sourceSize.height: height
        }

        MultiEffect {
            anchors.fill: wallpaper
            source: wallpaper
            autoPaddingEnabled: false
            blurEnabled: root.loadBackground && wallpaper.status === Image.Ready
            blur: 1.0
            blurMax: 128
            blurMultiplier: 1.25
            contrast: -0.08
        }

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            onClicked: {
                root.wakeRequested();
                root.forcePasswordFocus();
            }
            onPositionChanged: root.wakeRequested()
        }

        // Ours, not omarchy's. Hangs off the field rather than sharing a
        // column with it, so the field itself stays dead centre whether or not
        // there is a portrait to draw.
        Column {
            id: identity

            anchors.horizontalCenter: inputField.horizontalCenter
            anchors.bottom: inputField.top
            anchors.bottomMargin: root.theme.space(10)
            spacing: root.theme.space(3)

            ClippingRectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                width: root.avatarSize
                height: root.avatarSize
                visible: face.status === Image.Ready
                color: "transparent"
                // Round on a rounded theme, square on a sharp one — the same
                // shape token every other surface in the shell reads.
                radius: root.theme.radiusBase > 0 ? width / 2 : 0
                border.width: root.outlineThickness
                border.color: root.borderActiveColor

                Image {
                    id: face
                    anchors.fill: parent
                    source: "file://" + root.facePath
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    cache: false
                    sourceSize.width: width
                    sourceSize.height: height
                }
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.textColor
                font.family: root.theme.fontMono
                font.pixelSize: root.theme.fontPx(5)
                text: Qt.formatDateTime(lockClock.date, "HH:mm")
            }

            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                color: root.placeholderColor
                font.family: root.theme.fontUi
                font.pixelSize: root.theme.fontPx(1.1)
                text: Qt.formatDateTime(lockClock.date, "dddd, d MMMM")
            }
        }

        Rectangle {
            id: inputField
            width: root.fieldWidth
            height: root.fieldHeight
            anchors.centerIn: parent
            color: root.fieldColor
            radius: root.theme.radius(1)
            border.width: root.outlineThickness
            border.color: root.errorState ? root.borderErrorColor : root.borderActiveColor
            clip: true

            Behavior on border.color {
                ColorAnimation {
                    duration: root.theme.time(1)
                    easing.type: root.theme.easing
                }
            }

            TextInput {
                id: passwordInput
                anchors.fill: parent
                anchors.topMargin: root.outlineThickness
                // Reserve the fingerprint icon's width on both sides so the
                // centered dots stay symmetric and never slide under the icon
                // as they grow.
                anchors.rightMargin: root.outlineThickness + 18 + root.fingerprintReserve
                anchors.bottomMargin: root.outlineThickness
                anchors.leftMargin: root.outlineThickness + 18 + root.fingerprintReserve
                verticalAlignment: TextInput.AlignVCenter
                horizontalAlignment: TextInput.AlignHCenter
                activeFocusOnPress: true
                clip: true
                enabled: root.inputEnabled && !root.authenticatingPassword
                readOnly: root.authenticatingPassword
                echoMode: TextInput.Password
                passwordCharacter: "●"
                passwordMaskDelay: 0
                color: root.textColor
                selectionColor: root.selectionColor
                selectedTextColor: root.textColor
                font.family: root.theme.fontUi
                font.pixelSize: text.length > 0 ? Math.max(1, Math.floor(root.passwordDotFontSize * root.passwordDotScale)) : root.fieldFontSize
                font.letterSpacing: text.length > 0 ? root.passwordDotLetterSpacing * root.passwordDotScale : 0
                cursorVisible: activeFocus && root.showPasswordCursor && text.length > 0

                cursorDelegate: Rectangle {
                    width: 2
                    color: root.textColor
                    visible: passwordInput.cursorVisible
                }

                onTextChanged: {
                    if (!root.syncingPasswordText)
                        root.passwordTextEdited(text);
                    if (text.length > 0)
                        root.wakeRequested();
                    if (text.length > 0 && root.failureMessage.length > 0)
                        root.clearFailureRequested();
                }

                onAccepted: {
                    const submitted = root.passwordText;
                    root.passwordTextEdited("");
                    if (submitted.length > 0)
                        root.submitPassword(submitted);
                }

                Keys.onPressed: event => {
                    root.wakeRequested();
                    if (event.key === Qt.Key_Escape || (event.modifiers & Qt.ControlModifier && event.key === Qt.Key_U)) {
                        root.passwordTextEdited("");
                        event.accepted = true;
                    }
                }
            }

            Text {
                anchors.fill: passwordInput
                text: root.authenticatingPassword ? "Checking…" : (root.failureMessage.length > 0 ? root.failureMessage : root.placeholderText)
                visible: passwordInput.text.length === 0
                color: root.authenticatingPassword ? root.textColor : (root.failureMessage.length > 0 ? root.textErrorColor : root.placeholderColor)
                font.family: root.theme.fontUi
                font.pixelSize: root.fieldFontSize
                font.italic: !root.authenticatingPassword && root.failureMessage.length > 0
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
                elide: Text.ElideRight
            }

            // Fingerprint hint pinned inside the field's right edge when a
            // sensor is enrolled, so the user knows they can touch to unlock
            // instead of typing. Matches hyprlock, which draws its fingerprint
            // icon in the same spot.
            Text {
                id: fingerprintIcon
                objectName: "fingerprintIndicator"
                anchors.right: parent.right
                anchors.rightMargin: root.outlineThickness + 18
                anchors.verticalCenter: parent.verticalCenter
                visible: root.fingerprintConfigured
                text: "󰈷"
                color: root.placeholderColor
                font.family: root.theme.fontUi
                font.pixelSize: Math.round(root.fieldFontSize * 1.1)
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
        }
    }
}
