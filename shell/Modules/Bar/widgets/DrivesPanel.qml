import QtQuick
import "../components"
import "../../../components"
import "DrivesModel.js" as Model

// Drives panel — one card per removable drive, its volumes underneath, and
// the two actions that matter: open, and eject.
//
// The panel sets `drives.panelOpen` for its lifetime, which is what turns the
// 1 Hz throughput sampler on. That is deliberate and is the shell's approved
// "panels refreshing while open" exception: a transfer rate cannot be
// delivered by an event, and nothing samples while nobody is looking.
//
// EJECT IS NOT A REFUSAL. Asked while the kernel still has requests in
// flight, it is remembered and fires when the drive goes quiet — the button
// says "Eject when idle" and the row keeps showing the rate until it does.
// The alternative, failing with "target is busy", is what makes people pull
// sticks out early.
//
// Keys: j/k and the arrows walk the volumes, Enter mounts or opens, u
// unmounts, e ejects the drive the cursor is on, r re-probes.
BarPanel {
    id: panel

    required property var drives

    panelTitle: ""
    cardWidth: theme.space(95)

    readonly property var driveList: drives.drives || []

    // A flat walk over every volume of every drive, so one cursor index can
    // address the whole panel rather than needing a drive index and a volume
    // index that have to be kept in step.
    readonly property var flatRows: {
        const rows = [];
        for (const drive of driveList) {
            for (const volume of drive.volumes)
                rows.push({
                    drive: drive,
                    volume: volume
                });
        }
        return rows;
    }

    property int rowIndex: 0
    property bool cursorActive: false

    function moveCursor(dy) {
        cursorActive = true;
        if (flatRows.length === 0)
            return;
        rowIndex = Math.max(0, Math.min(flatRows.length - 1, rowIndex + dy));
    }

    function selected() {
        if (flatRows.length === 0)
            return null;
        return flatRows[Math.max(0, Math.min(rowIndex, flatRows.length - 1))];
    }

    function activateCursor() {
        if (!cursorActive) {
            cursorActive = true;
            return;
        }
        const row = selected();
        if (!row)
            return;
        // Enter is "do the obvious next thing": mount what is not mounted,
        // open what is.
        if (Model.isMounted(row.volume))
            panel.drives.openVolume(row.volume);
        else
            panel.drives.mountVolume(row.volume);
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            panel.moveCursor(panel.cursorActive ? 1 : 0);
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            panel.moveCursor(panel.cursorActive ? -1 : 0);
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            panel.activateCursor();
            break;
        case Qt.Key_U:
            if (panel.selected())
                panel.drives.unmountVolume(panel.selected().volume);
            break;
        case Qt.Key_E:
            if (panel.selected())
                panel.drives.eject(panel.selected().drive);
            break;
        case Qt.Key_R:
            panel.drives.refresh();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------ lifecycle
    onPanelOpened: {
        panel.cursorActive = false;
        panel.rowIndex = 0;
        panel.drives.panelOpen = true;
        panel.drives.refresh();
    }

    // Turning the sampler off is the whole reason this handler exists.
    onPanelClosed: panel.drives.panelOpen = false
    Component.onDestruction: panel.drives.panelOpen = false

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Drives"
        meta: panel.drives.heroMeta
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            text: "󰋊"
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.drives.busy ? panel.theme.warn : panel.theme.textPrimary
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.drives.lastError !== ""
        width: parent.width
        text: panel.drives.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
    }

    // --------------------------------------------------------------- drives
    Column {
        id: driveColumn

        width: parent.width
        spacing: panel.theme.space(2.5)

        Repeater {
            model: panel.driveList

            DriveCard {
                required property var modelData

                width: driveColumn.width
                drive: modelData
            }
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small
        muted: true

        visible: panel.driveList.length === 0
        width: parent.width
        text: "Nothing plugged in."
        wrapMode: Text.WordWrap
    }

    // --------------------------------------------------------------- footer
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        width: parent.width
        text: panel.drives.busy ? "Still writing. An eject asked for now will wait for the drive to go quiet." : "Eject unmounts every volume and powers the drive down."
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    component DriveCard: Column {
        id: card

        property var drive: null

        readonly property bool waiting: !!drive && panel.drives.pendingEject[drive.sys] === true
        readonly property bool driveBusy: Model.hasPendingIo(drive)

        spacing: panel.theme.space(1)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: card.drive ? card.drive.name.toUpperCase() : ""
            value: card.drive ? card.drive.size : ""
        }

        // The drive's own state line plus the eject control.
        Item {
            width: parent.width
            implicitHeight: Math.max(stateText.implicitHeight, ejectChip.implicitHeight)

            StyledText {
                id: stateText

                theme: panel.theme
                role: StyledText.Caption
                mono: true

                anchors.left: parent.left
                anchors.right: ejectChip.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                text: card.waiting ? "Ejecting when the drive goes quiet…" : Model.driveStateText(card.drive, panel.drives.rate)
                color: card.driveBusy || card.waiting ? panel.theme.warn : panel.theme.textMuted
                elide: Text.ElideRight
            }

            ChipSurface {
                id: ejectChip

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                theme: panel.theme
                implicitWidth: ejectLabel.implicitWidth + panel.theme.space(4)
                implicitHeight: panel.theme.space(7)
                pointerOver: ejectMouse.containsMouse

                StyledText {
                    id: ejectLabel

                    theme: panel.theme
                    role: StyledText.Caption
                    anchors.centerIn: parent
                    // The button says which of the two things is about to
                    // happen, rather than saying "Eject" and then quietly
                    // doing something else.
                    text: card.waiting ? "Cancel" : (card.driveBusy ? "Eject when idle" : "Eject")
                    color: panel.theme.textPrimary
                }

                MouseArea {
                    id: ejectMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        if (card.waiting)
                            panel.drives.cancelEject(card.drive.sys);
                        else
                            panel.drives.eject(card.drive);
                    }
                }

                PanelHint {
                    theme: panel.theme
                    visible: ejectMouse.containsMouse
                    anchor: ejectChip
                    above: true
                    text: card.waiting ? "Stop waiting and leave the drive mounted" : (card.driveBusy ? "Wait for the transfer, then power the drive down" : "Unmount everything and power the drive down")
                }
            }
        }

        // ------------------------------------------------------------ volumes
        Repeater {
            model: card.drive ? card.drive.volumes : []

            VolumeRow {
                required property var modelData

                width: card.width
                volume: modelData
                drive: card.drive
            }
        }
    }

    component VolumeRow: CursorSurface {
        id: row

        theme: panel.theme

        property var volume: null
        property var drive: null

        readonly property int flatIndex: panel.flatRows.findIndex(entry => entry.volume === row.volume)
        readonly property bool rowSelected: panel.cursorActive && panel.rowIndex === row.flatIndex
        readonly property bool mounted: Model.isMounted(volume)
        readonly property string holder: volume && panel.drives.holders[volume.parent] ? String(panel.drives.holders[volume.parent]) : ""

        hasCursor: rowSelected
        current: mounted
        implicitHeight: rowContent.implicitHeight + panel.theme.space(2.5)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse) {
                panel.cursorActive = true;
                if (row.flatIndex >= 0)
                    panel.rowIndex = row.flatIndex;
            }
            onClicked: {
                if (row.mounted)
                    panel.drives.openVolume(row.volume);
                else
                    panel.drives.mountVolume(row.volume);
            }
        }

        PanelHint {
            theme: panel.theme
            visible: rowMouse.containsMouse && !unmountMouse.containsMouse
            anchor: row
            above: true
            text: row.mounted ? "Open in the file manager" : "Mount"
        }

        Item {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: Math.max(rowMark.implicitHeight, rowLabels.implicitHeight, unmountChip.implicitHeight)

            OpticalGlyph {
                id: rowMark
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(5)
                text: row.mounted ? "󰝰" // md-folder_open
                : "󰉋" // md-folder
                verticalInkCenter: true
                color: row.mounted ? panel.theme.textPrimary : panel.theme.textMuted
                pixelSize: panel.theme.fontPx(1.083)
            }

            Column {
                id: rowLabels

                anchors.left: rowMark.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: unmountChip.visible ? unmountChip.left : parent.right
                anchors.rightMargin: unmountChip.visible ? panel.theme.space(2) : 0
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                StyledText {
                    theme: panel.theme

                    width: parent.width
                    text: Model.volumeLabel(row.volume)
                    elide: Text.ElideRight
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true

                    width: parent.width
                    // Who is holding it outranks where it is: that line only
                    // appears after an unmount has been refused, and it is
                    // the answer to the question that refusal raised.
                    text: {
                        if (row.holder !== "")
                            return "Held by " + row.holder;
                        if (!row.mounted)
                            return row.volume && row.volume.fstype ? "Not mounted · " + row.volume.fstype : "Not mounted";
                        return row.volume.mount + (row.volume.avail ? " · " + row.volume.avail + " free" : "");
                    }
                    color: row.holder !== "" ? panel.theme.warn : panel.theme.textMuted
                    elide: Text.ElideRight
                }
            }

            ChipSurface {
                id: unmountChip

                visible: row.mounted
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                theme: panel.theme
                implicitWidth: panel.theme.space(8)
                implicitHeight: panel.theme.space(7)
                pointerOver: unmountMouse.containsMouse

                OpticalGlyph {
                    anchors.centerIn: parent
                    text: "󰅖" // md-close
                    color: panel.theme.textPrimary
                    pixelSize: panel.theme.fontPx(1.0)
                }

                // A MouseArea rather than a TapHandler: the row underneath
                // has its own full-fill MouseArea, and a TapHandler's passive
                // grab would let the press fall through — one click would
                // unmount AND open.
                MouseArea {
                    id: unmountMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        panel.drives.unmountVolume(row.volume);
                        // Ask who is holding it, so that if the unmount is
                        // refused the row can say why rather than leaving
                        // the user with udisks' "target is busy".
                        panel.drives.lookupHolders(row.volume);
                    }
                }

                PanelHint {
                    theme: panel.theme
                    visible: unmountMouse.containsMouse
                    anchor: unmountChip
                    above: true
                    text: "Unmount"
                }
            }
        }
    }
}
