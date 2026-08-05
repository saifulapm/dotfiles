import QtQuick
import "../components"
import "DropboxModel.js" as Format

// rclone-remote panel — ours, in the Dropbox panel's visual language
// (omarchy's design; CREDITS.md), grown out of the iCloud panel and reshaped
// to the user's sketch (2026-08-06): the hero IS the mount surface — the
// instance's mark, the name over the mount path, a folder button and the
// on/off switch on the trailing edge — followed by a STORAGE section exactly
// when the backend's `rclone about` answered with quota (dropbox does;
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
    // The actionable targets, in reading order: the hero switch always, the
    // hero folder button only once there is a folder to open, the re-auth
    // row only while a failed probe holds it up.
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

    // -------------------------------------------------------------- content
    Column {
        id: sections

        width: parent.width
        spacing: panel.theme.space(3)

        // ------------------------------------------------------------ hero
        // The hero is the whole mount surface (user redesign, 2026-08-06):
        // the mark, the name over the mount path, a folder button, and the
        // switch on the trailing edge — no MOUNT section repeating any of it.
        Item {
            id: hero

            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight, folderAction.implicitHeight)

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

            // Open folder, as just the folder — dimmed while there is no
            // mounted folder to open.
            GlyphAction {
                id: folderAction
                anchors.right: powerSwitch.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰉋" // md-folder
                enabled: panel.service.mounted
                hasCursor: panel.hasCursorOn("open")
                hint: "Open folder"
                onHovered: panel.setCursorOn("open")
                onActivated: panel.service.openFolder()
            }

            Column {
                id: heroLabels

                anchors.left: heroIcon.right
                anchors.leftMargin: panel.theme.space(3)
                anchors.right: folderAction.left
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
                    width: parent.width
                    text: panel.service.mountPoint === "" ? "—" : panel.service.mountPoint
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                    elide: Text.ElideMiddle
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

    // The dropbox panel's PanelActionButton: a bordered square holding one
    // glyph, dimmed while it has nothing to act on, with the shared cursor
    // border when the keyboard is on it.
    component GlyphAction: Rectangle {
        id: glyphAction

        property string glyph: ""
        property bool enabled: true
        property bool hasCursor: false
        property string hint: ""

        signal hovered
        signal activated

        implicitWidth: panel.theme.space(8)
        implicitHeight: panel.theme.space(7)
        radius: panel.theme.radius(0.75)
        color: glyphHover.hovered && glyphAction.enabled ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2
        border.width: panel.theme.borderWidth
        border.color: glyphAction.hasCursor && glyphAction.enabled ? panel.theme.alpha(panel.theme.accent, 0.6) : panel.theme.surface3
        opacity: glyphAction.enabled ? 1 : 0.45

        OpticalGlyph {
            anchors.centerIn: parent
            text: glyphAction.glyph
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(1.083)
        }

        HoverHandler {
            id: glyphHover
            cursorShape: glyphAction.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
            onHoveredChanged: if (hovered && glyphAction.enabled)
                glyphAction.hovered()
        }

        TapHandler {
            enabled: glyphAction.enabled
            onTapped: glyphAction.activated()
        }

        Hint {
            visible: glyphHover.hovered && glyphAction.enabled && glyphAction.hint !== ""
            anchor: glyphAction
            text: glyphAction.hint
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
