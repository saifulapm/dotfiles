import QtQuick
import "../components"
import "../../../components"
import "PortsModel.js" as Model

// Ports panel — what is listening, what started it, and one key to open it.
//
// The search field owns the keyboard from the moment the panel opens, the way
// the ssh panel's does: there is nothing to do here but filter, so making the
// user press a key to begin would be a step for nothing.
//
// Rows are ordered ours-first rather than by port number, which is the
// opinion this panel has — a numeric sort buries the `pnpm dev` you came to
// find under sshd, dnsmasq and the mail proxies.
//
// Actions, in the order they matter: Enter opens the URL, Alt+C copies it,
// Alt+Q shows a QR for a phone on the same network, Alt+D opens the project
// directory, and Alt+X stops the process. Only the last of those is
// destructive and it is the only one that is never offered for something this
// user does not own — bin/ports refuses it anyway, and an action that will be
// refused should not be on screen.
//
// THEY ARE CHORDS AND NOT BARE LETTERS, which they were until 2026-08-21.
// The search field holds focus for the life of the panel, so `c` typed a "c"
// into the query and the shortcut in the footer was a lie — the same bug the
// pass panel's Alt chords had, from the other direction. A panel with an
// always-focused text field cannot have single-letter shortcuts at all.
BarPanel {
    id: panel

    required property var ports

    panelTitle: ""
    cardWidth: theme.space(105)

    readonly property int maxRows: 9

    property string query: ""
    readonly property var rows: ports.ranked(query)
    readonly property var visibleRows: rows.slice(0, maxRows)
    readonly property int hiddenCount: Math.max(0, rows.length - maxRows)

    property int rowIndex: 0

    function moveCursor(dy) {
        if (visibleRows.length === 0)
            return;
        rowIndex = Math.max(0, Math.min(visibleRows.length - 1, rowIndex + dy));
    }

    function selected() {
        if (visibleRows.length === 0)
            return null;
        return visibleRows[Math.max(0, Math.min(rowIndex, visibleRows.length - 1))];
    }

    onQueryChanged: rowIndex = 0

    // One entry point for both the hero switch and Alt+S: flipping the
    // filter republishes the list, so the cursor goes home like a query
    // change sends it.
    function toggleSystem() {
        panel.ports.showSystem = !panel.ports.showSystem;
        panel.rowIndex = 0;
    }

    // Claimed ahead of the search field — PanelTextField.chord explains why a
    // TextInput has to be asked first rather than fallen through.
    function handleChord(event) {
        if ((event.modifiers & Qt.AltModifier) === 0)
            return;
        const row = panel.selected();
        switch (event.key) {
        case Qt.Key_C:
            if (row)
                panel.ports.copyUrl(row);
            break;
        case Qt.Key_Q:
            if (row)
                panel.ports.requestQr(row);
            break;
        case Qt.Key_D:
            if (row)
                panel.ports.openDirectory(row);
            break;
        case Qt.Key_X:
            if (row)
                panel.ports.stop(row);
            break;
        case Qt.Key_R:
            panel.ports.refresh();
            break;
        case Qt.Key_S:
            panel.toggleSystem();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    onContentKey: event => panel.handleChord(event)

    // ------------------------------------------------------------ lifecycle
    onPanelOpened: {
        panel.query = "";
        panel.rowIndex = 0;
        panel.ports.panelOpen = true;
        panel.ports.clearQr();
        panel.ports.refresh();
        searchField.text = "";
        searchField.focusWhen = true;
    }

    // Stopping the 2 s refresher is the whole reason this handler exists.
    onPanelClosed: {
        panel.ports.panelOpen = false;
        searchField.focusWhen = false;
    }
    Component.onDestruction: panel.ports.panelOpen = false

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Ports"
        meta: Model.heroMeta(panel.ports.rows, panel.rows.length, panel.query, panel.ports.showSystem)
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            text: "󰌘" // md-lan
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.ports.exposedCount > 0 ? panel.theme.warn : panel.theme.textPrimary
        }

        // The system-ports toggle (Alt+S). Off by default: declared services
        // join the list only on request, and never wake the bar icon.
        trailing: PanelSwitch {
            theme: panel.theme
            anchors.verticalCenter: parent.verticalCenter
            checked: panel.ports.showSystem
            hint: "System ports (Alt+S)"
            onToggled: panel.toggleSystem()
        }
    }

    PanelTextField {
        id: searchField

        theme: panel.theme
        width: parent.width
        inputFont: panel.theme.fontUi
        placeholder: "Search port, process or project"

        onTextEdited: text => panel.query = text
        onChord: event => panel.handleChord(event)
        onAccepted: {
            const row = panel.selected();
            if (row)
                panel.ports.openUrl(row);
        }
        onMoveRequested: delta => panel.moveCursor(delta)
        onCancelled: {
            if (panel.ports.qrPort !== 0) {
                panel.ports.clearQr();
            } else if (panel.query !== "") {
                text = "";
                panel.query = "";
            } else {
                panel.close();
            }
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.ports.lastError !== ""
        width: parent.width
        text: panel.ports.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------------- rows
    Column {
        id: rowColumn

        width: parent.width
        spacing: panel.theme.space(0.5)
        visible: panel.visibleRows.length > 0

        Repeater {
            model: panel.visibleRows

            PortRow {
                required property var modelData
                required property int index

                width: rowColumn.width
                entry: modelData
                rowIndex: index
            }
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small
        muted: true

        visible: panel.visibleRows.length === 0
        width: parent.width
        text: {
            if (panel.ports.listenerCount === 0)
                return "Nothing is listening.";
            if (panel.query !== "")
                return "Nothing matches “" + panel.query + "”.";
            // The common case, and it is good news rather than an error: the
            // machine's own services are running and you have started nothing.
            return "Nothing running that you started. The machine's own services are hidden — search one by name.";
        }
        wrapMode: Text.WordWrap
    }

    // --------------------------------------------------------------- footer
    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        width: parent.width
        text: {
            if (panel.hiddenCount > 0)
                return panel.hiddenCount + " more — keep typing to narrow";
            return "Enter opens · Alt+C copies · Alt+Q a QR · Alt+D the folder · Alt+X stops it · Alt+S system";
        }
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    component PortRow: CursorSurface {
        id: portRow

        theme: panel.theme

        property var entry: null
        property int rowIndex: 0

        readonly property bool rowSelected: panel.rowIndex === rowIndex
        readonly property bool showingQr: !!entry && panel.ports.qrPort === entry.port && panel.ports.qrRows.length > 0
        readonly property bool exposed: Model.isExposed(entry)

        hasCursor: rowSelected
        bordered: false
        current: rowSelected
        implicitHeight: rowBody.implicitHeight + panel.theme.space(2.5)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse)
                panel.rowIndex = portRow.rowIndex
            onClicked: {
                panel.rowIndex = portRow.rowIndex;
                panel.ports.openUrl(portRow.entry);
            }
        }

        Column {
            id: rowBody

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            spacing: panel.theme.space(1)

            Item {
                width: parent.width
                implicitHeight: Math.max(portText.implicitHeight, labels.implicitHeight, actions.implicitHeight)

                // The port number is the identifier people actually use, so
                // it leads, in mono, at a fixed width the rows line up on.
                StyledText {
                    id: portText

                    theme: panel.theme
                    mono: true

                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    width: panel.theme.space(11)
                    text: portRow.entry ? String(portRow.entry.port) : ""
                    color: portRow.exposed ? panel.theme.warn : panel.theme.textPrimary
                    font.weight: Font.DemiBold
                }

                Column {
                    id: labels

                    anchors.left: portText.right
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.right: actions.left
                    anchors.rightMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(0.25)

                    StyledText {
                        theme: panel.theme

                        width: parent.width
                        text: portRow.entry ? portRow.entry.label : ""
                        elide: Text.ElideRight
                    }

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Caption
                        mono: true

                        width: parent.width
                        text: {
                            if (!portRow.entry)
                                return "";
                            const unit = Model.unitText(portRow.entry);
                            const detail = unit || Model.detailText(portRow.entry, panel.ports.home);
                            const scope = Model.scopeLabel(portRow.entry);
                            return detail ? detail + " · " + scope : scope;
                        }
                        color: portRow.exposed ? panel.theme.warn : panel.theme.textMuted
                        elide: Text.ElideRight
                    }
                }

                Row {
                    id: actions

                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(1)

                    RowChip {
                        visible: Model.urlFor(portRow.entry) !== ""
                        glyph: "󰐲" // md-qrcode
                        hint: "Show a QR for a phone"
                        onActivated: panel.ports.requestQr(portRow.entry)
                    }

                    RowChip {
                        visible: !!portRow.entry && portRow.entry.cwd !== ""
                        glyph: "󰉋" // md-folder
                        hint: "Open the project folder"
                        onActivated: panel.ports.openDirectory(portRow.entry)
                    }

                    // Never drawn for something this user does not own:
                    // bin/ports would refuse it, and an action that will be
                    // refused does not belong on screen.
                    RowChip {
                        visible: Model.isKillable(portRow.entry)
                        glyph: "󰙦" // md-stop_circle
                        hint: "Stop this process"
                        urgent: true
                        onActivated: panel.ports.stop(portRow.entry)
                    }
                }
            }

            // The QR, painted with native rectangles from bin/network-qr's
            // 0/1 matrix — no temporary image, nothing cached.
            Item {
                width: parent.width
                visible: portRow.showingQr
                implicitHeight: portRow.showingQr ? qrBlock.height + panel.theme.space(3) : 0

                Rectangle {
                    id: qrBlock

                    anchors.horizontalCenter: parent.horizontalCenter
                    anchors.top: parent.top
                    anchors.topMargin: panel.theme.space(1.5)
                    width: modules * moduleSize
                    height: width
                    // A scanner needs light modules to be light whatever the
                    // desktop theme is doing, so this block is fixed white
                    // and the dark modules are fixed black.
                    color: "white"
                    radius: panel.theme.radius(0.25)

                    readonly property int modules: panel.ports.qrRows.length
                    readonly property int moduleSize: modules > 0 ? Math.max(2, Math.floor(panel.theme.space(42) / modules)) : 2

                    Column {
                        anchors.centerIn: parent
                        spacing: 0

                        Repeater {
                            model: panel.ports.qrRows

                            Row {
                                id: qrLine

                                required property string modelData
                                // Named, so the per-module delegate below
                                // reads the row it belongs to by id rather
                                // than walking parent.parent — which is one
                                // refactor away from silently addressing the
                                // wrong item.
                                readonly property string bits: modelData
                                spacing: 0

                                Repeater {
                                    model: qrLine.bits.length

                                    Rectangle {
                                        required property int index
                                        width: qrBlock.moduleSize
                                        height: qrBlock.moduleSize
                                        color: qrLine.bits.charAt(index) === "1" ? "black" : "white"
                                    }
                                }
                            }
                        }
                    }
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true

                    anchors.top: qrBlock.bottom
                    anchors.topMargin: panel.theme.space(1)
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: panel.ports.qrUrl
                    color: panel.theme.textMuted
                }
            }
        }
    }

    // A bordered square holding one glyph — the devservices web button's
    // shape, with a MouseArea rather than a TapHandler for the reason that
    // one documents: a TapHandler's passive grab lets the press fall through
    // to the row underneath.
    component RowChip: ChipSurface {
        id: chip

        property string glyph: ""
        property string hint: ""
        property bool urgent: false

        signal activated

        theme: panel.theme
        implicitWidth: panel.theme.space(7)
        implicitHeight: panel.theme.space(6.5)
        pointerOver: chipMouse.containsMouse

        OpticalGlyph {
            anchors.centerIn: parent
            text: chip.glyph
            color: chip.urgent ? panel.theme.error : panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(0.917)
        }

        MouseArea {
            id: chipMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: chip.activated()
        }

        PanelHint {
            theme: panel.theme
            visible: chipMouse.containsMouse
            anchor: chip
            above: true
            text: chip.hint
        }
    }
}
