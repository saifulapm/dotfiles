import QtQuick
import "../components"
import "../../../components"
import "RcloneRemoteModel.js" as Format

// rclone-remote panel — ours, in the Dropbox panel's visual language
// (omarchy's design), grown out of the iCloud panel and reshaped
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
    cardWidth: theme.space(95)

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
        PanelHero {
            theme: panel.theme
            width: parent.width
            title: panel.service.label
            meta: panel.service.mountPoint === "" ? "—" : panel.service.mountPoint
            metaWeight: Font.Normal
            metaLetterSpacing: 0
            metaElide: Text.ElideMiddle

            icon: RcloneRemoteMark {
                iconSize: panel.theme.fontPx(1.6)
                glyph: panel.service.config ? String(panel.service.config.glyph || "") : ""
                drawnMark: panel.service.config ? String(panel.service.config.drawnMark || "") : ""
                color: panel.service.mountActive ? panel.theme.textPrimary : panel.theme.textMuted
                opacity: panel.service.mountActive ? 1.0 : 0.5
            }

            trailing: [
                // Open folder, as just the folder — dimmed while there is no
                // mounted folder to open.
                GlyphButton {
                    theme: panel.theme
                    anchors.verticalCenter: parent.verticalCenter
                    glyph: "󰉋" // md-folder
                    enabled: panel.service.mounted
                    hasCursor: panel.hasCursorOn("open")
                    hint: "Open folder"
                    onHovered: panel.setCursorOn("open")
                    onActivated: panel.service.openFolder()
                },
                // The service flips `mountActive` optimistically, so the knob
                // throws on the click rather than when the FUSE mount settles.
                PanelSwitch {
                    theme: panel.theme
                    anchors.verticalCenter: parent.verticalCenter
                    checked: panel.service.mountActive
                    busy: panel.service.busy
                    hasCursor: panel.hasCursorOn("mount")
                    hint: panel.mountHint
                    onHovered: panel.setCursorOn("mount")
                    onToggled: panel.toggleMount()
                }
            ]
        }

        // -------------------------------------------------- action/error
        StyledText {
            theme: panel.theme
            role: StyledText.Small

            visible: panel.service.actionStatus !== "" || panel.service.lastError !== ""
            width: parent.width
            text: panel.service.actionStatus !== "" ? panel.service.actionStatus : panel.service.lastError
            color: panel.service.lastError !== "" && panel.service.actionStatus === "" ? panel.theme.error : panel.theme.textMuted
            wrapMode: Text.WordWrap
        }

        // --------------------------------------------------------- storage
        // Only for backends whose `about` answered with numbers — the
        // dropbox panel's "Stored" line over a fill bar. Omitted entirely
        // (header too) when the backend cannot say.
        SectionHeader {
            theme: panel.theme
            width: parent.width
            visible: panel.quotaVisible
            label: "STORAGE"
        }

        Column {
            visible: panel.quotaVisible
            width: parent.width
            spacing: panel.theme.space(1.5)

            InfoPair {
                theme: panel.theme
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
            theme: panel.theme
            width: parent.width
            label: "ACCOUNT"
        }

        InfoPair {
            theme: panel.theme
            label: "Remote"
            value: panel.service.remote === "" ? "—" : panel.service.remote + ": · " + panel.service.remoteType
        }

        InfoPair {
            theme: panel.theme
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
            theme: panel.theme

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

            PanelHint {
                theme: panel.theme
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

                StyledText {
                    theme: panel.theme
                    role: StyledText.Small
                    muted: true

                    width: parent.width
                    text: panel.service.label + " did not answer — the session may have expired. Re-authenticate in a terminal (interactive):"
                    wrapMode: Text.WordWrap
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Small
                    mono: true

                    width: parent.width
                    text: panel.service.reauthCommand
                    elide: Text.ElideRight
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true
                    muted: true

                    visible: panel.service.probeError !== ""
                    width: parent.width
                    text: panel.service.elideStatus(panel.service.probeError)
                    wrapMode: Text.WrapAnywhere
                }
            }
        }
    }

    // ----------------------------------------------------------- components
}
