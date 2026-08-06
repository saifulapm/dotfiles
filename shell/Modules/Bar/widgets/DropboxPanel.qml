import QtQuick
import "../components"
import "DropboxModel.js" as Model

// Dropbox panel — full port of omarchy's dropbox plugin Panel.qml in our
// tokens: a hero of the Dropbox mark over a rotating sync phrase with the
// on/off switch on its trailing edge, the action/error line, the login row
// while no account is attached, the stored total, and the RECENT FILES list.
//
// Their single cursor model comes with it: the mouse and the keyboard move the
// same highlight, j/k (and the arrows) walk header → files, Enter activates
// whatever is under it, and their letter keys are r (refresh), l (login) and
// p (pause/resume). The first arrow press only reveals the cursor.
//
// Ours on top of theirs: the "Stored" row opens the Dropbox folder with
// xdg-open (o does the same from the keyboard) — upstream has no way to reach
// the folder at all — and the relative times re-tick every 30 s while the card
// sits open, as the model-usage panel's countdowns do.
BarPanel {
    id: panel

    required property var dropbox

    panelTitle: ""
    cardWidth: theme.space(95)

    // Read instead of Date.now() so "3m ago" stays true while the card is open.
    property double nowMs: Date.now()

    // ------------------------------------------------------------- phrases
    property int phraseIndex: 0
    readonly property var activePhrases: ["Filing files", "Distributing data", "Shuffling folders", "Boxing bytes", "Sorting stuff", "Syncing secrets", "Packing packets", "Moving memories", "Wrangling revisions", "Cataloging chaos"]
    readonly property string heroPhraseText: activePhrases[phraseIndex % activePhrases.length]

    readonly property string toggleHint: dropbox.active ? "Pause syncing" : "Resume syncing"

    // -------------------------------------------------------------- cursor
    // Sections: "login" (the whole card is one action while logged out),
    // "header" (the on/off switch) and "files" (the recent list).
    property string focusSection: "login"
    property int fileIndex: 0
    property bool cursorActive: false

    readonly property var files: dropbox.files || []
    // "header" stays navigable, but an absent CLI leaves nothing to highlight.
    readonly property bool headerHasCursor: cursorActive && focusSection === "header" && dropbox.installed

    function ensureCursor() {
        if (!panel.dropbox.authenticated) {
            panel.focusSection = "login";
            panel.fileIndex = 0;
            return;
        }
        if (panel.files.length === 0) {
            panel.focusSection = "header";
            panel.fileIndex = 0;
            return;
        }
        if (panel.focusSection !== "files" && panel.focusSection !== "header")
            panel.focusSection = "files";
        if (panel.fileIndex >= panel.files.length)
            panel.fileIndex = Math.max(0, panel.files.length - 1);
        if (panel.fileIndex < 0)
            panel.fileIndex = 0;
    }

    function moveCursor(dy) {
        panel.cursorActive = true;
        panel.ensureCursor();
        if (dy === 0)
            return;
        if (panel.focusSection === "header") {
            if (dy > 0 && panel.files.length > 0) {
                panel.focusSection = "files";
                panel.fileIndex = 0;
            }
            return;
        }
        if (panel.focusSection === "files") {
            if (dy < 0 && panel.fileIndex === 0) {
                panel.setHeaderCursor();
                return;
            }
            panel.fileIndex = Math.max(0, Math.min(panel.files.length - 1, panel.fileIndex + dy));
        }
    }

    function setHeaderCursor() {
        panel.cursorActive = true;
        panel.focusSection = "header";
        scroller.contentY = 0;
    }

    function setFileCursor(index) {
        panel.cursorActive = true;
        panel.focusSection = "files";
        panel.fileIndex = index;
    }

    function selectedFile() {
        if (panel.files.length === 0)
            return null;
        return panel.files[Math.max(0, Math.min(panel.fileIndex, panel.files.length - 1))];
    }

    function toggleRunning() {
        if (panel.dropbox.installed && !panel.dropbox.busy)
            panel.dropbox.toggleRunning();
    }

    function activateCursor() {
        if (!panel.cursorActive) {
            panel.cursorActive = true;
            return;
        }
        panel.ensureCursor();
        if (panel.focusSection === "login")
            panel.dropbox.login();
        else if (panel.focusSection === "header")
            panel.toggleRunning();
        else if (panel.focusSection === "files")
            panel.dropbox.openFile(panel.selectedFile());
    }

    // Keep the keyboard-focused row inside the viewport (NetworkPanel's).
    function ensureCursorVisible(item) {
        if (!item || !scroller.interactive)
            return;
        const margin = panel.theme.space(2);
        const maxY = Math.max(0, scroller.contentHeight - scroller.height);
        const top = item.mapToItem(sections, 0, 0).y;
        const bottom = top + item.height;
        if (top < scroller.contentY + margin)
            scroller.contentY = Math.max(0, Math.min(maxY, top - margin));
        else if (bottom > scroller.contentY + scroller.height - margin)
            scroller.contentY = Math.max(0, Math.min(maxY, bottom + margin - scroller.height));
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            if (panel.cursorActive)
                panel.moveCursor(1);
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            if (panel.cursorActive)
                panel.moveCursor(-1);
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            panel.activateCursor();
            break;
        case Qt.Key_R:
            panel.dropbox.refreshDetails();
            break;
        case Qt.Key_L:
            panel.dropbox.login();
            break;
        case Qt.Key_P:
            panel.toggleRunning();
            break;
        case Qt.Key_O:
            panel.dropbox.openFolder();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------ lifecycle
    onPanelOpened: {
        panel.nowMs = Date.now();
        panel.cursorActive = false;
        scroller.contentY = 0;
        panel.dropbox.refreshDetails();
        panel.ensureCursor();
    }

    onFilesChanged: panel.ensureCursor()

    Connections {
        target: panel.dropbox
        function onAuthenticatedChanged() {
            panel.ensureCursor();
        }
    }

    Timer {
        interval: 30000
        running: panel.opened
        repeat: true
        onTriggered: panel.nowMs = Date.now()
    }

    PhraseRotator {
        theme: panel.theme
        target: heroMeta
        running: panel.opened && panel.dropbox.authenticated && panel.dropbox.active
        onAdvance: panel.phraseIndex = (panel.phraseIndex + 1) % panel.activePhrases.length
    }

    // -------------------------------------------------------------- content
    Flickable {
        id: scroller

        width: parent.width
        // Capped like their popup: a big Dropbox scrolls inside the card
        // instead of stretching it down the whole screen.
        height: Math.min(sections.implicitHeight, panel.theme.space(140), panel.height - panel.theme.barHeight - panel.theme.space(14))
        contentWidth: width
        contentHeight: sections.implicitHeight
        interactive: contentHeight > height
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        Column {
            id: sections

            width: scroller.width
            spacing: panel.theme.space(3)

            // ---------------------------------------------------------- hero
            Item {
                id: hero

                visible: panel.dropbox.authenticated
                width: parent.width
                implicitHeight: visible ? Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, powerSwitch.implicitHeight) : 0

                DropboxIcon {
                    id: heroIcon
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    iconSize: panel.theme.fontPx(1.6)
                    color: panel.dropbox.authenticated && panel.dropbox.active ? panel.theme.textPrimary : panel.theme.textMuted
                    opacity: panel.dropbox.active ? 1.0 : 0.5
                }

                // Their compact on/off switch on the trailing edge of the hero,
                // and the header's only cursor target. The service flips
                // `active` optimistically, so the knob throws on the click.
                PanelSwitch {
                    id: powerSwitch
                    theme: panel.theme
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    visible: panel.dropbox.installed
                    checked: panel.dropbox.active
                    busy: panel.dropbox.busy
                    hasCursor: panel.headerHasCursor
                    hint: panel.toggleHint
                    onHovered: panel.setHeaderCursor()
                    onToggled: panel.toggleRunning()
                }

                Column {
                    id: heroLabels

                    anchors.left: heroIcon.right
                    anchors.leftMargin: panel.theme.space(3)
                    anchors.right: powerSwitch.visible ? powerSwitch.left : parent.right
                    anchors.rightMargin: panel.theme.space(3)
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: panel.theme.space(0.5)

                    Text {
                        width: parent.width
                        text: "Dropbox"
                        color: panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(1.083)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        id: heroMeta
                        width: parent.width
                        text: panel.dropbox.active ? panel.heroPhraseText : "Syncing paused"
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.833)
                        elide: Text.ElideRight
                    }
                }
            }

            // The daemon's own sentence. Upstream keeps it in the bar tooltip
            // only; a panel that can start and stop syncing should say what
            // the thing it just started is doing.
            Text {
                visible: panel.dropbox.authenticated && text !== ""
                width: parent.width
                text: panel.dropbox.elideStatus(panel.dropbox.statusText)
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.833)
                wrapMode: Text.WordWrap
            }

            // -------------------------------------------------- action/error
            Text {
                visible: panel.dropbox.actionStatus !== "" || panel.dropbox.lastError !== ""
                width: parent.width
                text: panel.dropbox.actionStatus !== "" ? panel.dropbox.actionStatus : panel.dropbox.lastError
                color: panel.dropbox.lastError !== "" && panel.dropbox.actionStatus === "" ? panel.theme.error : panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.833)
                wrapMode: Text.WordWrap
            }

            // --------------------------------------------------------- login
            CursorSurface {
                id: loginButton
                theme: panel.theme

                visible: !panel.dropbox.authenticated
                width: parent.width
                implicitHeight: visible ? loginRow.implicitHeight + panel.theme.space(4) : 0
                hasCursor: panel.cursorActive && panel.focusSection === "login"

                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    enabled: panel.dropbox.installed && !panel.dropbox.busy
                    cursorShape: enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
                    onEntered: {
                        panel.cursorActive = true;
                        panel.focusSection = "login";
                    }
                    onClicked: panel.dropbox.login()
                }

                Item {
                    id: loginRow

                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.leftMargin: panel.theme.space(2.5)
                    anchors.rightMargin: panel.theme.space(2.5)
                    implicitHeight: Math.max(loginMark.implicitHeight, loginLabels.implicitHeight, loginAction.implicitHeight)

                    // Their login row leads with the Dropbox brand glyph from
                    // the Devicons range, which does not render under our
                    // Symbols Nerd Font fallback — the drawn mark stands in.
                    DropboxIcon {
                        id: loginMark
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        iconSize: panel.theme.fontPx(1.15)
                        color: panel.theme.textPrimary
                    }

                    Column {
                        id: loginLabels

                        anchors.left: loginMark.right
                        anchors.leftMargin: panel.theme.space(2)
                        anchors.right: loginAction.left
                        anchors.rightMargin: panel.theme.space(2)
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: panel.theme.space(0.25)

                        Text {
                            width: parent.width
                            text: panel.dropbox.installed ? "Login to Dropbox" : "Dropbox CLI is not installed"
                            color: panel.theme.textPrimary
                            font.family: panel.theme.fontUi
                            font.pixelSize: panel.theme.fontPx(0.917)
                            elide: Text.ElideRight
                        }

                        Text {
                            width: parent.width
                            text: panel.dropbox.installed ? "Start the authentication flow" : "Install nautilus-dropbox first"
                            color: panel.theme.textMuted
                            font.family: panel.theme.fontUi
                            font.pixelSize: panel.theme.fontPx(0.75)
                            elide: Text.ElideRight
                        }
                    }

                    // Their PanelActionButton and its key glyph (already a
                    // Material Design codepoint, so it renders as-is).
                    GlyphButton {
                        id: loginAction
                        theme: panel.theme
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        glyph: "󰌋"
                        enabled: panel.dropbox.installed && !panel.dropbox.busy
                        onActivated: panel.dropbox.login()
                    }
                }
            }

            // -------------------------------------------------------- stored
            // Their InfoPair, with the folder behind it: clicking the row (or
            // pressing o) opens the Dropbox folder in the file manager.
            Item {
                id: storedRow

                visible: panel.dropbox.authenticated
                width: parent.width
                implicitHeight: visible ? Math.max(storedLabel.implicitHeight, storedValue.implicitHeight) : 0

                HoverHandler {
                    id: storedHover
                    enabled: panel.dropbox.accountPath !== ""
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    enabled: panel.dropbox.accountPath !== ""
                    onTapped: panel.dropbox.openFolder()
                }

                PanelHint {
                    theme: panel.theme
                    visible: storedHover.hovered
                    anchor: storedRow
                    text: "Open " + (panel.dropbox.accountPath || "the Dropbox folder")
                }

                Text {
                    id: storedLabel
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    text: "Stored"
                    color: panel.theme.textPrimary
                    opacity: 0.6
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.833)
                }

                Text {
                    id: storedValue
                    anchors.right: parent.right
                    anchors.left: storedLabel.right
                    anchors.leftMargin: panel.theme.space(2)
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: Text.AlignRight
                    elide: Text.ElideRight
                    text: panel.dropbox.detailsLoaded ? Model.usageText(panel.dropbox.usedBytes, panel.dropbox.quotaBytes, panel.dropbox.quotaKnown) : "Reading…"
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.833)
                }
            }

            Rectangle {
                visible: panel.dropbox.authenticated
                width: parent.width
                height: visible ? 1 : 0
                color: panel.theme.surface3
            }

            // -------------------------------------------------- recent files
            Column {
                visible: panel.dropbox.authenticated
                width: parent.width
                spacing: panel.theme.space(1.5)

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    label: "RECENT FILES"
                }

                Text {
                    visible: panel.files.length === 0
                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: panel.dropbox.detailsLoaded ? "No synced files found." : "Reading the Dropbox folder…"
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                }

                Column {
                    id: fileColumn

                    visible: panel.files.length > 0
                    width: parent.width
                    spacing: panel.theme.space(0.5)

                    Repeater {
                        model: panel.files

                        FileRow {
                            required property var modelData
                            required property int index

                            width: fileColumn.width
                            file: modelData
                            rowIndex: index
                        }
                    }
                }
            }
        }
    }

    // ----------------------------------------------------------- components
    component FileRow: CursorSurface {
        id: fileRow

        theme: panel.theme

        property var file: null
        property int rowIndex: 0
        readonly property string fileName: file ? String(file.name || "Untitled") : "Untitled"

        implicitHeight: fileContent.implicitHeight + panel.theme.space(2.5)
        hasCursor: panel.cursorActive && panel.focusSection === "files" && panel.fileIndex === rowIndex

        // Scroll to the row the keyboard just landed on.
        onHasCursorChanged: if (hasCursor)
            panel.ensureCursorVisible(fileRow)

        MouseArea {
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onEntered: panel.setFileCursor(fileRow.rowIndex)
            onClicked: panel.dropbox.openFile(fileRow.file)
        }

        OpticalGlyph {
            id: fileGlyph
            anchors.left: parent.left
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.verticalCenter: parent.verticalCenter
            text: Model.fileGlyph(fileRow.fileName)
            color: panel.theme.textPrimary
            pixelSize: panel.theme.fontPx(1.083)
        }

        Column {
            id: fileContent

            anchors.left: fileGlyph.right
            anchors.leftMargin: panel.theme.space(2)
            anchors.right: parent.right
            anchors.rightMargin: panel.theme.space(2.5)
            anchors.verticalCenter: parent.verticalCenter
            spacing: panel.theme.space(0.25)

            Text {
                width: parent.width
                text: fileRow.fileName
                color: panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
                elide: Text.ElideRight
            }

            Text {
                width: parent.width
                text: Model.fileMeta(fileRow.file, panel.nowMs)
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.75)
                elide: Text.ElideRight
            }
        }
    }
}
