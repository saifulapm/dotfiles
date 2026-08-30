import QtQuick
import "../components"
import "../../../components"
import "PxyModel.js" as Model

// pxy panel — the route's control surface.
//
// ROUTE is a picker over one group's live walk order: the chips choose which
// group to look at, and without a query the rows ARE that group's chain, in
// the order a request would walk it, each with its verdict (eligible, or why
// it would be skipped). Typing filters the whole catalog instead, so anything
// pxy serves is pinnable. Clicking (or Enter) pins that model — one pin leads
// every group's chain, which stays behind it as fallback — and the top row
// clears the pin. COOLDOWNS lists who is benched and for how long; LIMITS one
// meter per provider, fullest first, so "which model should I use" has an
// answer at a glance.
BarPanel {
    id: panel

    required property var pxy

    panelTitle: ""
    cardWidth: theme.space(100)

    // How many rows the picker offers before "keep typing to narrow" kicks
    // in. The ROUTE list scrolls: the viewport stays the height of the old
    // 4-row panel (group row + 4 models) and the rest is reached by wheel or
    // cursor.
    readonly property int maxRows: 20
    // Fullest first, so the cut drops only the providers with headroom.
    readonly property int maxLimits: 10
    readonly property var limitRows: (pxy.limits || []).slice(0, maxLimits)
    readonly property int hiddenLimits: Math.max(0, (pxy.limits || []).length - maxLimits)

    property string query: ""
    property int rowIndex: 0
    // Which group's chain is on screen. Empty until a scan lands, and reset to
    // the first group whenever the scanned set no longer contains it (a group
    // renamed in config.toml must not leave the panel showing nothing).
    property string group: ""

    readonly property var groupChain: pxy.chainOf(group)
    readonly property string groupLabel: {
        const found = (pxy.groups || []).find(g => String(g.name) === group);
        return found ? String(found.label || found.name) : group;
    }
    readonly property var picker: Model.pickerRows(groupChain, pxy.models, query, maxRows)
    // The synthetic "clear pin" row leads the unfiltered list; while searching
    // it would only push real matches down.
    readonly property var listRows: (query === "" ? [
            {
                isGroup: true,
                id: panel.group
            }
        ] : []).concat(picker.rows)

    function syncGroup() {
        const names = (pxy.groups || []).map(g => String(g.name));
        if (names.indexOf(group) === -1)
            group = pxy.firstGroup;
    }

    Connections {
        target: panel.pxy
        function onGroupsChanged() {
            panel.syncGroup();
        }
    }

    Component.onCompleted: syncGroup()

    onQueryChanged: {
        rowIndex = 0;
        routeScroll.contentY = 0;
    }
    onGroupChanged: {
        rowIndex = 0;
        routeScroll.contentY = 0;
    }

    function moveCursor(dy) {
        if (listRows.length === 0)
            return;
        rowIndex = Math.max(0, Math.min(listRows.length - 1, rowIndex + dy));
        routeScroll.reveal(rowIndex);
    }

    function choose(row) {
        if (!row)
            return;
        if (row.isGroup)
            panel.pxy.clearPin();
        else
            panel.pxy.pin(row.id);
        panel.query = "";
        searchField.text = "";
    }

    onContentKey: event => {
        if (event.key === Qt.Key_R && (event.modifiers & Qt.ControlModifier)) {
            panel.pxy.refresh(true);
            event.accepted = true;
        }
    }

    onPanelOpened: {
        panel.query = "";
        panel.rowIndex = 0;
        panel.syncGroup();
        searchField.text = "";
        searchField.focusWhen = true;
    }

    onPanelClosed: searchField.focusWhen = false

    // ------------------------------------------------------------- hero
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "pxy"
        titleColor: panel.pxy.daemonActive ? panel.theme.textPrimary : panel.theme.error
        meta: {
            if (!panel.pxy.daemonActive)
                return "DAEMON DOWN";
            let route = panel.pxy.groups.length + " GROUPS · CHAIN PRIORITY";
            if (panel.pxy.routePin !== "")
                // A stale pin (model dropped from the catalog) is ignored by
                // routing; saying "PINNED" here would lie about the walk.
                route = panel.pxy.routePinActive ? "PINNED · " + Model.modelName(panel.pxy.routePin).toUpperCase() : "PIN STALE · CHAIN PRIORITY";
            return route + " · " + panel.pxy.modelCount + " MODELS";
        }
        metaColor: panel.pxy.daemonActive ? panel.theme.textMuted : panel.theme.error

        icon: OpticalGlyph {
            text: "󰓡"
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.pxy.daemonActive ? panel.theme.textPrimary : panel.theme.error
        }

        trailing: [
            GlyphButton {
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰜉" // md-restart
                busy: panel.pxy.restarting
                hint: panel.pxy.restarting ? "Restarting the daemon…" : "Restart the pxy daemon (needed after config or pass changes)"
                onActivated: panel.pxy.restartDaemon()
            },
            GlyphButton {
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰑐" // md-refresh
                busy: panel.pxy.refreshing
                hint: panel.pxy.refreshing ? "Scanning…" : "Re-scan, remote balances included (Ctrl+R)"
                onActivated: panel.pxy.refresh(true)
            }
        ]
    }

    InfoNote {
        theme: panel.theme
        visible: !panel.pxy.daemonActive || panel.pxy.statusText !== ""
        text: !panel.pxy.daemonActive ? "The pxy daemon is not answering — agents wired to it will stall. Restart it from the button above." : panel.pxy.statusText
    }

    // ------------------------------------------------------------- route
    // No section header: the group tabs are the header — they name what the
    // rows below them are.
    // One tab per group — AiPanel's provider switch, same shape and the same
    // component. Selecting a tab only changes which chain is shown; which
    // group a request uses is the agent's launch model, not a panel setting,
    // so this never writes anything.
    Row {
        id: groupSwitch

        readonly property real cellWidth: panel.pxy.groups.length > 0 ? (width - spacing * (panel.pxy.groups.length - 1)) / panel.pxy.groups.length : 0

        visible: panel.pxy.groups.length > 1
        width: parent.width
        spacing: panel.theme.space(1.5)

        Repeater {
            model: panel.pxy.groups

            ChipSurface {
                id: groupTab

                required property var modelData

                readonly property string name: String(groupTab.modelData.name)
                // The label is what config.toml wants shown ("Pay Per Use");
                // `name` stays the routable id everything else keys on.
                readonly property string label: String(groupTab.modelData.label || groupTab.modelData.name)
                readonly property bool selected: panel.group === groupTab.name

                theme: panel.theme
                width: groupSwitch.cellWidth
                implicitHeight: tabLabel.implicitHeight + panel.theme.space(3)
                chosen: groupTab.selected
                pointerOver: tabHover.hovered

                StyledText {
                    id: tabLabel
                    theme: panel.theme
                    role: StyledText.Small
                    anchors.centerIn: parent
                    text: groupTab.label
                    color: groupTab.selected ? panel.theme.accent : panel.theme.textPrimary
                }

                HoverHandler {
                    id: tabHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: panel.group = groupTab.name
                }
            }
        }
    }

    PanelTextField {
        id: searchField

        theme: panel.theme
        width: parent.width
        inputFont: panel.theme.fontMono
        placeholder: "Search all " + panel.pxy.models.length + " models — Enter pins one ahead of every chain"

        onTextEdited: text => panel.query = text
        onAccepted: panel.choose(panel.listRows[Math.min(panel.rowIndex, panel.listRows.length - 1)])
        onMoveRequested: delta => panel.moveCursor(delta)
        onCancelled: {
            if (panel.query !== "") {
                text = "";
                panel.query = "";
            } else {
                panel.close();
            }
        }
    }

    // The route list scrolls inside a viewport exactly as tall as the old
    // 4-model panel: all 20 offered rows are in the content, the rest is
    // reached by wheel or by moving the cursor past the edge.
    Flickable {
        id: routeScroll

        width: parent.width
        height: Math.min(contentHeight, viewportBottom)
        clip: true
        contentWidth: width
        contentHeight: routeColumn.height
        interactive: contentHeight > height + 1

        // This Qt build has no Flickable.wheelEnabled — handle the wheel
        // manually or the list never scrolls.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const max = Math.max(0, routeScroll.contentHeight - routeScroll.height);
                routeScroll.contentY = Math.max(0, Math.min(max, routeScroll.contentY - event.angleDelta.y));
                event.accepted = true;
            }
        }

        // Bottom edge of the last fully visible row: the clear-pin group row
        // plus 4 model rows when unfiltered, 4 model rows while searching.
        readonly property real viewportBottom: {
            const i = panel.query === "" ? 4 : 3;
            const k = routeRepeater.itemAt(i);
            return k ? k.y + k.height : routeColumn.implicitHeight;
        }

        // Keyboard cursor past the viewport edge pulls the content along.
        function reveal(i) {
            const k = routeRepeater.itemAt(i);
            if (!k)
                return;
            if (k.y < contentY)
                contentY = k.y;
            else if (k.y + k.height > contentY + height)
                contentY = k.y + k.height - height;
        }

        Column {
            id: routeColumn

            width: routeScroll.width
            spacing: panel.theme.space(0.5)

            Repeater {
                id: routeRepeater
                model: panel.listRows

                RouteRow {
                    required property var modelData
                    required property int index

                    width: routeColumn.width
                    row: modelData
                    rowIndex: index
                }
            }
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Caption
        muted: true

        width: parent.width
        text: {
            if (panel.query !== "") {
                if (panel.picker.rows.length === 0)
                    return "Nothing matches “" + panel.query + "”.";
                return panel.picker.hidden > 0 ? panel.picker.hidden + " more — keep typing to narrow" : "";
            }
            if (panel.group === "")
                return "No groups configured — add a [groups.<name>] chain to config.toml.";
            // The list shows the first rows and SCROLLS for the rest (the
            // viewport is 4 models tall), so the count is information, not a
            // promise of hidden rows.
            return panel.groupChain.length + " candidates in “" + panel.groupLabel
                + "” — scroll the list; a pinned model leads, the chain stays as fallback.";
        }
        visible: text !== ""
        wrapMode: Text.WordWrap
    }

    // --------------------------------------------------------- cooldowns
    Separator {
        theme: panel.theme
        visible: panel.pxy.cooldowns.length > 0
    }

    Column {
        visible: panel.pxy.cooldowns.length > 0
        width: parent.width
        spacing: panel.theme.space(1)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "COOLING DOWN"
        }

        Repeater {
            model: panel.pxy.cooldowns

            Item {
                id: coolRow

                required property var modelData

                width: parent.width
                height: coolKey.implicitHeight + panel.theme.space(1)

                StyledText {
                    id: coolKey
                    theme: panel.theme
                    role: StyledText.Small
                    mono: true
                    anchors.left: parent.left
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.right: coolLeft.left
                    anchors.rightMargin: panel.theme.space(2)
                    text: coolRow.modelData.key + "  —  " + coolRow.modelData.reason
                    elide: Text.ElideRight
                    color: coolRow.modelData.retryable === false ? panel.theme.error : panel.theme.textPrimary
                }

                StyledText {
                    id: coolLeft
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true
                    muted: true
                    anchors.right: parent.right
                    anchors.verticalCenter: parent.verticalCenter
                    text: Model.formatSeconds(coolRow.modelData.secondsLeft)
                }
            }
        }
    }

    // ------------------------------------------------------------ limits
    Separator {
        theme: panel.theme
        visible: panel.pxy.limits.length > 0
    }

    Column {
        visible: panel.pxy.limits.length > 0
        width: parent.width
        spacing: panel.theme.space(2)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "PROVIDER LIMITS"
        }

        Repeater {
            model: panel.limitRows

            Column {
                id: limitRow

                required property var modelData

                readonly property real pct: Number(modelData.percent)
                readonly property bool alarming: pct >= 0.9

                width: parent.width
                spacing: panel.theme.space(1)

                Item {
                    width: parent.width
                    height: limitName.implicitHeight

                    StyledText {
                        id: limitName
                        theme: panel.theme
                        role: StyledText.Small
                        anchors.left: parent.left
                        text: limitRow.modelData.name
                    }

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Small
                        mono: true
                        anchors.right: parent.right
                        visible: limitRow.pct >= 0
                        text: Math.round(limitRow.pct * 100) + "%"
                        color: limitRow.alarming ? panel.theme.error : panel.theme.textPrimary
                    }
                }

                Item {
                    width: parent.width
                    height: panel.theme.space(1.25)
                    visible: limitRow.pct >= 0

                    Rectangle {
                        id: limitTrack
                        anchors.fill: parent
                        radius: height / 2
                        color: panel.theme.surface3
                    }

                    Rectangle {
                        anchors.left: limitTrack.left
                        anchors.verticalCenter: limitTrack.verticalCenter
                        height: limitTrack.height
                        radius: limitTrack.radius
                        width: limitTrack.width * Math.max(0, Math.min(1, limitRow.pct))
                        color: limitRow.alarming ? panel.theme.error : panel.theme.accent

                        Behavior on width {
                            NumberAnimation {
                                duration: panel.theme.time(1)
                                easing.type: panel.theme.motion.easing
                            }
                        }
                    }
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    muted: true
                    width: parent.width
                    text: limitRow.modelData.detail
                    elide: Text.ElideRight
                }
            }
        }

        StyledText {
            theme: panel.theme
            role: StyledText.Caption
            muted: true

            visible: panel.hiddenLimits > 0
            width: parent.width
            text: panel.hiddenLimits + " more with headroom — `pxy status --remote` lists them all"
        }
    }

    // ---------------------------------------------------------- components
    component RouteRow: CursorSurface {
        id: routeRow

        theme: panel.theme

        property var row: null
        property int rowIndex: 0

        readonly property bool rowSelected: panel.rowIndex === rowIndex
        readonly property bool isGroup: !!row && row.isGroup === true
        readonly property bool isCurrent: isGroup ? panel.pxy.routePin === "" : (!!row && row.pinned === true)
        readonly property bool eligible: isGroup || !row || row.eligible !== false

        hasCursor: rowSelected
        bordered: false
        current: rowSelected
        implicitHeight: routeContent.implicitHeight + panel.theme.space(2.5)

        MouseArea {
            id: routeMouse
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onContainsMouseChanged: if (containsMouse)
                panel.rowIndex = routeRow.rowIndex
            onClicked: {
                panel.rowIndex = routeRow.rowIndex;
                panel.choose(routeRow.row);
            }
        }

        Item {
            id: routeContent

            anchors.left: parent.left
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            anchors.rightMargin: panel.theme.space(2.5)
            implicitHeight: routeLabels.implicitHeight

            // Eligibility at a glance: accent = would serve, muted = would
            // be skipped right now (the caption says why).
            Rectangle {
                id: routeDot
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                width: panel.theme.space(1.5)
                height: width
                radius: width / 2
                color: routeRow.eligible ? panel.theme.accent : panel.theme.surface3
                border.width: panel.theme.borderWidth
                border.color: routeRow.eligible ? panel.theme.accent : panel.theme.textMuted
            }

            Column {
                id: routeLabels

                anchors.left: routeDot.right
                anchors.leftMargin: panel.theme.space(2.5)
                anchors.right: routeMark.left
                anchors.rightMargin: panel.theme.space(2)
                anchors.verticalCenter: parent.verticalCenter
                spacing: panel.theme.space(0.25)

                StyledText {
                    theme: panel.theme

                    width: parent.width
                    // Two accounts of one provider expand into two rows with
                    // the same model id — the account tag tells them apart.
                    text: routeRow.isGroup ? panel.groupLabel + " — chain priority"
                        : Model.modelName(routeRow.row ? routeRow.row.id : "")
                            + (routeRow.row && routeRow.row.account
                                ? "  [" + routeRow.row.account + "]" : "")
                    elide: Text.ElideRight
                    font.weight: routeRow.isCurrent ? Font.DemiBold : Font.Normal
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: !routeRow.isGroup
                    muted: true

                    visible: text !== ""
                    width: parent.width
                    text: {
                        if (routeRow.isGroup)
                            return panel.pxy.routePin === "" ? "" : "Clear the pin — every group follows its configured chain again";
                        const provider = routeRow.row && routeRow.row.provider ? routeRow.row.provider : Model.providerOf(routeRow.row ? routeRow.row.id : "");
                        const caption = Model.rowCaption(routeRow.row);
                        return caption === "" ? provider : provider + "  ·  " + caption;
                    }
                    elide: Text.ElideRight
                }
            }

            // md-pin for the current selection (the pinned model, or Auto
            // when nothing is pinned).
            OpticalGlyph {
                id: routeMark
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                visible: routeRow.isCurrent
                text: "󰐃"
                verticalInkCenter: true
                color: panel.theme.accent
                pixelSize: panel.theme.fontPx(0.9)
            }
        }
    }
}
