import QtQuick
import "../components"
import "DropboxModel.js" as Format

// rclone-remote panel — ours, in the Dropbox panel's visual language
// (omarchy's design; CREDITS.md), grown out of the iCloud panel: a hero of
// the instance's mark over a rotating phrase, then a MOUNT section (the
// on/off switch, and the folder behind it), a STORAGE section exactly when
// the backend's `rclone about` answered with quota (dropbox does;
// iclouddrive cannot), and an ACCOUNT section (the remote, its reachability,
// and — when a probe has failed — the re-auth row). Re-authenticating an
// rclone session is interactive (Apple 2FA, Dropbox browser OAuth) and no
// shell process can drive it, so the row is a copyable command: the
// tailscale panel's notice-row precedent, tap to copy.
//
// The cursor model is the dropbox panel's simplified one: j/k (and the
// arrows) walk the actionable rows, Enter activates whatever is under the
// cursor, hover moves it, and the first press only reveals it. The letter
// keys are r (probe again), m (mount/unmount), o (open the folder) and
// c (copy the re-auth command).
BarPanel {
    id: panel

    required property var service

    panelTitle: ""
    cardWidth: 380

    // ------------------------------------------------------------- phrases
    property int phraseIndex: 0
    readonly property var activePhrases: {
        const fromConfig = panel.service.config ? panel.service.config.phrases : undefined;
        if (fromConfig && fromConfig.length > 0)
            return fromConfig;
        return ["Ferrying folders", "Drizzling data", "Raining files", "Seeding the cloud", "Minding memories", "Shuffling shards", "Polishing pixels", "Braiding bytes"];
    }
    readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

    readonly property string mountHint: service.mountActive ? "Unmount the " + service.label + " folder" : "Mount " + service.label + " at " + service.mountPoint

    readonly property string reachabilityText: {
        if (panel.service.checking)
            return "Checking…";
        if (panel.service.reachState === 1)
            return "Reachable";
        if (panel.service.reachState === -1)
            return "Unreachable";
        return "Not checked";
    }

    // Quota, when the last probe carried it (`rclone about` support).
    readonly property bool quotaVisible: panel.service.quotaSupported && panel.service.quotaTotal > 0 && panel.service.quotaUsed >= 0
    readonly property real quotaFraction: panel.quotaVisible ? Math.max(0, Math.min(1, panel.service.quotaUsed / panel.service.quotaTotal)) : 0

    // -------------------------------------------------------------- cursor
    // The actionable rows, top to bottom, as they currently exist: the mount
    // switch always, the folder only once there is a folder to open, the
    // re-auth row only while a failed probe holds it up.
    readonly property var cursorRows: {
        const rows = ["mount"];
        if (panel.service.mounted)
            rows.push("open");
        if (panel.service.lastProbeFailed)
            rows.push("reauth");
        return rows;
    }
    property int cursorIndex: 0
    property bool cursorActive: false

    function rowUnderCursor() {
        if (panel.cursorRows.length === 0)
            return "";
        return panel.cursorRows[Math.max(0, Math.min(panel.cursorIndex, panel.cursorRows.length - 1))];
    }

    function hasCursorOn(row) {
        return panel.cursorActive && panel.rowUnderCursor() === row;
    }

    function moveCursor(dy) {
        if (!panel.cursorActive) {
            panel.cursorActive = true;
            return;
        }
        panel.cursorIndex = Math.max(0, Math.min(panel.cursorRows.length - 1, panel.cursorIndex + dy));
    }

    function setCursorOn(row) {
        const index = panel.cursorRows.indexOf(row);
        if (index < 0)
            return;
        panel.cursorActive = true;
        panel.cursorIndex = index;
    }

    function activateCursor() {
        if (!panel.cursorActive) {
            panel.cursorActive = true;
            return;
        }
        const row = panel.rowUnderCursor();
        if (row === "mount")
            panel.toggleMount();
        else if (row === "open")
            panel.service.openFolder();
        else if (row === "reauth")
            panel.service.copyReauthCommand();
    }

    function toggleMount() {
        if (!panel.service.busy)
            panel.service.toggleMount();
    }

    onCursorRowsChanged: {
        if (panel.cursorIndex >= panel.cursorRows.length)
            panel.cursorIndex = Math.max(0, panel.cursorRows.length - 1);
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            panel.moveCursor(1);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            panel.moveCursor(-1);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            panel.activateCursor();
            break;
        case Qt.Key_R:
            panel.service.probe();
            break;
        case Qt.Key_M:
            panel.toggleMount();
            break;
        case Qt.Key_O:
            panel.service.openFolder();
            break;
        case Qt.Key_C:
            if (panel.service.lastProbeFailed)
                panel.service.copyReauthCommand();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------ lifecycle
    // Opening the panel is one of the two moments a network probe is allowed
    // (the other is an explicit refresh); the local facts ride along free.
    onPanelOpened: {
        panel.cursorActive = false;
        panel.cursorIndex = 0;
        panel.service.refreshLocal();
        panel.service.probe();
    }

    Timer {
        id: phraseTimer
        interval: 2800
        running: panel.opened && panel.service.mountActive
        repeat: true
        onTriggered: phraseSwap.restart()
    }

    SequentialAnimation {
        id: phraseSwap
        PropertyAnimation {
            target: heroMeta
            property: "opacity"
            to: 0.0
            duration: 180
            easing.type: Easing.OutQuad
        }
        ScriptAction {
            script: panel.phraseIndex = (panel.phraseIndex + 1) % panel.activePhrases.length
        }
        PropertyAnimation {
            target: heroMeta
            property: "opacity"
            to: 1.0
            duration: 260
            easing.type: Easing.InQuad
        }
    }

    // -------------------------------------------------------------- content
    Column {
        id: sections

        width: parent.width
        spacing: panel.theme.space(3)

        // ------------------------------------------------------------ hero
        // The switch rides the hero's trailing edge, as the dropbox and
        // tailscale heroes have it, and the subtitle is the rotating phrase
        // alone — the mount state already has a whole section saying it, so
        // an unmounted hero shows just the mark and the name (user redesign,
        // 2026-08-06).
        Item {
            id: hero

            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight)

            RcloneRemoteMark {
                id: heroIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                iconSize: panel.theme.fontPx(1.6)
                glyph: panel.service.config ? String(panel.service.config.glyph || "") : ""
                drawnMark: panel.service.config ? String(panel.service.config.drawnMark || "") : ""
                color: panel.service.mountActive ? panel.theme.textPrimary : panel.theme.textMuted
                opacity: panel.service.mountActive ? 1.0 : 0.5
            }

            // The service flips `mountActive` optimistically, so the knob
            // throws on the click rather than when the FUSE mount settles.
            ToggleSwitch {
                id: powerSwitch
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: panel.service.mountActive
                busy: panel.service.busy
                hasCursor: panel.hasCursorOn("mount")
                hint: panel.mountHint
                onHovered: panel.setCursorOn("mount")
                onToggled: panel.toggleMount()
            }

            Column {
                id: heroLabels

                anchors.left: heroIcon.right
                anchors.leftMargin: panel.theme.space(3)
                anchors.right: powerSwitch.left
                anchors.rightMargin: panel.theme.space(3)
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.5)

                Text {
                    width: parent.width
                    text: panel.service.label
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(1.083)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    id: heroMeta
                    visible: panel.service.mountActive
                    width: parent.width
                    text: panel.heroPhraseText
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.833)
                    elide: Text.ElideRight
                }
            }
        }

        // -------------------------------------------------- action/error
        Text {
            visible: panel.service.actionStatus !== "" || panel.service.lastError !== ""
            width: parent.width
            text: panel.service.actionStatus !== "" ? panel.service.actionStatus : panel.service.lastError
            color: panel.service.lastError !== "" && panel.service.actionStatus === "" ? panel.theme.error : panel.theme.textMuted
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.833)
            wrapMode: Text.WordWrap
        }

        // ----------------------------------------------------------- mount
        SectionHeader {
            text: "MOUNT"
        }

        CursorSurface {
            id: mountRow

            width: parent.width
            implicitHeight: mountInner.implicitHeight + panel.theme.space(3)
            hasCursor: panel.hasCursorOn("mount")

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: panel.setCursorOn("mount")
                onClicked: panel.toggleMount()
            }

            Item {
                id: mountInner

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.rightMargin: panel.theme.space(2.5)
                implicitHeight: mountLabels.implicitHeight

                Column {
                    id: mountLabels

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(0.25)

                    Text {
                        width: parent.width
                        text: panel.service.mountActive ? "Mounted" : "Not mounted"
                        color: panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.917)
                        elide: Text.ElideRight
                    }

                    Text {
                        width: parent.width
                        text: panel.service.mountPoint === "" ? "—" : panel.service.mountPoint
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontMono
                        font.pixelSize: panel.theme.fontPx(0.75)
                        elide: Text.ElideRight
                    }
                }
            }
        }

        CursorSurface {
            id: openRow

            visible: panel.service.mounted
            width: parent.width
            implicitHeight: visible ? openInner.implicitHeight + panel.theme.space(3) : 0
            hasCursor: panel.hasCursorOn("open")

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: panel.setCursorOn("open")
                onClicked: panel.service.openFolder()
            }

            Item {
                id: openInner

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.rightMargin: panel.theme.space(2.5)
                implicitHeight: Math.max(openGlyph.implicitHeight, openLabel.implicitHeight)

                OpticalGlyph {
                    id: openGlyph
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "󰉋" // md-folder
                    color: panel.theme.textPrimary
                    pixelSize: panel.theme.fontPx(1.083)
                }

                Text {
                    id: openLabel
                    anchors.left: openGlyph.right
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Open folder"
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    elide: Text.ElideRight
                }
            }
        }

        // --------------------------------------------------------- storage
        // Only for backends whose `about` answered with numbers — the
        // dropbox panel's "Stored" line over a fill bar. Omitted entirely
        // (header too) when the backend cannot say.
        SectionHeader {
            visible: panel.quotaVisible
            text: "STORAGE"
        }

        Column {
            visible: panel.quotaVisible
            width: parent.width
            spacing: panel.theme.space(1.5)

            InfoPair {
                label: "Stored"
                value: Format.usageText(panel.service.quotaUsed, panel.service.quotaTotal, true) + " (" + Format.formatPercent(panel.quotaFraction * 100) + ")"
            }

            Rectangle {
                width: parent.width
                height: panel.theme.space(1)
                radius: height / 2
                color: panel.theme.surface3

                Rectangle {
                    width: parent.width * panel.quotaFraction
                    height: parent.height
                    radius: parent.radius
                    color: panel.theme.accent
                }
            }
        }

        // --------------------------------------------------------- account
        SectionHeader {
            text: "ACCOUNT"
        }

        InfoPair {
            label: "Remote"
            value: panel.service.remote === "" ? "—" : panel.service.remote + ": · " + panel.service.remoteType
        }

        InfoPair {
            label: "Reachability"
            value: panel.reachabilityText
            valueColor: panel.service.reachState === -1 && !panel.service.checking ? panel.theme.error : panel.theme.textPrimary
        }

        // The re-auth row: a sentence about the one thing the shell cannot
        // fix by itself, over the command that fixes it. Tapping copies the
        // command — `rclone config reconnect` re-authenticates interactively
        // (Apple 2FA, Dropbox browser OAuth), so no button here could ever
        // run it.
        CursorSurface {
            id: reauthRow

            visible: panel.service.lastProbeFailed
            width: parent.width
            implicitHeight: visible ? reauthColumn.implicitHeight + panel.theme.space(3) : 0
            hasCursor: panel.hasCursorOn("reauth")
            color: panel.hasCursorOn("reauth") ? panel.theme.alpha(panel.theme.textPrimary, 0.06) : panel.theme.surface2

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onEntered: panel.setCursorOn("reauth")
                onClicked: panel.service.copyReauthCommand()
            }

            Hint {
                visible: reauthRow.hasCursor
                anchor: reauthRow
                text: "Copy command"
            }

            Column {
                id: reauthColumn

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                anchors.leftMargin: panel.theme.space(3)
                anchors.rightMargin: panel.theme.space(3)
                spacing: panel.theme.space(1)

                Text {
                    width: parent.width
                    text: panel.service.label + " did not answer — the session may have expired. Re-authenticate in a terminal (interactive):"
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.833)
                    wrapMode: Text.WordWrap
                }

                Text {
                    width: parent.width
                    text: panel.service.reauthCommand
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.833)
                    elide: Text.ElideRight
                }

                Text {
                    visible: panel.service.probeError !== ""
                    width: parent.width
                    text: panel.service.elideStatus(panel.service.probeError)
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }

    // ----------------------------------------------------------- components
    component SectionHeader: Text {
        color: panel.theme.textMuted
        font.family: panel.theme.fontMono
        font.pixelSize: panel.theme.fontPx(0.75)
        font.letterSpacing: 1.2
        font.weight: Font.DemiBold
    }

    component CursorSurface: Rectangle {
        property bool hasCursor: false

        radius: panel.theme.radius(0.75)
        color: hasCursor ? panel.theme.alpha(panel.theme.textPrimary, 0.06) : "transparent"
        border.width: panel.theme.borderWidth
        border.color: hasCursor ? panel.theme.alpha(panel.theme.accent, 0.6) : "transparent"
    }

    component InfoPair: Item {
        property string label: ""
        property string value: ""
        property color valueColor: panel.theme.textPrimary

        width: parent ? parent.width : 0
        implicitHeight: Math.max(pairLabel.implicitHeight, pairValue.implicitHeight)

        Text {
            id: pairLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: parent.label
            color: panel.theme.textPrimary
            opacity: 0.6
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.833)
        }

        Text {
            id: pairValue
            anchors.right: parent.right
            anchors.left: pairLabel.right
            anchors.leftMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            horizontalAlignment: Text.AlignRight
            elide: Text.ElideRight
            text: parent.value
            color: parent.valueColor
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.833)
        }
    }

    // Their ToggleSwitch, as ported for the network and dropbox panels.
    component ToggleSwitch: Rectangle {
        id: toggle

        property bool checked: false
        property bool hasCursor: false
        property bool busy: false
        property string hint: ""

        signal hovered
        signal toggled

        implicitWidth: panel.theme.space(10)
        implicitHeight: panel.theme.space(5.5)
        radius: height / 2
        color: checked ? panel.theme.accent : panel.theme.surface3
        border.width: panel.theme.borderWidth
        border.color: toggle.hasCursor ? panel.theme.accent : "transparent"
        opacity: toggle.busy ? 0.6 : 1

        Behavior on color {
            ColorAnimation {
                duration: panel.theme.time(0.5)
            }
        }

        Rectangle {
            y: (parent.height - height) / 2
            x: toggle.checked ? parent.width - width - (parent.height - height) / 2 : (parent.height - height) / 2
            width: parent.height - panel.theme.space(1.5)
            height: width
            radius: width / 2
            color: toggle.checked ? panel.theme.textOnAccent : panel.theme.textMuted

            Behavior on x {
                NumberAnimation {
                    duration: panel.theme.time(0.5)
                    easing.type: panel.theme.easing
                }
            }
        }

        HoverHandler {
            id: toggleHover
            cursorShape: Qt.PointingHandCursor
            onHoveredChanged: if (hovered)
                toggle.hovered()
        }

        TapHandler {
            onTapped: toggle.toggled()
        }

        Hint {
            visible: toggleHover.hovered && toggle.hint !== ""
            anchor: toggle
            text: toggle.hint
        }
    }

    // Their PanelToolTip, kept inside the card (NetworkPanel's).
    component Hint: Rectangle {
        id: hintBox

        property Item anchor: null
        property string text: ""

        parent: hintBox.anchor
        anchors.right: hintBox.anchor ? hintBox.anchor.right : undefined
        anchors.top: hintBox.anchor ? hintBox.anchor.bottom : undefined
        anchors.topMargin: panel.theme.space(1)
        width: hintLabel.implicitWidth + panel.theme.space(3)
        height: hintLabel.implicitHeight + panel.theme.space(2)
        radius: panel.theme.radius(0.75)
        color: panel.theme.surface2
        border.width: panel.theme.borderWidth
        border.color: panel.theme.surface3
        z: 10

        Text {
            id: hintLabel
            anchors.centerIn: parent
            text: hintBox.text
            color: panel.theme.textPrimary
            font.family: panel.theme.fontUi
            font.pixelSize: panel.theme.fontPx(0.833)
        }
    }
}
