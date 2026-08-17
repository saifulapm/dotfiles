import QtQuick
import Quickshell
import "../components"
import "../../../components"
import "../../Notifications/NotificationLogic.js" as Logic

// Notification history center — the review surface over Services/Notifs.qml's
// two history buckets: pending (received but not yet seen) and past (already
// seen, kept for the service's 15-minute replay window). Omarchy's service
// comments describe this panel ("the Past tab in the history panel") but
// their repo ships no implementation, so the surface itself is ours, built
// on the same BarPanel scaffold and cursor model as the Bluetooth panel.
//
// Closing the panel marks every pending entry seen: the list was just on
// screen, so the bell's unseen badge resets and the entries move to the
// RECENT bucket, where the service's TTL sweep retires them.
BarPanel {
    id: panel

    required property var notifs

    // The bar's closeNotifCenter/notifCenterOpen use this to tell the center
    // apart from the widget panels sharing the activePanel slot.
    readonly property bool isNotifCenter: true

    cardWidth: theme.space(95)

    readonly property int unseenCount: notifs.pendingModel.count
    readonly property int recentCount: notifs.pastModel.count

    // ---------------------------------------------------------------- rows
    // Both buckets flattened into one list — pending first — so a single
    // ListView owns the viewport and the cursor works in flat indexes
    // (the Bluetooth panel's scrollRows shape). Rebuilt when either count
    // changes; rows are plain snapshots, safe to hold across model edits.
    readonly property var rows: {
        const out = [];
        for (let i = 0; i < notifs.pendingModel.count; i++)
            out.push({
                entry: notifs.snapshotFromRow(notifs.pendingModel.get(i)),
                section: "pending",
                indexInSection: i
            });
        for (let j = 0; j < notifs.pastModel.count; j++)
            out.push({
                entry: notifs.snapshotFromRow(notifs.pastModel.get(j)),
                section: "past",
                indexInSection: j
            });
        return out;
    }

    function sectionTitleAt(index) {
        if (index < 0 || index >= rows.length)
            return "";
        if (index > 0 && rows[index - 1].section === rows[index].section)
            return "";
        return rows[index].section === "pending" ? "UNSEEN" : "RECENT";
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
        if (row.section === "pending")
            notifs.markSeenByOriginalId(row.entry.originalId);
        if (invoked)
            panel.close();
    }

    function dismissCursor() {
        if (cursorIndex < 0)
            return;
        dismissRow(rows[cursorIndex]);
    }

    function dismissRow(row) {
        if (!row)
            return;
        if (row.section === "pending")
            notifs.dismissPending(row.indexInSection);
        else
            notifs.dismissPast(row.indexInSection);
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
        if (row.section === "pending")
            notifs.markSeenByOriginalId(row.entry.originalId);
        panel.close();
    }

    // ----------------------------------------------------------- timestamps
    // Ticks only while the panel is open — relative labels stay honest
    // without any background polling.
    property double nowMs: Date.now()

    Timer {
        running: panel.opened
        interval: 30000
        repeat: true
        onTriggered: panel.nowMs = Date.now()
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
        cursorActive = false;
        cursorIndex = panel.rows.length > 0 ? 0 : -1;
    }

    // Reviewed: the unseen bucket was on screen, so it has been seen.
    onPanelClosed: {
        if (notifs.pendingModel.count > 0)
            notifs.markAllSeen();
    }

    // ------------------------------------------------------------ keyboard
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

            Column {
                id: heroLabels
                anchors.left: heroIcon.right
                anchors.leftMargin: panel.theme.space(3)
                anchors.right: dndSwitch.left
                anchors.rightMargin: panel.theme.space(3)
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.5)

                Text {
                    width: parent.width
                    text: "Notifications"
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(1.083)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    text: {
                        const parts = [];
                        if (panel.notifs.dnd)
                            parts.push("SILENCED");
                        if (panel.unseenCount > 0)
                            parts.push(panel.unseenCount + " UNSEEN");
                        if (panel.recentCount > 0)
                            parts.push(panel.recentCount + " RECENT");
                        return parts.length > 0 ? parts.join(" · ") : "ALL CAUGHT UP";
                    }
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontMono
                    font.pixelSize: panel.theme.fontPx(0.75)
                    font.letterSpacing: 1.2
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }
            }
        }

        Separator {
            theme: panel.theme
        }

        // ------------------------------------------------------------ list
        ListView {
            id: rowListView

            width: parent.width
            height: Math.min(contentHeight, panel.theme.space(100))
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
                readonly property string sectionTitle: panel.sectionTitleAt(index)

                width: ListView.view.width
                height: delegateColumn.implicitHeight

                Column {
                    id: delegateColumn
                    width: parent.width
                    spacing: panel.theme.space(1.5)

                    Separator {
                        theme: panel.theme
                        visible: index > 0 && sectionTitle !== ""
                        height: visible ? 1 : 0
                    }

                    // Bucket header with its clear-all affordance on the
                    // trailing edge.
                    Item {
                        visible: sectionTitle !== ""
                        width: parent.width
                        height: visible ? panel.theme.space(6) : 0

                        SectionHeader {
                            theme: panel.theme
                            anchors.left: parent.left
                            anchors.right: clearAction.left
                            anchors.verticalCenter: parent.verticalCenter
                            label: sectionTitle + " · " + (modelData.section === "pending" ? panel.unseenCount : panel.recentCount)
                        }

                        Text {
                            id: clearAction
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "CLEAR"
                            color: clearMouse.containsMouse ? panel.theme.textPrimary : panel.theme.textMuted
                            font.family: panel.theme.fontMono
                            font.pixelSize: panel.theme.fontPx(0.75)
                            font.letterSpacing: 1.2
                            font.weight: Font.DemiBold

                            MouseArea {
                                id: clearMouse
                                anchors.fill: parent
                                anchors.margins: -panel.theme.space(1)
                                hoverEnabled: true
                                cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    if (modelData.section === "pending")
                                        panel.notifs.clearPending();
                                    else
                                        panel.notifs.clearPast();
                                }
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

        // ----------------------------------------------------- empty state
        Column {
            visible: panel.rows.length === 0
            width: parent.width
            spacing: panel.theme.space(1)

            Text {
                width: parent.width
                text: "All caught up"
                color: panel.theme.textPrimary
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
            }

            Text {
                width: parent.width
                text: panel.notifs.dnd ? "Do not disturb is on — new notifications queue here silently." : "Notifications you receive will queue here."
                color: panel.theme.textMuted
                font.family: panel.theme.fontUi
                font.pixelSize: panel.theme.fontPx(0.917)
                wrapMode: Text.WordWrap
            }
        }
    }

    // ------------------------------------------------------------ components
    component NotifRow: CursorSurface {
        id: notifRow

        theme: panel.theme

        required property var row
        required property int flatIndex

        readonly property var entry: row.entry
        readonly property bool rowSelected: panel.cursorActive && panel.cursorIndex === flatIndex
        readonly property bool showDismiss: rowMouse.containsMouse || rowSelected
        readonly property string iconSource: panel.iconSourceFor(entry)
        readonly property bool hasGlyph: String(entry.glyph || "").length > 0
        // Live actions only materialize for the row under the cursor — the
        // lookup walks liveRefs, which mutates without change signals.
        readonly property var liveActions: showDismiss ? panel.actionsFor(entry) : []
        readonly property string bodyPreview: Logic.sanitizeBody(entry.body, entry.app, entry.appIcon).replace(/\s+/g, " ").trim()

        hasCursor: rowSelected
        implicitHeight: rowContent.implicitHeight + panel.theme.space(3)

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
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: Math.max(iconSlot.height, info.implicitHeight)

            // Fixed icon slot so every row's text ledge lines up: sender
            // image, else app icon, else the notification's glyph, else a
            // muted bell.
            Item {
                id: iconSlot
                anchors.left: parent.left
                anchors.top: parent.top
                width: panel.theme.space(9)
                height: panel.theme.space(9)

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
                    anchors.centerIn: parent
                    visible: rowImage.status !== Image.Ready
                    text: notifRow.hasGlyph ? notifRow.entry.glyph : "󰂚"
                    color: notifRow.hasGlyph ? panel.theme.textPrimary : panel.theme.textMuted
                    font.family: "Symbols Nerd Font"
                    font.pixelSize: panel.theme.fontPx(1.5)
                }
            }

            Column {
                id: info

                anchors.left: iconSlot.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: dismissBtn.visible ? dismissBtn.left : parent.right
                anchors.rightMargin: dismissBtn.visible ? panel.theme.space(2) : 0
                anchors.top: parent.top
                spacing: panel.theme.space(0.5)

                Item {
                    width: parent.width
                    height: summaryText.implicitHeight

                    Text {
                        id: summaryText
                        anchors.left: parent.left
                        anchors.right: timeText.visible ? timeText.left : parent.right
                        anchors.rightMargin: timeText.visible ? panel.theme.space(2) : 0
                        text: notifRow.entry.summary || notifRow.entry.app || "Notification"
                        color: notifRow.entry.urgency === 2 ? panel.theme.error : panel.theme.textPrimary
                        font.family: panel.theme.fontUi
                        font.pixelSize: panel.theme.fontPx(0.917)
                        font.weight: Font.DemiBold
                        elide: Text.ElideRight
                    }

                    Text {
                        id: timeText
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        visible: !notifRow.showDismiss
                        text: panel.relativeTime(notifRow.entry.timestamp)
                        color: panel.theme.textMuted
                        font.family: panel.theme.fontMono
                        font.pixelSize: panel.theme.fontPx(0.75)
                    }
                }

                Text {
                    visible: text !== ""
                    width: parent.width
                    text: notifRow.bodyPreview !== "" ? notifRow.bodyPreview : notifRow.entry.app
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.833)
                    elide: Text.ElideRight
                    maximumLineCount: 1
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

                            Text {
                                id: chipLabel
                                anchors.centerIn: parent
                                text: actionChip.modelData.text
                                color: panel.theme.accent
                                font.family: panel.theme.fontUi
                                font.pixelSize: panel.theme.fontPx(0.833)
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

            // The MouseArea-grab dismiss variant (BluetoothPanel's
            // ForgetButton reasoning): the row underneath owns a full-fill
            // MouseArea, and a TapHandler's passive grab would let one click
            // dismiss AND activate.
            Rectangle {
                id: dismissBtn

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(6)
                height: panel.theme.space(6)
                visible: notifRow.showDismiss
                radius: panel.theme.radius(0.75)
                color: dismissMouse.containsMouse ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2
                border.width: panel.theme.borderWidth
                border.color: panel.theme.surface3

                OpticalGlyph {
                    anchors.centerIn: parent
                    text: "󰅖"
                    color: panel.theme.textPrimary
                    pixelSize: panel.theme.fontPx(0.917)
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
}
