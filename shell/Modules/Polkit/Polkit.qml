import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.Polkit
import "../../components"
import "PolkitModel.js" as PolkitModel

// Polkit authentication agent — omarchy's polkit plugin design (CREDITS.md)
// on our tokens. The agent object is eager — it must be registered with
// polkit from startup or privileged prompts have no UI to land in. The
// dialog window loads only while a request is active (or closing out).
//
// Their face: one compact centered card holding a padlock and the password
// field — no title, no action id, no buttons — with the justification pill
// ("Authorize running 'X'") floating above it, a shake + "Wrong" flash +
// error border on a failed attempt, and a square card framing only the
// fingerprint glyph while PAM waits on an enrolled reader.
//
// The view renders SNAPSHOT properties (their resetSnapshot / syncFromFlow /
// beginFlow pattern), not the flow object: the flow dies before derived
// state re-evaluates, so binding on it directly logged null-property
// TypeErrors on every cancel. The Connections target is `agentObj.flow`
// itself — null while idle, which just disables it.
Scope {
    id: polkitRoot

    required property var theme

    readonly property var agent: agentObj
    readonly property bool active: agentObj.isActive && agentObj.flow !== null

    // ---------------------------------------------------- snapshot state
    property bool closing: false
    property bool submitted: false
    property string currentMessage: ""
    property string currentPrompt: ""
    property string currentSupplementary: ""
    property bool responseRequired: false
    property bool responseVisible: false
    property bool failed: false
    property bool errorFlash: false
    // pam_fprintd appears in the effective polkit PAM auth stack (a sensor is
    // enrolled and wired in).
    property bool fingerprintConfigured: false
    // Lid shut right now — the reader is physically unreachable, so we fall
    // back to the password even when a sensor is enrolled. Refreshed per
    // request.
    property bool laptopClosed: false
    property int shakeOffset: 0

    // Dev-only: force the fingerprint presentation so the square card can be
    // rendered on hardware with no enrolled reader (fprintd-list on this Mac:
    // "No devices available"). It overrides the response gate too, because
    // without pam_fprintd PAM asks for the password immediately and the
    // waiting state the square card exists for never occurs.
    readonly property bool devFingerprint: Quickshell.env("QSHELL_DEV_FINGERPRINT") === "1"

    readonly property bool dialogVisible: agentObj.isActive || closing
    // One method shows at a time. Fingerprint owns the dialog while PAM is
    // waiting on the reader (lid open, sensor enrolled); the moment PAM asks
    // for a password — including immediately when the lid is shut and the
    // clamshell gate skips pam_fprintd — the password field takes over.
    readonly property bool fingerprintMode: devFingerprint ? (dialogVisible && !laptopClosed) : (fingerprintConfigured && !laptopClosed && dialogVisible && !responseRequired && !submitted && !errorFlash)

    // Their design constants through our spacing token: upstream sizes this
    // card in Style.space(px) — px times the theme's scale — and our
    // theme.space(n) is n space units of 4 px, so px/4 is the multiplier
    // that renders identically at default density and moves with a theme's
    // density the way theirs moves with [spacing] scale. fieldHeight is
    // their space(42); contentMargin their panelPadding default (space(18),
    // ours was space(16) — a real drop); edgeMargin their gapsOut*2 screen
    // clamp (10 at their defaults).
    readonly property int fieldHeight: theme.space(10.5)
    readonly property int contentMargin: theme.space(4.5)
    readonly property int edgeMargin: theme.space(2.5)
    readonly property int borderThickness: theme.polkit.borderWidth

    function refreshLidState() {
        if (!laptopClosedProc.running)
            laptopClosedProc.running = true;
    }

    function refreshPamConfig() {
        if (!pamStackProc.running)
            pamStackProc.running = true;
    }

    function resetSnapshot() {
        currentMessage = "";
        currentPrompt = "";
        currentSupplementary = "";
        responseRequired = false;
        responseVisible = false;
        failed = false;
        errorFlash = false;
        submitted = false;
        clearPasswordField();
    }

    function syncFromFlow() {
        const flow = agentObj.flow;
        if (!flow)
            return;
        currentMessage = String(flow.message || "Authentication is needed...");
        currentPrompt = String(flow.inputPrompt || "");
        currentSupplementary = String(flow.supplementaryMessage || "");
        responseRequired = !!flow.isResponseRequired;
        responseVisible = !!flow.responseVisible;
        failed = !!flow.failed;
        if (responseRequired)
            submitted = false;
    }

    function beginFlow() {
        closeTimer.stop();
        closing = false;
        submitted = false;
        clearPasswordField();
        refreshLidState();
        refreshPamConfig();
        syncFromFlow();
        Qt.callLater(refocus);
    }

    function submitResponse(text) {
        const flow = agentObj.flow;
        if (!flow || !flow.isResponseRequired)
            return;
        submitted = true;
        errorFlash = false;
        flow.submit(text);
        clearPasswordField();
        parkFocus();
    }

    function cancelRequest() {
        const flow = agentObj.flow;
        clearPasswordField();
        submitted = false;
        closing = true;
        closeTimer.restart();
        if (flow)
            flow.cancelAuthenticationRequest();
    }

    // The IPC entry point: without the active guard, a cancel with no flow
    // up would raise the (empty) dialog for the closing grace period.
    function cancel() {
        if (active)
            cancelRequest();
    }

    function triggerFailureFeedback() {
        submitted = false;
        errorFlash = true;
        clearPasswordField();
        errorTimer.restart();
        shakeAnimation.restart();
        Qt.callLater(refocus);
    }

    // Typing clears the failure: the first keystroke during the flash ends
    // it early instead of leaving the field dead until the timer runs out.
    function clearErrorFlash() {
        if (!errorFlash)
            return;
        errorTimer.stop();
        errorFlash = false;
    }

    // The field lives inside the loaded window, so everything that touches
    // it goes through the loader item and no-ops while the dialog is down.
    function clearPasswordField() {
        if (dialogLoader.item)
            dialogLoader.item.clearPassword();
    }

    function refocus() {
        if (dialogLoader.item)
            dialogLoader.item.refocus();
    }

    function parkFocus() {
        if (dialogLoader.item)
            dialogLoader.item.parkFocus();
    }

    Component.onCompleted: refreshPamConfig()

    Timer {
        id: closeTimer
        interval: 300
        repeat: false
        onTriggered: {
            polkitRoot.closing = false;
            polkitRoot.resetSnapshot();
        }
    }

    Timer {
        id: errorTimer
        interval: 1200
        repeat: false
        onTriggered: polkitRoot.errorFlash = false
    }

    SequentialAnimation {
        id: shakeAnimation

        NumberAnimation {
            target: polkitRoot
            property: "shakeOffset"
            to: -8
            duration: 35
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: polkitRoot
            property: "shakeOffset"
            to: 8
            duration: 50
            easing.type: Easing.InOutQuad
        }
        NumberAnimation {
            target: polkitRoot
            property: "shakeOffset"
            to: 0
            duration: 55
            easing.type: Easing.OutQuad
        }
    }

    // Upstream reads /etc/pam.d/polkit-1 whole and watches it. Fedora splits
    // the stack: the vendor file lives in /usr/lib/pam.d (an /etc/pam.d file
    // of the same name overrides it) and carries only `auth include
    // system-auth` — pam_fprintd lands in system-auth when authselect
    // enables fingerprint. So the probe assembles the effective stack (the
    // service file plus one level of auth include/substack) and runs at
    // startup and again per request, which also covers the edits a file
    // watch on one path would miss.
    Process {
        id: pamStackProc
        command: ["bash", "-c", "f=/etc/pam.d/polkit-1; [ -r \"$f\" ] || f=/usr/lib/pam.d/polkit-1; [ -r \"$f\" ] || exit 0; cat \"$f\"; awk '$1==\"auth\" && ($2==\"include\" || $2==\"substack\") {print $3}' \"$f\" | while read -r svc; do for d in /etc/pam.d /usr/lib/pam.d; do if [ -r \"$d/$svc\" ]; then cat \"$d/$svc\"; break; fi; done; done"]
        stdout: StdioCollector {
            id: pamStackOut
            waitForEnd: true
        }
        onExited: polkitRoot.fingerprintConfigured = PolkitModel.fingerprintConfiguredFromPamConfig(String(pamStackOut.text || ""))
    }

    // Their omarchy-hw-laptop-closed reads /proc/acpi/button/lid/*/state,
    // which does not exist on Asahi (no ACPI) — logind's LidClosed property
    // is the source that answers here, fed by the "Apple SMC power/lid
    // events" input device. The ACPI path is kept first for the x86 machine.
    Process {
        id: laptopClosedProc
        command: ["bash", "-c", "for s in /proc/acpi/button/lid/*/state; do [ -r \"$s\" ] || continue; grep -qi closed \"$s\" && { echo closed; exit 0; }; done; v=$(busctl get-property org.freedesktop.login1 /org/freedesktop/login1 org.freedesktop.login1.Manager LidClosed 2>/dev/null); [ \"$v\" = \"b true\" ] && echo closed || echo open"]
        stdout: StdioCollector {
            id: laptopClosedOut
            waitForEnd: true
        }
        onExited: polkitRoot.laptopClosed = String(laptopClosedOut.text || "").trim() === "closed"
    }

    PolkitAgent {
        id: agentObj

        // Own a namespaced object path instead of quickshell's default
        // (omarchy's /org/omarchy/PolkitAgent).
        path: "/org/qshell/PolkitAgent"

        onAuthenticationRequestStarted: polkitRoot.beginFlow()
        onIsActiveChanged: {
            if (isActive)
                polkitRoot.syncFromFlow();
            else if (!polkitRoot.closing)
                polkitRoot.resetSnapshot();
        }
        onIsRegisteredChanged: {
            if (isRegistered)
                // console.info, not .log — .log is suppressed at the default
                // log level and the line would never appear.
                console.info("Polkit: agent registered");
            else
                console.warn("Polkit: agent is not registered; another agent may be running");
        }
    }

    Connections {
        target: agentObj.flow

        function onIsResponseRequiredChanged() {
            polkitRoot.syncFromFlow();
            if (!agentObj.flow || !agentObj.flow.isResponseRequired)
                polkitRoot.clearPasswordField();
            Qt.callLater(polkitRoot.refocus);
        }

        function onInputPromptChanged() {
            polkitRoot.syncFromFlow();
        }

        function onResponseVisibleChanged() {
            polkitRoot.syncFromFlow();
        }

        function onSupplementaryMessageChanged() {
            polkitRoot.syncFromFlow();
        }

        function onFailedChanged() {
            polkitRoot.syncFromFlow();
        }

        function onAuthenticationFailed() {
            polkitRoot.syncFromFlow();
            polkitRoot.triggerFailureFeedback();
        }

        function onAuthenticationSucceeded() {
            polkitRoot.closing = true;
            closeTimer.restart();
        }

        function onAuthenticationRequestCancelled() {
            polkitRoot.closing = true;
            closeTimer.restart();
        }
    }

    Loader {
        id: dialogLoader
        active: polkitRoot.dialogVisible

        sourceComponent: PanelWindow {
            id: panel
            visible: true
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.namespace: "qshell-polkit"

            // Asking for exclusive keyboard focus in the layer surface's
            // FIRST commit does not get it: the dialog rendered, the field
            // held active focus, and every keystroke went somewhere else —
            // there was not even a caret. Mapping with None and flipping to
            // Exclusive one tick later is what actually takes the keyboard,
            // and is what every other overlay here does by accident (they
            // are all built closed and then opened). Verified on screen:
            // without the flip the password field never blinks a caret,
            // with it the caret is there.
            property bool wantsKeyboard: false
            WlrLayershell.keyboardFocus: wantsKeyboard ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
            Component.onCompleted: Qt.callLater(() => {
                wantsKeyboard = true;
                refocus();
            })

            // Password mode is a wide field; fingerprint mode collapses to a
            // square that just frames the centered sensor glyph (theirs:
            // cardWidth = cardHeight).
            readonly property int cardHeight: height > 0 ? Math.min(polkitRoot.fieldHeight + polkitRoot.contentMargin * 2, height - polkitRoot.edgeMargin * 2) : polkitRoot.fieldHeight + polkitRoot.contentMargin * 2
            // Their 260–312 px clamp, scaled: space(65)..space(78).
            readonly property int cardWidth: polkitRoot.fingerprintMode ? cardHeight : Math.min(polkitRoot.theme.space(78), Math.max(polkitRoot.theme.space(65), width - polkitRoot.edgeMargin * 2))

            function refocus() {
                // In fingerprint mode there is no field to type into — park
                // focus on the key catcher so Escape still cancels.
                if (polkitRoot.fingerprintMode)
                    keyCatcher.forceActiveFocus();
                else
                    passwordInput.forceActiveFocus();
            }

            function parkFocus() {
                keyCatcher.forceActiveFocus();
            }

            function clearPassword() {
                passwordInput.text = "";
            }

            // Card-shaped compositor blur behind the glass fill; the scrim
            // around it stays a plain dim (see BarPanel.qml).
            BackgroundEffect.blurRegion: polkitRoot.theme.blurActive ? cardBlurRegion : null

            Region {
                id: cardBlurRegion
                item: card
                radius: card.radius

                Region {
                    item: justificationPill.visible ? justificationPill : null
                    radius: justificationPill.radius
                }
            }

            Rectangle {
                anchors.fill: parent
                color: polkitRoot.theme.polkit.scrim
            }

            MouseArea {
                anchors.fill: parent
                onClicked: panel.refocus()
            }

            Rectangle {
                id: card
                width: panel.cardWidth
                height: panel.cardHeight
                radius: polkitRoot.theme.radius(1)
                anchors.centerIn: parent
                anchors.horizontalCenterOffset: polkitRoot.shakeOffset
                color: polkitRoot.theme.polkit.background
                // The error state is always a solid color, so a failed
                // attempt goes back to the plain Rectangle border even under
                // a gradient theme (the LockView rule).
                border.width: cardBorder.active ? 0 : polkitRoot.borderThickness
                border.color: polkitRoot.errorFlash ? polkitRoot.theme.polkit.borderError : polkitRoot.theme.polkit.border

                MouseArea {
                    anchors.fill: parent
                    onClicked: panel.refocus()
                }

                Item {
                    id: keyCatcher
                    anchors.fill: parent
                    focus: true

                    Keys.priority: Keys.BeforeItem
                    Keys.onPressed: event => {
                        if (event.key === Qt.Key_Escape) {
                            polkitRoot.cancelRequest();
                            event.accepted = true;
                        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
                            if (polkitRoot.responseRequired)
                                polkitRoot.submitResponse(passwordInput.text);
                            event.accepted = true;
                        }
                    }
                }

                // Fingerprint mode shows just the sensor glyph, centered and
                // alone — no padlock, no field, no prompt text.
                OpticalGlyph {
                    anchors.centerIn: parent
                    visible: polkitRoot.fingerprintMode
                    text: "󰈷"
                    fontFamily: polkitRoot.theme.fontUi
                    pixelSize: Math.round(polkitRoot.fieldHeight * 0.7)
                    color: polkitRoot.errorFlash ? polkitRoot.theme.polkit.textError : polkitRoot.theme.polkit.accent
                }

                Row {
                    id: cardRow
                    visible: !polkitRoot.fingerprintMode
                    anchors.fill: parent
                    // Their BorderSurface insets content by border + padding,
                    // so the field never sits under a wide border ring.
                    anchors.margins: polkitRoot.contentMargin + polkitRoot.borderThickness
                    spacing: polkitRoot.theme.space(3.5)

                    Item {
                        width: polkitRoot.theme.space(6.5)
                        height: polkitRoot.fieldHeight

                        // Their padlock is FontAwesome U+F023, which does not
                        // render under our Nerd Font fallback — md-lock is
                        // the MD-range stand-in.
                        OpticalGlyph {
                            anchors.centerIn: parent
                            text: "󰌾"
                            fontFamily: polkitRoot.theme.fontUi
                            pixelSize: polkitRoot.theme.fontPx(1.5)
                            color: polkitRoot.errorFlash ? polkitRoot.theme.polkit.textError : polkitRoot.theme.polkit.accent
                        }
                    }

                    Item {
                        width: parent.width - polkitRoot.theme.space(10)
                        height: polkitRoot.fieldHeight

                        TextInput {
                            id: passwordInput
                            anchors.fill: parent
                            verticalAlignment: TextInput.AlignVCenter
                            activeFocusOnPress: true
                            clip: true
                            selectionColor: polkitRoot.theme.alpha(polkitRoot.theme.polkit.accent, 0.45)
                            selectedTextColor: polkitRoot.theme.polkit.text
                            font.family: polkitRoot.theme.fontUi
                            font.pixelSize: polkitRoot.theme.fontPx(1.5)
                            echoMode: polkitRoot.responseVisible ? TextInput.Normal : TextInput.Password
                            passwordCharacter: "•"
                            color: polkitRoot.errorFlash ? polkitRoot.theme.polkit.textError : polkitRoot.theme.polkit.text
                            cursorVisible: activeFocus && !polkitRoot.submitted && !polkitRoot.errorFlash
                            readOnly: polkitRoot.submitted || polkitRoot.errorFlash
                            enabled: polkitRoot.dialogVisible
                            onAccepted: polkitRoot.submitResponse(text)
                            Keys.onPressed: event => {
                                if (event.key === Qt.Key_Escape) {
                                    polkitRoot.cancelRequest();
                                    event.accepted = true;
                                } else if (polkitRoot.errorFlash && event.text.length > 0) {
                                    // readOnly during the flash swallows the
                                    // keystroke itself; ending the flash here
                                    // lets the next one type.
                                    polkitRoot.clearErrorFlash();
                                }
                            }
                        }

                        StyledText {
                            theme: polkitRoot.theme
                            role: StyledText.Display

                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: polkitRoot.errorFlash ? "Wrong" : (polkitRoot.submitted ? "Checking..." : "Enter password")
                            color: polkitRoot.errorFlash ? polkitRoot.theme.polkit.textError : polkitRoot.theme.polkit.text
                            opacity: polkitRoot.errorFlash ? 1 : 0.36
                            elide: Text.ElideRight
                            visible: passwordInput.text.length === 0
                        }

                        Rectangle {
                            width: Math.max(1, polkitRoot.theme.space(0.5))
                            height: polkitRoot.theme.space(6)
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            color: polkitRoot.errorFlash ? polkitRoot.theme.polkit.textError : polkitRoot.theme.polkit.text
                            visible: passwordInput.activeFocus && passwordInput.text.length === 0 && !polkitRoot.submitted && !polkitRoot.errorFlash
                        }

                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton
                            onClicked: passwordInput.forceActiveFocus()
                        }
                    }
                }

                // A gradient [polkit] border draws as a ring; the plain
                // Rectangle border above stays in charge for solid themes.
                // On flash the spec KEY switches to border-error (omarchy's
                // rule), so a theme may gradient the error state too.
                GradientBorder {
                    id: cardBorder
                    anchors.fill: parent
                    z: 100
                    spec: polkitRoot.errorFlash ? polkitRoot.theme.polkit.borderErrorSpec : polkitRoot.theme.polkit.borderSpec
                    borderWidth: polkitRoot.borderThickness
                    cornerRadius: card.radius
                }
            }

            // The justification pill: polkit's boilerplate "Authentication is
            // needed to run '/usr/bin/x' as the super user" reduced to
            // "Authorize running '/usr/bin/x'", floating above the card.
            Rectangle {
                id: justificationPill
                width: Math.min(justificationText.implicitWidth + polkitRoot.theme.space(6), panel.width - polkitRoot.edgeMargin * 2)
                height: polkitRoot.theme.space(7)
                anchors.horizontalCenter: card.horizontalCenter
                anchors.bottom: card.top
                anchors.bottomMargin: polkitRoot.theme.space(2.5)
                radius: polkitRoot.theme.radius(1)
                color: polkitRoot.theme.polkit.background
                visible: justificationText.text.length > 0

                StyledText {
                    id: justificationText
                    theme: polkitRoot.theme
                    anchors.fill: parent
                    anchors.leftMargin: polkitRoot.theme.space(3)
                    anchors.rightMargin: polkitRoot.theme.space(3)
                    text: PolkitModel.authorizationLabel(polkitRoot.currentMessage)
                    color: polkitRoot.theme.polkit.text
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                    elide: Text.ElideMiddle
                }
            }
        }
    }
}
