import QtQuick
import "../components"
import "../../../components"
import "PxyModel.js" as Model

// pxy panel — the route's control surface, on three pages.
//
// One stacked column of everything (route + activity + cooldowns + limits)
// grew past the height of a laptop screen, and BarPanel clips rather than
// scrolls, so the limits were simply unreachable on eDP-1. The card now holds
// a fixed-height body and a view switch over it: ROUTE is the interactive
// page, ACTIVITY and LIMITS are the two read-only dashboards, each scrolling
// inside the same viewport. The card's height no longer depends on how many
// providers or cooldowns exist.
//
// ROUTE is a picker over one group's live walk order: the chips choose which
// group to look at, and without a query the rows ARE that group's chain, in
// the order a request would walk it, each with its verdict (eligible, or why
// it would be skipped). Typing filters the whole catalog instead, so anything
// pxy serves is pinnable. Clicking (or Enter) pins that model into the group
// on screen — the pin leads that group's chain, which stays behind it as
// fallback, and no other group notices — and the top row clears that group's
// pin.
BarPanel {
    id: panel

    required property var pxy

    panelTitle: ""
    cardWidth: theme.space(100)

    // The ceiling on the body, and so on the card: hero, view switch and card
    // padding are the only things above it, and every page scrolls once it
    // would grow past this. The screen term is what a short output (the
    // MacBook's 1066 logical rows) needs — BarPanel clips rather than scrolls,
    // so a body that ignored it would simply lose its bottom rows.
    readonly property real bodyHeight: Math.min(theme.space(115), panel.height - theme.barHeight - theme.space(34))

    // How many rows the picker offers before "keep typing to narrow" kicks in.
    readonly property int maxRows: 20

    property string query: ""
    property int rowIndex: 0
    // 0 route · 1 activity · 2 limits.
    property int tab: 0
    // Which group's chain is on screen. Empty until a scan lands, and reset to
    // the first group whenever the scanned set no longer contains it (a group
    // renamed in config.toml must not leave the panel showing nothing).
    property string group: ""

    readonly property var groupChain: pxy.chainOf(group)
    readonly property string groupLabel: {
        const found = (pxy.groups || []).find(g => String(g.name) === group);
        return found ? String(found.label || found.name) : group;
    }
    // The pin of the group on screen: {model, active} or null.
    readonly property var groupPin: pxy.pinOf(group)
    readonly property var picker: Model.pickerRows(groupChain, pxy.models, query, maxRows)
    // The last day's legs, keyed by "provider/model": the route rows read
    // their own latency and error rate out of this.
    readonly property var statsByModel: Model.statsByModel(pxy.stats)
    readonly property int statLegs: Number((pxy.stats && pxy.stats.legs) || 0)

    // The fullest provider, which is the one fact the LIMITS tab can carry
    // without being opened. -1 when nothing reports a usable percentage.
    readonly property real worstLimit: {
        let top = -1;
        const rows = pxy.limits || [];
        for (let i = 0; i < rows.length; i++)
            top = Math.max(top, Number(rows[i].percent));
        return top;
    }

    // The view switch. Each tab carries the number that decides whether it is
    // worth opening — so a cooldown or a blown quota is visible from the page
    // you happen to be on.
    readonly property var tabDefs: [
        {
            label: "Route",
            badge: panel.pxy.pinnedCount > 0 ? panel.pxy.pinnedCount + (panel.pxy.pinnedCount === 1 ? " pin" : " pins") : panel.pxy.groups.length + " groups",
            alarm: false
        },
        {
            label: "Activity",
            badge: panel.pxy.cooldowns.length > 0 ? panel.pxy.cooldowns.length + " cooling" : (panel.statLegs > 0 ? panel.statLegs + " legs" : "quiet"),
            alarm: panel.pxy.cooldowns.length > 0
        },
        {
            label: "Limits",
            badge: panel.worstLimit >= 0 ? Math.round(panel.worstLimit * 100) + "%" : panel.pxy.limits.length + " known",
            alarm: panel.worstLimit >= 0.9
        }
    ]

    function statFor(id) {
        return statsByModel[String(id || "")] || null;
    }
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

    // A hidden TextInput cannot hold focus, so leaving ROUTE would otherwise
    // leave the card with no focused item at all and Escape would stop
    // closing it. Focus follows the page.
    onTabChanged: {
        if (tab === 0)
            Qt.callLater(searchField.takeFocus);
        else
            panel.refocusKeys();
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
            panel.pxy.clearPin(panel.group);
        else
            panel.pxy.pin(panel.group, row.id);
        panel.query = "";
        searchField.text = "";
    }

    // Claimed BEFORE the search field can eat them — a focused TextInput
    // accepts Alt chords as text rather than ignoring them, so the card's key
    // catcher never sees them (PassPanel.handleChord documents the measurement).
    // Routed from both places, so the chords work on every page.
    function handleChord(event) {
        if ((event.modifiers & Qt.ControlModifier) && event.key === Qt.Key_R)
            panel.pxy.refresh(true);
        else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Left)
            panel.tab = (panel.tab + panel.tabDefs.length - 1) % panel.tabDefs.length;
        else if ((event.modifiers & Qt.AltModifier) && event.key === Qt.Key_Right)
            panel.tab = (panel.tab + 1) % panel.tabDefs.length;
        else
            return;
        event.accepted = true;
    }

    onContentKey: event => panel.handleChord(event)

    onPanelOpened: {
        panel.query = "";
        panel.rowIndex = 0;
        panel.tab = 0;
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
        // Just the catalog and the pins: how many groups there are is on the
        // ROUTE tab, and the chips below it name them.
        meta: {
            if (!panel.pxy.daemonActive)
                return "DAEMON DOWN";
            return panel.pxy.modelCount + " MODELS" + (panel.pxy.pinnedCount > 0 ? " · " + panel.pxy.pinnedCount + " PINNED" : "");
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

    // ------------------------------------------------------- view switch
    // Two lines per segment (name over its live number) is what tells this
    // apart from the group chips one row below it — same ChipSurface, taller
    // and louder, because it governs the whole body rather than one list.
    Row {
        id: viewTabs

        readonly property real cellWidth: (width - spacing * (panel.tabDefs.length - 1)) / panel.tabDefs.length

        width: parent.width
        spacing: panel.theme.space(1.5)

        Repeater {
            model: panel.tabDefs

            ChipSurface {
                id: viewTab

                required property var modelData
                required property int index

                readonly property bool selected: panel.tab === viewTab.index

                theme: panel.theme
                width: viewTabs.cellWidth
                height: viewLabels.implicitHeight + panel.theme.space(3)
                chosen: viewTab.selected
                pointerOver: viewHover.hovered

                Column {
                    id: viewLabels
                    anchors.centerIn: parent
                    spacing: panel.theme.space(0.25)

                    StyledText {
                        theme: panel.theme
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: viewTab.modelData.label
                        color: viewTab.selected ? panel.theme.accent : panel.theme.textPrimary
                        font.weight: viewTab.selected ? Font.DemiBold : Font.Normal
                    }

                    StyledText {
                        theme: panel.theme
                        role: StyledText.Caption
                        mono: true
                        muted: !viewTab.modelData.alarm
                        anchors.horizontalCenter: parent.horizontalCenter
                        text: viewTab.modelData.badge
                        color: viewTab.modelData.alarm ? panel.theme.error : panel.theme.textMuted
                    }
                }

                HoverHandler {
                    id: viewHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: panel.tab = viewTab.index
                }
            }
        }
    }

    // -------------------------------------------------------------- body
    // One well, three pages, and the card's height is hero + switch + this.
    // The well takes the height of whichever page is showing, CAPPED at
    // bodyHeight — a fixed well left half the card empty whenever a group had
    // four models, and "too long" is not fixed by making it always tall.
    Item {
        width: parent.width
        height: panel.tab === 0 ? routePage.height : (panel.tab === 1 ? activityScroll.height : limitsScroll.height)

        // ----------------------------------------------------- route page
        Column {
            id: routePage

            width: parent.width
            visible: panel.tab === 0
            spacing: panel.theme.space(2)

            // One tab per group — AiPanel's provider switch, same shape and
            // the same component. Selecting a tab only changes which chain is
            // shown; which group a request uses is the agent's launch model,
            // not a panel setting, so this never writes anything.
            Column {
                id: routeHead

                width: parent.width
                spacing: panel.theme.space(2)

                Row {
                    id: groupSwitch

                    readonly property real cellWidth: panel.pxy.groups.length > 0 ? (width - spacing * (panel.pxy.groups.length - 1)) / panel.pxy.groups.length : 0

                    visible: panel.pxy.groups.length > 1
                    width: parent.width
                    spacing: panel.theme.space(1)

                    Repeater {
                        model: panel.pxy.groups

                        ChipSurface {
                            id: groupTab

                            required property var modelData

                            readonly property string name: String(groupTab.modelData.name)
                            // The label is what config.toml wants shown ("Pay
                            // Per Use"); `name` stays the routable id
                            // everything else keys on.
                            readonly property string label: String(groupTab.modelData.label || groupTab.modelData.name)
                            readonly property bool selected: panel.group === groupTab.name
                            readonly property bool pinned: panel.pxy.pinOf(groupTab.name) !== null

                            theme: panel.theme
                            width: groupSwitch.cellWidth
                            height: tabLabel.implicitHeight + panel.theme.space(2)
                            chosen: groupTab.selected
                            pointerOver: tabHover.hovered

                            StyledText {
                                id: tabLabel
                                theme: panel.theme
                                role: StyledText.Small
                                anchors.centerIn: parent
                                // md-pin after the label: which groups are
                                // steered is visible without clicking through
                                // every tab.
                                text: groupTab.label + (groupTab.pinned ? " 󰐃" : "")
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
                    placeholder: "Search " + panel.pxy.models.length + " models — Enter pins into “" + panel.groupLabel + "”"

                    onTextEdited: text => panel.query = text
                    onAccepted: panel.choose(panel.listRows[Math.min(panel.rowIndex, panel.listRows.length - 1)])
                    onMoveRequested: delta => panel.moveCursor(delta)
                    onChord: event => panel.handleChord(event)
                    onCancelled: {
                        if (panel.query !== "") {
                            text = "";
                            panel.query = "";
                        } else {
                            panel.close();
                        }
                    }
                }
            }

            // The list grows with its rows until it would push the card past
            // the cap, then scrolls — the viewport is a consequence of the
            // card's height, not a row count this file has to guess.
            ScrollArea {
                id: routeScroll

                width: parent.width
                height: Math.min(contentHeight, panel.bodyHeight - routeHead.height - routeFoot.height - routePage.spacing * 2)
                contentHeight: routeColumn.height

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
                id: routeFoot

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
                    const tail = panel.groupPin ? (panel.groupPin.active ? "the pin leads, the chain follows" : "the pin is STALE (not in the catalog), chain order applies") : "a pin here steers only this group";
                    return panel.groupChain.length + " candidates · " + tail;
                }
                elide: Text.ElideRight
            }
        }

        // -------------------------------------------------- activity page
        // What the router actually did in the last day, from pxy's per-leg
        // rows, and who is benched right now. It answers the two questions the
        // walk order on ROUTE cannot: how a candidate has been behaving, and
        // why one of them is being skipped.
        ScrollArea {
            id: activityScroll

            width: parent.width
            height: Math.min(contentHeight, panel.bodyHeight)
            visible: panel.tab === 1
            contentHeight: activityColumn.height

            Column {
                id: activityColumn

                width: activityScroll.width
                spacing: panel.theme.space(1)

                StyledText {
                    theme: panel.theme
                    role: StyledText.Small
                    muted: true
                    width: parent.width
                    visible: panel.statLegs === 0 && panel.pxy.cooldowns.length === 0
                    text: "No traffic in the last 24 hours."
                    wrapMode: Text.WordWrap
                }

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    visible: panel.statLegs > 0
                    label: "LAST 24H"
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    mono: true
                    muted: true
                    width: parent.width
                    visible: panel.statLegs > 0
                    text: Model.activitySummary(panel.pxy.stats)
                    wrapMode: Text.WordWrap
                }

                Item {
                    width: parent.width
                    height: panel.theme.space(1)
                    visible: panel.statLegs > 0
                }

                Repeater {
                    model: Model.activityRows(panel.pxy.stats, 8)

                    Item {
                        id: activityRow

                        required property var modelData

                        width: activityColumn.width
                        height: activityName.implicitHeight + panel.theme.space(1)

                        StyledText {
                            id: activityName
                            theme: panel.theme
                            role: StyledText.Small
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: activityDetail.left
                            anchors.rightMargin: panel.theme.space(2)
                            text: Model.modelName(activityRow.modelData.name)
                            elide: Text.ElideRight
                        }

                        StyledText {
                            id: activityDetail
                            theme: panel.theme
                            role: StyledText.Caption
                            mono: true
                            muted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: Model.activityDetail(activityRow.modelData)
                        }
                    }
                }

                StyledText {
                    theme: panel.theme
                    role: StyledText.Caption
                    muted: true
                    width: parent.width
                    visible: text !== ""
                    text: {
                        const line = Model.toolsLine(panel.pxy.stats);
                        return line === "" ? "" : "tools: " + line;
                    }
                    wrapMode: Text.WordWrap
                }

                // The failures, folded by reason. COOLING DOWN below says who
                // is benched right now; this says what has been going wrong,
                // including the errors that never earned a cooldown.
                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    // A header needs air above it or it reads as another row
                    // of the list it is meant to end; the label centers, so
                    // the extra height lands on both sides of it.
                    height: implicitHeight + panel.theme.space(2)
                    visible: Model.topErrors(panel.pxy.stats, 5).length > 0
                    label: "FAILURES"
                }

                Repeater {
                    model: Model.topErrors(panel.pxy.stats, 5)

                    Item {
                        id: errorRow

                        required property var modelData

                        width: activityColumn.width
                        height: errorReason.implicitHeight + panel.theme.space(1)

                        StyledText {
                            id: errorReason
                            theme: panel.theme
                            role: StyledText.Caption
                            mono: true
                            anchors.left: parent.left
                            anchors.verticalCenter: parent.verticalCenter
                            anchors.right: errorCount.left
                            anchors.rightMargin: panel.theme.space(2)
                            text: errorRow.modelData.reason
                            elide: Text.ElideRight
                            color: panel.theme.error
                        }

                        StyledText {
                            id: errorCount
                            theme: panel.theme
                            role: StyledText.Caption
                            mono: true
                            muted: true
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            text: "×" + errorRow.modelData.count + "  " + Model.modelName(errorRow.modelData.lastCandidate)
                        }
                    }
                }

                SectionHeader {
                    theme: panel.theme
                    width: parent.width
                    height: implicitHeight + panel.theme.space(2)
                    visible: panel.pxy.cooldowns.length > 0
                    label: "COOLING DOWN"
                    value: panel.pxy.cooldowns.length > 0 ? String(panel.pxy.cooldowns.length) : ""
                    valueColor: panel.theme.error
                }

                Repeater {
                    model: panel.pxy.cooldowns

                    Item {
                        id: coolRow

                        required property var modelData

                        width: activityColumn.width
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
        }

        // ---------------------------------------------------- limits page
        // One meter per provider, fullest first, so "which model should I use"
        // has an answer at a glance. Every provider is here now — the page
        // scrolls, so there is no cut and no "5 more with headroom" footnote.
        ScrollArea {
            id: limitsScroll

            width: parent.width
            height: Math.min(contentHeight, panel.bodyHeight)
            visible: panel.tab === 2
            contentHeight: limitsColumn.height

            Column {
                id: limitsColumn

                width: limitsScroll.width
                spacing: panel.theme.space(2)

                StyledText {
                    theme: panel.theme
                    role: StyledText.Small
                    muted: true
                    width: parent.width
                    visible: panel.pxy.limits.length === 0
                    text: "No provider limits reported — re-scan with remote balances (Ctrl+R)."
                    wrapMode: Text.WordWrap
                }

                Repeater {
                    model: panel.pxy.limits

                    // Name, what is left, and the percentage on ONE line, with
                    // the meter as a hairline under it: the old three-line
                    // block spent most of the panel's height on ten rows that
                    // are usually all at 0%.
                    Column {
                        id: limitRow

                        required property var modelData

                        readonly property real pct: Number(modelData.percent)
                        readonly property bool known: pct >= 0
                        readonly property color tone: pct >= 1 ? panel.theme.error : (pct >= 0.75 ? panel.theme.warn : panel.theme.accent)

                        width: limitsColumn.width
                        spacing: panel.theme.space(1)

                        Item {
                            width: parent.width
                            height: limitName.implicitHeight

                            StyledText {
                                id: limitName
                                theme: panel.theme
                                role: StyledText.Small
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                text: limitRow.modelData.name
                            }

                            StyledText {
                                id: limitPct
                                theme: panel.theme
                                role: StyledText.Small
                                mono: true
                                anchors.right: parent.right
                                anchors.verticalCenter: parent.verticalCenter
                                visible: limitRow.known
                                text: Math.round(limitRow.pct * 100) + "%"
                                color: limitRow.pct >= 0.75 ? limitRow.tone : panel.theme.textPrimary
                            }

                            StyledText {
                                theme: panel.theme
                                role: StyledText.Caption
                                mono: true
                                muted: true
                                anchors.left: limitName.right
                                anchors.leftMargin: panel.theme.space(2)
                                anchors.right: limitPct.visible ? limitPct.left : parent.right
                                anchors.rightMargin: panel.theme.space(2)
                                anchors.verticalCenter: parent.verticalCenter
                                horizontalAlignment: Text.AlignRight
                                text: limitRow.modelData.detail
                                elide: Text.ElideRight
                            }
                        }

                        Rectangle {
                            id: limitTrack

                            width: parent.width
                            height: panel.theme.space(0.5)
                            radius: height / 2
                            color: panel.theme.surface3
                            visible: limitRow.known

                            Rectangle {
                                anchors.left: parent.left
                                anchors.verticalCenter: parent.verticalCenter
                                height: parent.height
                                radius: parent.radius
                                width: parent.width * Math.max(0, Math.min(1, limitRow.pct))
                                color: limitRow.tone

                                Behavior on width {
                                    NumberAnimation {
                                        duration: panel.theme.time(1)
                                        easing.type: panel.theme.motion.easing
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- components
    // This Qt build has no Flickable.wheelEnabled — the wheel is handled
    // manually or a list never scrolls. All three pages need it, so the
    // workaround lives here once.
    component ScrollArea: Flickable {
        id: area

        contentWidth: width
        interactive: contentHeight > height + 1
        boundsBehavior: Flickable.StopAtBounds
        clip: true

        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => {
                const max = Math.max(0, area.contentHeight - area.height);
                area.contentY = Math.max(0, Math.min(max, area.contentY - event.angleDelta.y));
                event.accepted = true;
            }
        }
    }

    component RouteRow: CursorSurface {
        id: routeRow

        theme: panel.theme

        property var row: null
        property int rowIndex: 0

        readonly property bool rowSelected: panel.rowIndex === rowIndex
        readonly property bool isGroup: !!row && row.isGroup === true
        readonly property bool isCurrent: isGroup ? panel.groupPin === null : (!!row && row.pinned === true)
        readonly property bool eligible: isGroup || !row || row.eligible !== false

        hasCursor: rowSelected
        bordered: false
        current: rowSelected
        implicitHeight: routeContent.implicitHeight + panel.theme.space(2)

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
                    text: routeRow.isGroup ? panel.groupLabel + " — chain priority" : Model.modelName(routeRow.row ? routeRow.row.id : "") + (routeRow.row && routeRow.row.account ? "  [" + routeRow.row.account + "]" : "")
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
                            return panel.groupPin === null ? "" : "Clear the pin — “" + panel.groupLabel + "” follows its configured chain again";
                        return Model.rowSubtitle(routeRow.row, panel.statFor(routeRow.row ? routeRow.row.id : ""));
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
