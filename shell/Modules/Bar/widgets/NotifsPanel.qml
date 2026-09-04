import QtQuick
import Quickshell
import "../components"
import "../../../components"
import "../../Notifications/NotificationLogic.js" as Logic

// Notification history center — the review surface over Services/Notifs.qml's
// two history buckets: pending (received but not yet seen) and past (already
// seen). Omarchy's service comments describe this panel ("the Past tab in the
// history panel") but their repo ships no implementation, so the surface
// itself is ours, built on the same BarPanel scaffold and cursor model as the
// Bluetooth panel.
//
// The list is CHRONOLOGICAL, both buckets merged, grouped by the day each
// entry arrived on. It used to stack unseen above seen, which was right while
// the service only kept a seen entry for fifteen minutes; with thirty days of
// retention it stopped being right — a three-day-old unseen notification
// would sit above everything that arrived today. Unseen is a per-row dot now.
// (Day sections, the search box and per-sender muting are the shapes the
// marketplace's notification centers converged on: jankeesvw's, ritechoice23's
// and abran-labs'. The code is ours, against our own service.)
//
// Closing the panel marks every pending entry seen: the list was just on
// screen, so the bell's unseen badge resets.
BarPanel {
    id: panel

    required property var notifs

    // The bar's closeNotifCenter/notifCenterOpen use this to tell the center
    // apart from the widget panels sharing the activePanel slot.
    readonly property bool isNotifCenter: true

    cardWidth: theme.space(95)

    readonly property int unseenCount: notifs.pendingModel.count
    readonly property int totalCount: notifs.pendingModel.count + notifs.pastModel.count

    // ---------------------------------------------------------------- search
    property string query: ""
    readonly property bool filtering: query.trim().length > 0

    // ------------------------------------------------------------------ rows
    // Snapshots, so they stay valid across model edits; the merge, sort,
    // filter and day sectioning all happen in NotificationLogic, where node
    // can test them.
    readonly property var rows: {
        const pending = [];
        for (let i = 0; i < notifs.pendingModel.count; i++)
            pending.push(notifs.snapshotFromRow(notifs.pendingModel.get(i)));
        const past = [];
        for (let j = 0; j < notifs.pastModel.count; j++)
            past.push(notifs.snapshotFromRow(notifs.pastModel.get(j)));
        return Logic.centerRows(pending, past, query, dayNow);
    }

    // How tall the list may grow: whatever is left of the screen once the
    // card's fixed rows have taken theirs.
    //
    // Not a constant like the Bluetooth panel's space(100): thirty days of
    // history is a genuinely long list, and a fixed cap left a third of the
    // screen empty below a panel that was already scrolling. Not unbounded
    // either — BarPanel clamps the CARD to the screen, so a column that asks
    // for more than fits is not shrunk, it is clipped, and the muted list
    // would silently vanish off the bottom edge. This keeps the column inside
    // the clamp so the clamp never has to act.
    readonly property real listCap: {
        const chrome = heroRow.implicitHeight + (searchField.visible ? searchField.implicitHeight : 0) + mutedColumn.height + theme.space(28);
        return Math.max(theme.space(40), height - barExtent - chrome);
    }

    // -------------------------------------------------------------- cursor
    // -1 sits on the hero's DND switch, 0.. on the rows.
    property bool cursorActive: false
    property int cursorIndex: 0

    onRowsChanged: {
        if (cursorIndex >= rows.length)
            cursorIndex = rows.length - 1;
        if (cursorIndex < -1)
            cursorIndex = -1;
    }

    function setRowCursor(index) {
        cursorActive = true;
        cursorIndex = index;
    }

    function moveCursor(delta) {
        cursorActive = true;
        cursorIndex = Math.max(-1, Math.min(cursorIndex + delta, rows.length - 1));
    }

    function activateCursor() {
        if (cursorIndex === -1) {
            notifs.toggleDnd();
            return;
        }
        const row = rows[cursorIndex];
        if (!row)
            return;
        const invoked = notifs.invokeEntryDefault(row.entry);
        notifs.markEntrySeen(row.entry);
        if (invoked)
            panel.close();
    }

    function dismissCursor() {
        if (cursorIndex < 0)
            return;
        dismissRow(rows[cursorIndex]);
    }

    function dismissRow(row) {
        if (row)
            notifs.dismissEntry(row.entry);
    }

    // Mute the sender of the row under the cursor. The rule is taken from the
    // notification's own app name rather than typed, which is what keeps a
    // substring rule as specific as the sender that created it.
    function muteRow(row) {
        if (row && row.entry && row.entry.app)
            notifs.muteApp(row.entry.app);
    }

    function clearSection(row) {
        if (!row)
            return;
        const bounds = Logic.dayBounds(row.entry.timestamp);
        notifs.clearRange(bounds.from, bounds.to);
    }

    // The live Notification's action list for a row, or [] once the sender's
    // object is gone — history rows outlive the bus object by design.
    function actionsFor(entry) {
        try {
            const ref = entry && entry.originalId >= 0 ? notifs.liveRefs[entry.originalId] : null;
            if (ref && ref.actions && ref.actions.length > 0)
                return ref.actions;
        } catch (e) {
            // The server tore the notification down under the wrapper.
        }
        return [];
    }

    function invokeAction(row, action) {
        try {
            action.invoke();
        } catch (e) {
            console.warn("NotifsPanel: action invoke failed:", e);
            return;
        }
        notifs.markEntrySeen(row.entry);
        panel.close();
    }

    // ----------------------------------------------------------- timestamps
    // Ticks only while the panel is open — relative labels stay honest
    // without any background polling.
    property double nowMs: Date.now()
    // Sectioning reads THIS instead of nowMs, and it only moves when the
    // local day does. Binding the row list to a 30-second clock would rebuild
    // the whole model twice a minute and throw the scroll position away with
    // it, to redraw headers that change once a day.
    property double dayNow: Date.now()

    Timer {
        running: panel.opened
        interval: 30000
        repeat: true
        onTriggered: {
            panel.nowMs = Date.now();
            if (Logic.startOfDay(panel.dayNow) !== Logic.startOfDay(panel.nowMs))
                panel.dayNow = panel.nowMs;
        }
    }

    function relativeTime(timestamp) {
        const s = Math.max(0, Math.round((nowMs - timestamp) / 1000));
        if (s < 60)
            return "now";
        if (s < 3600)
            return Math.floor(s / 60) + "m";
        if (s < 86400)
            return Math.floor(s / 3600) + "h";
        return Math.floor(s / 86400) + "d";
    }

    // Icon resolution, as NotificationCard does it: ask the icon theme for
    // provider names so an unknown name yields nothing instead of Qt's
    // placeholder texture, and leave file/path sources alone.
    function resolveImage(value) {
        const v = String(value || "");
        const prefix = "image://icon/";
        if (v.indexOf(prefix) !== 0 || v.indexOf("?") >= 0)
            return v;
        return Quickshell.iconPath(decodeURIComponent(v.substring(prefix.length)), true);
    }

    function iconSourceFor(entry) {
        if (entry.image && String(entry.image).length > 0)
            return resolveImage(entry.image);
        const value = String(entry.appIcon || "");
        if (value.length === 0)
            return "";
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
            return value;
        if (value.charAt(0) === "/")
            return "file://" + encodeURI(value);
        return Quickshell.iconPath(value, true);
    }

    onPanelOpened: {
        nowMs = Date.now();
        dayNow = nowMs;
        query = "";
        cursorActive = false;
        cursorIndex = panel.rows.length > 0 ? 0 : -1;
    }

    // Reviewed: the unseen bucket was on screen, so it has been seen.
    onPanelClosed: {
        if (notifs.pendingModel.count > 0)
            notifs.markAllSeen();
    }

    // ------------------------------------------------------------ keyboard
    // Chords arrive here from two places — the card's key catcher when the
    // list has focus, and PanelTextField.chord when the search box does, which
    // is the only way a Ctrl chord can be caught ahead of a TextInput.
    function handleChord(event) {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_F) {
            searchField.takeFocus();
            searchField.selectAll();
            event.accepted = true;
        }
    }

    onContentKey: event => {
        if (event.modifiers & (Qt.AltModifier | Qt.ControlModifier)) {
            panel.handleChord(event);
            return;
        }
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
            if (panel.cursorActive)
                panel.activateCursor();
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Delete:
        case Qt.Key_X:
            if (panel.cursorActive)
                panel.dismissCursor();
            break;
        case Qt.Key_D:
            panel.notifs.toggleDnd();
            break;
        case Qt.Key_S:
            panel.notifs.toggleSound();
            break;
        case Qt.Key_M:
            if (panel.cursorActive && panel.cursorIndex >= 0)
                panel.muteRow(panel.rows[panel.cursorIndex]);
            break;
        case Qt.Key_Slash:
            searchField.takeFocus();
            searchField.selectAll();
            break;
        case Qt.Key_Escape:
            // Narrowest thing first: drop the filter, and only an Escape with
            // nothing left to undo falls through to BarPanel and closes.
            if (!panel.filtering)
                return;
            panel.query = "";
            searchField.text = "";
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------- content
    Column {
        width: parent.width
        spacing: panel.theme.space(3)

        // ------------------------------------------------------------ hero
        Item {
            id: heroRow

            width: parent.width
            implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight, dndSwitch.implicitHeight)

            OpticalGlyph {
                id: heroIcon
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: panel.notifs.dnd ? "󰂛" : "󰂚"
                color: panel.theme.textPrimary
                opacity: panel.notifs.dnd ? 0.5 : 1.0
                pixelSize: panel.theme.fontPx(1.6)
            }

            PanelSwitch {
                id: dndSwitch
                theme: panel.theme
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                checked: panel.notifs.dnd
                hasCursor: panel.cursorActive && panel.cursorIndex === -1
                hint: "Do not disturb"
                onHovered: {
                    panel.cursorActive = true;
                    panel.cursorIndex = -1;
                }
                onToggled: panel.notifs.toggleDnd()
            }

            // Sound sits beside DND rather than under it: it is the same kind
            // of decision (how loudly to be interrupted), and a toggle for a
            // feature that makes noise has to be reachable from the surface
            // the noise sends you to.
            GlyphButton {
                id: soundButton
                theme: panel.theme
                anchors.right: dndSwitch.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                glyph: panel.notifs.soundEnabled ? "󰕾" : "󰝟"
                hint: panel.notifs.soundEnabled ? "Sound on" : "Sound off"
                onActivated: panel.notifs.toggleSound()
            }

            Column {
                id: heroLabels
                anchors.left: heroIcon.right
                anchors.leftMargin: panel.theme.space(3)
                anchors.right: soundButton.left
                anchors.rightMargin: panel.theme.space(3)
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.5)

                StyledText {
                    theme: panel.theme
                    role: StyledText.Title

                    width: parent.width
                    text: "Notifications"
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true
                    muted: true

                    width: parent.width
                    text: {
                        const parts = [];
                        if (panel.notifs.dnd)
                            parts.push("SILENCED");
                        if (panel.filtering)
                            parts.push(panel.rows.length + " OF " + panel.totalCount);
                        else if (panel.unseenCount > 0)
                            parts.push(panel.unseenCount + " UNSEEN");
                        if (!panel.filtering && panel.totalCount > 0)
                            parts.push(panel.totalCount + " KEPT");
                        return parts.length > 0 ? parts.join(" · ") : "ALL CAUGHT UP";
                    }
                    font.letterSpacing: 1.2
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }

        // ---------------------------------------------------------- search
        // Shown whenever there is anything to search, rather than hidden
        // behind a toggle: the box IS the affordance, and a magnifier that
        // reveals a box is one more thing to discover for no less space.
        PanelTextField {
            id: searchField

            theme: panel.theme
            width: parent.width
            visible: panel.totalCount > 0
            inputFont: panel.theme.fontUi
            placeholder: "Search notifications"

            onTextEdited: text => panel.query = text
            onChord: event => panel.handleChord(event)
            // Arrows walk the list from inside the box, so a search can be
            // typed and then acted on without reaching for the mouse.
            onMoveRequested: delta => panel.moveCursor(delta)
            onAccepted: if (panel.cursorActive)
                panel.activateCursor()
            // Escape from inside the box drops the filter and hands the keys
            // back to the card; a second Escape then reaches BarPanel and
            // closes the panel, which is the order the rest of the shell uses.
            onCancelled: {
                if (panel.filtering) {
                    panel.query = "";
                    text = "";
                }
                panel.refocusKeys();
            }
        }

        Separator {
            theme: panel.theme
            visible: panel.rows.length > 0
        }

        // ------------------------------------------------------------ list
        Item {
            width: parent.width
            implicitHeight: rowListView.height

            ListView {
                id: rowListView

                width: parent.width
                height: Math.min(contentHeight, panel.listCap)
                spacing: panel.theme.space(1.5)
                clip: true
                boundsBehavior: Flickable.StopAtBounds
                interactive: contentHeight > height

                model: panel.rows
                currentIndex: panel.cursorActive ? panel.cursorIndex : -1
                onCurrentIndexChanged: if (currentIndex >= 0)
                    Qt.callLater(keepCurrentVisible)
                function keepCurrentVisible() {
                    if (currentIndex >= 0)
                        positionViewAtIndex(currentIndex, ListView.Contain);
                }

                delegate: Item {
                    required property var modelData
                    required property int index

                    width: ListView.view.width
                    height: delegateColumn.implicitHeight

                    Column {
                        id: delegateColumn
                        width: parent.width
                        spacing: panel.theme.space(1.5)

                        // Day header with that day's count and its own CLEAR —
                        // "clear today" is a thing to want; "clear everything I
                        // have ever been sent" mostly is not.
                        Item {
                            visible: modelData.section !== ""
                            width: parent.width
                            height: visible ? panel.theme.space(6) : 0

                            SectionHeader {
                                theme: panel.theme
                                anchors.left: parent.left
                                anchors.right: clearAction.left
                                anchors.rightMargin: panel.theme.space(2)
                                anchors.verticalCenter: parent.verticalCenter
                                label: modelData.section + " · " + modelData.sectionCount
                            }

                            StyledText {
                                id: clearAction
                                theme: panel.theme
                                role: StyledText.Caption
                                mono: true
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                text: "CLEAR"
                                color: clearMouse.containsMouse ? panel.theme.textPrimary : panel.theme.textMuted
                                font.letterSpacing: 1.2
                                font.weight: Font.DemiBold

                                MouseArea {
                                    id: clearMouse
                                    anchors.fill: parent
                                    anchors.margins: -panel.theme.space(1)
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: panel.clearSection(modelData)
                                }
                            }
                        }

                        NotifRow {
                            width: parent.width
                            row: modelData
                            flatIndex: index
                        }
                    }
                }
            }

            // "There is more this way." A ListView clipped mid-row says
            // nothing about why the row is sliced, and this shell has no
            // scrollbar to say it with — QtQuick.Controls is deliberately not
            // a dependency (see BluetoothPanel's note). A fade into the card
            // colour is the same cue without the import.
            ListEdgeFade {
                anchors.top: rowListView.top
                atTop: true
                shown: rowListView.contentHeight > rowListView.height && rowListView.contentY > 1
            }

            ListEdgeFade {
                anchors.bottom: rowListView.bottom
                atTop: false
                shown: rowListView.contentHeight > rowListView.height && rowListView.contentY < rowListView.contentHeight - rowListView.height - 1
            }
        }

        // ----------------------------------------------------- empty state
        Column {
            visible: panel.rows.length === 0
            width: parent.width
            spacing: panel.theme.space(1)

            StyledText {
                theme: panel.theme

                width: parent.width
                text: panel.filtering ? "No match" : "All caught up"
            }

            StyledText {
                theme: panel.theme
                muted: true

                width: parent.width
                text: {
                    if (panel.filtering)
                        return "Nothing in the last " + panel.notifs.historyKeepDays + " days matches that.";
                    if (panel.notifs.dnd)
                        return "Do not disturb is on — new notifications queue here silently.";
                    return "Notifications you receive queue here, and stay for " + panel.notifs.historyKeepDays + " days.";
                }
                wrapMode: Text.WordWrap
            }
        }

        // --------------------------------------------------- muted senders
        // Only ever drawn when something is muted. A mute that cannot be seen
        // is indistinguishable from an app that has stopped working, so the
        // list is the other half of the feature, not a detail of it.
        Column {
            id: mutedColumn

            visible: panel.notifs.mutedApps.length > 0
            width: parent.width
            spacing: panel.theme.space(1.5)

            Separator {
                theme: panel.theme
            }

            SectionHeader {
                theme: panel.theme
                width: parent.width
                label: "MUTED · " + panel.notifs.mutedApps.length
            }

            Flow {
                width: parent.width
                spacing: panel.theme.space(1.5)

                Repeater {
                    model: panel.notifs.mutedApps

                    Rectangle {
                        id: mutedChip
                        required property string modelData

                        implicitWidth: mutedRow.implicitWidth + panel.theme.space(3)
                        implicitHeight: mutedRow.implicitHeight + panel.theme.space(1.5)
                        radius: panel.theme.radius(0.5)
                        color: unmuteMouse.containsMouse ? panel.theme.alpha(panel.theme.textPrimary, 0.12) : panel.theme.surface2

                        Row {
                            id: mutedRow
                            anchors.centerIn: parent
                            spacing: panel.theme.space(1.5)

                            StyledText {
                                theme: panel.theme
                                role: StyledText.Small
                                text: mutedChip.modelData
                                anchors.verticalCenter: parent.verticalCenter
                            }

                            OpticalGlyph {
                                text: "󰅖"
                                color: panel.theme.textMuted
                                pixelSize: panel.theme.fontPx(0.75)
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }

                        MouseArea {
                            id: unmuteMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: panel.notifs.unmuteApp(mutedChip.modelData)
                        }

                        PanelHint {
                            theme: panel.theme
                            visible: unmuteMouse.containsMouse
                            anchor: mutedChip
                            text: "Unmute " + mutedChip.modelData
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------------ components
    // The scroll cue described at its two call sites. Fades to the card
    // colour rather than drawing a line, so it reads as "the list continues"
    // instead of as a border.
    component ListEdgeFade: Rectangle {
        required property bool atTop
        required property bool shown

        anchors.left: rowListView.left
        anchors.right: rowListView.right
        height: panel.theme.space(5)
        opacity: shown ? 1 : 0
        gradient: Gradient {
            GradientStop {
                position: 0
                color: atTop ? panel.theme.panel.background : "transparent"
            }
            GradientStop {
                position: 1
                color: atTop ? "transparent" : panel.theme.panel.background
            }
        }

        Behavior on opacity {
            NumberAnimation {
                duration: panel.theme.motion.standard
                easing.type: panel.theme.motion.easing
            }
        }
    }

    component NotifRow: CursorSurface {
        id: notifRow

        theme: panel.theme

        required property var row
        required property int flatIndex

        readonly property var entry: row.entry
        readonly property bool rowSelected: panel.cursorActive && panel.cursorIndex === flatIndex
        readonly property bool showActions: rowMouse.containsMouse || rowSelected
        readonly property string iconSource: panel.iconSourceFor(entry)
        readonly property bool hasGlyph: String(entry.glyph || "").length > 0
        // Live actions, for every row that still has them — NOT gated on the
        // pointer. Gating it there was the other half of the resizing row:
        // a notification whose sender is still alive grew a row of chips the
        // moment you pointed at it, and pushed the whole list below it down.
        readonly property var liveActions: {
            // Depend on the row list so a rebuild refreshes this. liveRefs is
            // a plain JS map and mutating it emits no change signal, so
            // without a dependency this would be evaluated once and keep a
            // torn-down notification's actions forever.
            const rebuilt = panel.rows;
            return rebuilt ? panel.actionsFor(entry) : [];
        }
        readonly property string bodyPreview: Logic.sanitizeBody(entry.body, entry.app, entry.appIcon).replace(/\s+/g, " ").trim()

        hasCursor: rowSelected
        // Unseen is the row itself, not a mark beside it: a dot needed a
        // gutter down the whole list, which cost every row the width and only
        // ever said something about a few of them.
        restingColor: row.unseen ? panel.theme.alpha(panel.theme.accent, 0.1) : "transparent"
        implicitHeight: rowContent.implicitHeight + panel.theme.space(2.5)

        MouseArea {
            id: rowMouse
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.LeftButton | Qt.RightButton
            cursorShape: Qt.PointingHandCursor

            onContainsMouseChanged: if (containsMouse)
                panel.setRowCursor(notifRow.flatIndex)

            onClicked: mouse => {
                if (mouse.button === Qt.RightButton) {
                    panel.dismissRow(notifRow.row);
                    return;
                }
                panel.setRowCursor(notifRow.flatIndex);
                panel.activateCursor();
            }
        }

        Item {
            id: rowContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2)
            anchors.rightMargin: panel.theme.space(2)
            implicitHeight: Math.max(gutter.implicitHeight, info.implicitHeight)

            // Icon with the age under it. The timestamp used to sit at the far
            // right of the first line, which put the two least important
            // things in the row — who sent it and when — at opposite ends of
            // it, and spent a line's width on a string four characters long.
            // Stacked in the gutter it costs no width at all, and the first
            // line is free for the name and the title together.
            Column {
                id: gutter

                anchors.left: parent.left
                anchors.top: parent.top
                width: panel.theme.space(6.5)
                spacing: panel.theme.space(0.5)

                // Fixed slot so every row's text ledge lines up: sender image,
                // else app icon, else the notification's glyph, else a muted
                // bell.
                Item {
                    id: iconSlot
                    width: parent.width
                    height: parent.width

                    Image {
                        id: rowImage
                        anchors.fill: parent
                        source: notifRow.iconSource
                        sourceSize.width: width * Screen.devicePixelRatio
                        sourceSize.height: height * Screen.devicePixelRatio
                        fillMode: Image.PreserveAspectFit
                        asynchronous: true
                        smooth: true
                        visible: status === Image.Ready
                    }

                    Text {
                        textFormat: Text.PlainText
                        anchors.centerIn: parent
                        visible: rowImage.status !== Image.Ready
                        text: notifRow.hasGlyph ? notifRow.entry.glyph : "󰂚"
                        color: notifRow.hasGlyph ? panel.theme.textPrimary : panel.theme.textMuted
                        font.family: "Symbols Nerd Font"
                        font.pixelSize: panel.theme.fontPx(1.5)
                    }
                }

                StyledText {
                    id: timeText
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true
                    muted: true

                    width: parent.width
                    horizontalAlignment: Text.AlignHCenter
                    text: panel.relativeTime(notifRow.entry.timestamp)
                }
            }

            Column {
                id: info

                anchors.left: gutter.right
                anchors.leftMargin: panel.theme.space(2)
                // All the way to the edge. The summary and the message get the
                // full width of the row because the only things competing for
                // it — the two buttons — are up on the first line, inside this
                // column, where they take width from the sender name instead
                // of from the text you are reading.
                anchors.right: parent.right
                anchors.top: parent.top
                spacing: panel.theme.space(0.5)

                // Sender and title on ONE line, with the row's two buttons.
                // The sender used to have a line of its own above the title,
                // which is a whole line spent on a word — over three sections
                // of history that is a third of the list given to something
                // read at a glance. Together they read as one heading, the
                // sender set as a muted caption so the title still carries.
                //
                // The buttons live here rather than centred down the right
                // edge so that the message below them can run the full width
                // of the row. On the edge they took a column off every line of
                // every row, permanently, to hold two controls that are only
                // ever shown for one row at a time.
                Item {
                    width: parent.width
                    height: Math.max(appText.implicitHeight, summaryText.implicitHeight, rowButtons.implicitHeight)

                    StyledText {
                        id: appText
                        theme: panel.theme
                        role: StyledText.Caption
                        mono: true
                        muted: true
                        anchors.left: parent.left
                        anchors.verticalCenter: parent.verticalCenter
                        // Its own width, but never more than a third of the
                        // line: a sender with a long name would otherwise push
                        // the title it is introducing off the row entirely.
                        width: Math.min(implicitWidth, parent.width / 3)
                        text: String(notifRow.entry.app || "Notification").toUpperCase()
                        font.letterSpacing: 1.2
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    StyledText {
                        id: summaryText
                        theme: panel.theme
                        anchors.left: appText.right
                        anchors.leftMargin: panel.theme.space(1.5)
                        anchors.right: rowButtons.left
                        anchors.rightMargin: panel.theme.space(1.5)
                        anchors.verticalCenter: parent.verticalCenter
                        text: notifRow.entry.summary || ""
                        color: notifRow.entry.urgency === 2 ? panel.theme.error : panel.theme.textPrimary
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    // Mute and dismiss, revealed together on hover or under
                    // the keyboard cursor. Both are MouseArea-grab variants
                    // rather than TapHandlers (BluetoothPanel's ForgetButton
                    // reasoning): the row underneath owns a full-fill
                    // MouseArea, and a TapHandler's passive grab would let one
                    // click act AND activate the row.
                    //
                    // Opacity, not visibility, so the space stays reserved and
                    // the row never changes size when you point at it. The
                    // handlers go with the fade — an invisible button still
                    // takes clicks.
                    Row {
                        id: rowButtons

                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: panel.theme.space(1)
                        opacity: notifRow.showActions ? 1 : 0
                        enabled: notifRow.showActions

                        Behavior on opacity {
                            NumberAnimation {
                                duration: panel.theme.motion.standard
                                easing.type: panel.theme.motion.easing
                            }
                        }

                        ChipSurface {
                            id: muteBtn
                            theme: panel.theme
                            width: panel.theme.space(5)
                            height: panel.theme.space(5)
                            pointerOver: muteMouse.containsMouse

                            OpticalGlyph {
                                anchors.centerIn: parent
                                text: "󰂛"
                                color: panel.theme.textPrimary
                                pixelSize: panel.theme.fontPx(0.833)
                            }

                            MouseArea {
                                id: muteMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.muteRow(notifRow.row)
                            }

                            PanelHint {
                                theme: panel.theme
                                visible: muteMouse.containsMouse
                                anchor: muteBtn
                                text: "Mute " + notifRow.entry.app
                            }
                        }

                        ChipSurface {
                            id: dismissBtn
                            theme: panel.theme
                            width: panel.theme.space(5)
                            height: panel.theme.space(5)
                            // An action, not a choice: `chosen` never fires,
                            // so this is the family's plain tile — surface2,
                            // hover lift, hairline.
                            pointerOver: dismissMouse.containsMouse

                            OpticalGlyph {
                                anchors.centerIn: parent
                                text: "󰅖"
                                color: panel.theme.textPrimary
                                pixelSize: panel.theme.fontPx(0.833)
                            }

                            MouseArea {
                                id: dismissMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.dismissRow(notifRow.row)
                            }

                            PanelHint {
                                theme: panel.theme
                                visible: dismissMouse.containsMouse
                                anchor: dismissBtn
                                text: "Dismiss"
                            }
                        }
                    }
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Small
                    muted: true

                    visible: text !== ""
                    width: parent.width
                    text: notifRow.bodyPreview
                    // Two lines, wrapped. One elided line was all a transient
                    // list needed; a message you are looking up days later is
                    // usually the body, not the summary.
                    wrapMode: Text.WordWrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                }

                // Action chips for the cursor row while the sender's live
                // notification still exists (NotificationCard's action row).
                Flow {
                    visible: notifRow.liveActions.length > 0
                    width: parent.width
                    spacing: panel.theme.space(1.5)

                    Repeater {
                        model: notifRow.liveActions

                        Rectangle {
                            id: actionChip
                            required property var modelData

                            implicitWidth: chipLabel.implicitWidth + panel.theme.space(3)
                            implicitHeight: chipLabel.implicitHeight + panel.theme.space(1.5)
                            radius: panel.theme.radius(0.5)
                            color: chipMouse.containsMouse ? panel.theme.alpha(panel.theme.accent, 0.3) : panel.theme.alpha(panel.theme.accent, 0.15)

                            StyledText {
                                id: chipLabel
                                theme: panel.theme
                                role: StyledText.Small
                                anchors.centerIn: parent
                                text: actionChip.modelData.text
                                color: panel.theme.accent
                            }

                            // MouseArea, not TapHandler: the row's own
                            // MouseArea would swallow a TapHandler's press.
                            MouseArea {
                                id: chipMouse
                                anchors.fill: parent
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: panel.invokeAction(notifRow.row, actionChip.modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
