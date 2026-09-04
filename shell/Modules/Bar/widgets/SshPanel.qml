import QtQuick
import "../components"
import "../../../components"
import "SshModel.js" as Model

// SSH panel — type a few letters, press Enter, get a terminal on that host.
//
// The search field owns the keyboard from the moment the panel opens, which
// is the difference between this panel and the rows-only ones (devservices,
// drives): there is nothing to do here BUT filter, so making the user
// press a key to start typing would be a step for nothing. A focused
// TextInput swallows every printable key, so the list is driven through the
// field's moveRequested/accepted signals rather than j/k — PanelTextField
// documents that constraint.
//
// Escape clears a query before it closes the panel: having typed three
// letters into the wrong host, the thing you want back is the full list, not
// the desktop.
//
// Rows are capped at MAX_ROWS. The card clips at a maximum height, so a
// longer list would simply be invisible below the fold with nothing to say so
// — the count line at the bottom says how many are hiding instead, and the
// answer to it is to keep typing.
BarPanel {
    id: panel

    required property var ssh

    panelTitle: ""
    cardWidth: theme.space(92)

    readonly property int maxRows: 8

    property string query: ""
    readonly property var rows: ssh.ranked(query)
    readonly property int forgesHidden: query === "" ? Model.forgeCount(ssh.hosts) : 0
    readonly property var visibleRows: rows.slice(0, maxRows)
    readonly property int hiddenCount: Math.max(0, rows.length - maxRows)

    // -------------------------------------------------------------- cursor
    // Unlike the rows-only panels there is no "reveal the cursor first"
    // step: a filter surface always has a selection, because Enter has to
    // mean something the moment you have typed.
    property int rowIndex: 0

    function moveCursor(dy) {
        if (visibleRows.length === 0)
            return;
        rowIndex = Math.max(0, Math.min(visibleRows.length - 1, rowIndex + dy));
    }

    function selectedHost() {
        if (visibleRows.length === 0)
            return null;
        return visibleRows[Math.max(0, Math.min(rowIndex, visibleRows.length - 1))];
    }

    function connectSelected() {
        const host = selectedHost();
        if (!host)
            return;
        panel.ssh.connect(host);
        panel.close();
    }

    // Any edit invalidates the old position: the row under the cursor is
    // usually not even in the new list.
    onQueryChanged: rowIndex = 0

    // ------------------------------------------------------------ lifecycle
    onPanelOpened: {
        panel.query = "";
        panel.rowIndex = 0;
        panel.ssh.refresh();
        searchField.text = "";
        searchField.focusWhen = true;
    }

    onPanelClosed: searchField.focusWhen = false

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "SSH"
        meta: Model.heroMeta(panel.ssh.hosts, panel.rows.length, panel.query)
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            text: "󰣀"
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.theme.textPrimary
        }
    }

    PanelTextField {
        id: searchField

        theme: panel.theme
        width: parent.width
        inputFont: panel.theme.fontUi
        placeholder: "Search hosts"

        onTextEdited: text => panel.query = text
        onAccepted: panel.connectSelected()
        onMoveRequested: delta => panel.moveCursor(delta)
        onCancelled: {
            // A query first, the panel second.
            if (panel.query !== "") {
                text = "";
                panel.query = "";
            } else {
                panel.close();
            }
        }
    }

    // ---------------------------------------------------------------- error
    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.ssh.lastError !== ""
        width: parent.width
        text: panel.ssh.lastError
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

            HostRow {
                required property var modelData
                required property int index

                width: rowColumn.width
                host: modelData
                rowIndex: index
            }
        }
    }

    // Nothing matched. Worded as a dead end for the QUERY rather than for the
    // machine — the hosts are still there, this text just did not find them.
    StyledText {
        theme: panel.theme
        role: StyledText.Small
        muted: true

        visible: panel.visibleRows.length === 0
        width: parent.width
        text: panel.ssh.hostCount === 0 ? "No hosts in ~/.ssh/config." : "No host matches “" + panel.query + "”."
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
            // Only say it when there is something being withheld, and say how
            // to get at it rather than merely that it exists.
            if (panel.query === "" && panel.forgesHidden > 0)
                return "Enter opens a terminal. Git remotes are hidden — search one by name to reach it.";
            return "Enter opens a terminal on the selected host.";
        }
        wrapMode: Text.WordWrap
    }

    // ----------------------------------------------------------- components
    component HostRow: CursorSurface {
        id: row

        theme: panel.theme

        property var host: null
        property int rowIndex: 0

        readonly property bool rowSelected: panel.rowIndex === rowIndex

        hasCursor: rowSelected
        // The selection IS the cursor on a filter surface, so the fill says
        // it and the outline would be saying it twice — the pickers
        // (launcher, clipboard, menu) drop the border for the same reason.
        bordered: false
        current: rowSelected
        implicitHeight: rowContent.implicitHeight + panel.theme.space(2.5)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse)
                panel.rowIndex = row.rowIndex
            onClicked: {
                panel.rowIndex = row.rowIndex;
                panel.connectSelected();
            }
        }

        Item {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: rowLabels.implicitHeight

            Column {
                id: rowLabels

                anchors.left: parent.left
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                StyledText {
                    theme: panel.theme

                    width: parent.width
                    text: row.host ? row.host.alias : ""
                    elide: Text.ElideRight
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true

                    visible: text !== ""
                    width: parent.width
                    text: {
                        const note = Model.noteText(row.host);
                        const sub = Model.subtitle(row.host);
                        return note ? (sub ? sub + " · " + note : note) : sub;
                    }
                    color: Model.isForge(row.host) ? panel.theme.warn : panel.theme.textMuted
                    elide: Text.ElideRight
                }
            }
        }
    }
}
