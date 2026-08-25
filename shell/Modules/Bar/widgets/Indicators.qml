import QtQuick
import "../components"

// Indicator container, ported from omarchy's Indicators widget.
//
// Two blocks sit side by side. The ACTIVE block is always visible and holds
// only the indicators that are currently on; the INACTIVE block holds all the
// others, collapsed to zero width inside a clip container that slides open on
// hover. The active block sits on the clock side, so a newly-activated
// indicator is unshifted onto the far side of it: appending would shove
// everything already showing sideways under the pointer.
//
// Every indicator is mounted twice — once in each block — and each copy is
// told which block it is in. The copy that does not belong there renders
// nothing and takes no width (see BarIndicator). That is upstream's design:
// it is what lets the active block keep a stable order while the inactive
// block keeps a fixed, config-ordered layout behind the reveal.
//
// Reveal sources, all debounced together by a 120 ms hide timer so crossing
// the gap between the container and a revealed icon does not close it:
//   * `alwaysShow: true` in this widget's inline shell.json entry,
//   * the pointer over the container or over one of its revealed icons,
//   * the pointer anywhere over the bar's center region (the bar holds that
//     one, since with nothing active this widget has no width to hover).
Item {
    id: root

    required property var theme
    required property var shell
    // The bar root, for the shared services the indicators need (dictation's
    // voxtype follower). Reached through the components below, so a service
    // is only created when its indicator actually mounts.
    required property var serviceHost
    property var bar: null
    property var settings: ({})

    // Upstream's default order. The notification bell is registered below
    // but not a default: it lives standalone on the bar's right edge
    // (shell.json), always visible as the history center's entry point —
    // add "notifs" to this widget's `items` to host it here instead.
    readonly property var defaultItems: ["screenrecording", "dictation", "reminder", "dnd", "stayawake"]

    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    // `items` selects (and orders) which indicators this instance shows;
    // omitted means all of them. Entries are ids, or {id, ...} objects whose
    // extra keys reach the indicator as its `settings`.
    readonly property var indicatorEntries: {
        const source = Array.isArray(setting("items", null)) && setting("items", []).length > 0 ? setting("items", []) : defaultItems;
        const result = [];
        for (let i = 0; i < source.length; i++) {
            const id = entryId(source[i]);
            if (id !== "")
                result.push(typeof source[i] === "string" ? ({
                        id: id
                    }) : source[i]);
        }
        return result;
    }
    readonly property var indicatorIds: indicatorEntries.map(e => String(e.id))

    readonly property bool alwaysShow: setting("alwaysShow", false) === true
    property bool areaHovered: false
    property bool itemHovered: false
    readonly property bool revealInactive: alwaysShow || areaHovered || itemHovered || (bar && bar.centerSectionRevealHeld === true && bar.centerHoverRevealSuppressed !== true)

    // Ids currently reported active, clock-side first.
    property var activeIds: []

    function entryId(entry) {
        if (typeof entry === "string")
            return entry;
        if (entry && typeof entry === "object" && entry.id !== undefined && entry.id !== null)
            return String(entry.id);
        return "";
    }

    function entryForId(id) {
        for (let i = 0; i < indicatorEntries.length; i++) {
            if (entryId(indicatorEntries[i]) === id)
                return indicatorEntries[i];
        }
        return ({
                id: id
            });
    }

    function hasIndicatorId(id) {
        return indicatorIds.indexOf(id) !== -1;
    }

    function setIndicatorAreaHovered(hovered) {
        areaHovered = hovered;
        if (hovered)
            hideTimer.stop();
        else
            hideTimer.restart();
    }

    function setIndicatorItemHovered(hovered) {
        if (hovered) {
            itemHovered = true;
            hideTimer.stop();
        } else {
            hideTimer.restart();
        }
    }

    // ------------------------------------------------- active block ordering
    function activeModelIndex(id) {
        for (let i = 0; i < activeModel.count; i++) {
            if (activeModel.get(i).activeId === id)
                return i;
        }
        return -1;
    }

    function syncActiveModel() {
        for (let i = activeModel.count - 1; i >= 0; i--) {
            if (activeIds.indexOf(activeModel.get(i).activeId) === -1)
                activeModel.remove(i);
        }
        for (let j = 0; j < activeIds.length; j++) {
            const id = activeIds[j];
            const index = activeModelIndex(id);
            if (index === -1)
                activeModel.insert(j, {
                    activeId: id
                });
            else if (index !== j)
                activeModel.move(index, j, 1);
        }
    }

    // Keep the ids we already show in their existing order, dropping any that
    // went inactive or left the config.
    function orderedActiveIds(states, preferredOrder) {
        const ids = [];
        for (let i = 0; i < preferredOrder.length; i++) {
            const id = preferredOrder[i];
            if (ids.indexOf(id) === -1 && hasIndicatorId(id) && states[id] === true)
                ids.push(id);
        }
        return ids;
    }

    property var activeStates: ({})

    function setIndicatorActive(id, active) {
        if (!id)
            return;
        const states = {};
        for (const key in activeStates) {
            if (activeStates[key] === true)
                states[key] = true;
        }
        if (active)
            states[id] = true;
        else
            delete states[id];
        activeStates = states;

        const ids = orderedActiveIds(states, activeIds);
        if (active && ids.indexOf(id) === -1 && hasIndicatorId(id))
            ids.unshift(id);
        activeIds = ids;
        syncActiveModel();
    }

    onIndicatorIdsChanged: {
        activeIds = orderedActiveIds(activeStates, activeIds);
        syncActiveModel();
    }

    // ---------------------------------------------------------------- layout
    readonly property bool vertical: bar ? bar.vertical === true : false
    readonly property int barSize: bar ? bar.barSize : theme.barHeight

    implicitWidth: bar && bar.vertical === true ? barSize : (layout.item ? layout.item.implicitWidth : 0)
    implicitHeight: bar && bar.vertical === true ? (layout.item ? layout.item.implicitHeight : 0) : barSize

    ListModel {
        id: activeModel
    }

    Timer {
        id: hideTimer
        interval: 120
        onTriggered: {
            if (!root.areaHovered)
                root.itemHovered = false;
        }
    }

    HoverHandler {
        onHoveredChanged: root.setIndicatorAreaHovered(hovered)
    }

    // Both blocks, laid out along the bar: side by side on a horizontal bar,
    // stacked on a vertical one (upstream keeps two arrangements too). Either
    // way the inactive block sits on the far side of the active one, so the
    // reveal grows away from the clock instead of shoving the lit indicators
    // out from under the pointer.
    Loader {
        id: layout

        anchors.fill: parent
        sourceComponent: root.vertical ? verticalIndicators : horizontalIndicators
    }

    Component {
        id: horizontalIndicators

        Row {
            spacing: 0

            Item {
                id: inactiveArea

                width: root.revealInactive ? inactiveRow.implicitWidth : 0
                height: root.height
                clip: true

                // Upstream's reveal snaps; ours slides, like our tray drawer.
                Behavior on width {
                    NumberAnimation {
                        duration: root.theme.time(1.2)
                        easing.type: root.theme.motion.easing
                    }
                }

                Row {
                    id: inactiveRow
                    // Slides in from the outer edge, so the icons closest to
                    // the active block arrive first.
                    x: inactiveArea.width - implicitWidth
                    height: parent.height
                    spacing: 0

                    Repeater {
                        model: root.indicatorIds
                        IndicatorSlot {
                            required property string modelData
                            indicatorId: modelData
                            indicatorBlock: "inactive"
                        }
                    }
                }

                HoverHandler {
                    onHoveredChanged: root.setIndicatorAreaHovered(hovered)
                }
            }

            Row {
                id: activeRow
                height: root.height
                spacing: 0

                Repeater {
                    model: activeModel
                    IndicatorSlot {
                        required property string activeId
                        indicatorId: activeId
                        indicatorBlock: "active"
                    }
                }
            }
        }
    }

    Component {
        id: verticalIndicators

        Column {
            spacing: 0

            Item {
                id: verticalInactiveArea

                width: root.barSize
                height: root.revealInactive ? verticalInactiveColumn.implicitHeight : 0
                clip: true

                Behavior on height {
                    NumberAnimation {
                        duration: root.theme.time(1.2)
                        easing.type: root.theme.motion.easing
                    }
                }

                Column {
                    id: verticalInactiveColumn
                    y: verticalInactiveArea.height - implicitHeight
                    width: parent.width
                    spacing: 0

                    Repeater {
                        model: root.indicatorIds
                        IndicatorSlot {
                            required property string modelData
                            indicatorId: modelData
                            indicatorBlock: "inactive"
                        }
                    }
                }

                HoverHandler {
                    onHoveredChanged: root.setIndicatorAreaHovered(hovered)
                }
            }

            Column {
                id: verticalActiveColumn
                width: root.barSize
                spacing: 0

                Repeater {
                    model: activeModel
                    IndicatorSlot {
                        required property string activeId
                        indicatorId: activeId
                        indicatorBlock: "active"
                    }
                }
            }
        }
    }

    // ------------------------------------------------------ indicator registry
    // Registered ids match the bar registry's, so every indicator stays usable
    // on its own (`"dnd"` in a bar array) as well as inside this container.
    readonly property var indicatorRegistry: ({
            "screenrecording": screenRecordingComponent,
            "dictation": dictationComponent,
            "notifs": notifsBellComponent,
            "dnd": dndComponent,
            "reminder": reminderComponent,
            "stayawake": stayAwakeComponent
        })

    // ------------------------------------------------ notification center
    // The center's panel hangs off this container, not off the bell copy
    // that opened it: the active-block copy is torn down the moment the
    // last unseen entry clears, which must not close an open panel.
    function openNotifsPanel(anchorBell) {
        if (notifsPanelLoader.status === Loader.Null)
            notifsPanelLoader.setSource("NotifsPanel.qml", {
                theme: root.theme,
                notifs: root.shell.notifs
            });
        notifsPanelLoader.item.anchorItem = anchorBell !== null && anchorBell !== undefined ? anchorBell : root;
        notifsPanelLoader.item.toggle();
    }

    // The IPC summon path (Bar.summonNotifCenter): the container anchors the
    // panel itself, so the center opens even with every indicator collapsed.
    function summonNotifCenter() {
        openNotifsPanel(null);
        return true;
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    PanelLoader {
        id: notifsPanelLoader
    }

    Component {
        id: screenRecordingComponent
        ScreenRecording {
            theme: root.theme
            bar: root.bar
            shell: root.shell
            indicatorHost: root
        }
    }

    Component {
        id: dictationComponent
        Dictation {
            theme: root.theme
            bar: root.bar
            dictation: root.serviceHost.dictationService()
            indicatorHost: root
        }
    }

    Component {
        id: notifsBellComponent
        NotifsBell {
            theme: root.theme
            bar: root.bar
            notifs: root.shell.notifs
            indicatorHost: root
        }
    }

    Component {
        id: dndComponent
        Dnd {
            theme: root.theme
            bar: root.bar
            notifs: root.shell.notifs
            indicatorHost: root
        }
    }

    Component {
        id: reminderComponent
        Reminder {
            theme: root.theme
            bar: root.bar
            shell: root.shell
            indicatorHost: root
        }
    }

    Component {
        id: stayAwakeComponent
        StayAwake {
            theme: root.theme
            bar: root.bar
            idle: root.shell.idle
            indicatorHost: root
        }
    }

    // One loader per indicator, per block (upstream's IndicatorLoader). The
    // block and the active-override are pushed in imperatively: they are
    // fixed for the life of a slot, and the reactive injections all live in
    // the components above.
    component IndicatorSlot: Item {
        id: slot

        property string indicatorId: ""
        property string indicatorBlock: "inactive"
        // Guards the active block against a copy that has not loaded its
        // state yet reporting itself inactive and removing its own row.
        property bool activeStateObserved: false

        readonly property var entry: root.entryForId(indicatorId)
        readonly property var known: root.indicatorRegistry[indicatorId]

        readonly property bool shown: source.item !== null && source.item.visible
        // Along the bar the slot is the indicator's own size and collapses
        // with it; across the bar it is the bar's thickness.
        implicitWidth: root.vertical ? root.barSize : (shown ? source.item.implicitWidth : 0)
        implicitHeight: root.vertical ? (shown ? source.item.implicitHeight : 0) : root.height
        width: implicitWidth
        height: implicitHeight

        function inject() {
            const target = source.item;
            if (!target)
                return;
            target.indicatorBlock = slot.indicatorBlock;
            target.activeOverride = slot.indicatorBlock === "active" ? true : null;
            if ("settings" in target)
                target.settings = slot.entry;
        }

        function syncActiveState() {
            const target = source.item;
            if (!target)
                return;
            const isActive = target.active === true;
            if (slot.indicatorBlock === "active") {
                if (isActive)
                    slot.activeStateObserved = true;
                else if (!slot.activeStateObserved)
                    return;
            }
            root.setIndicatorActive(slot.indicatorId, isActive);
        }

        onEntryChanged: inject()
        onIndicatorBlockChanged: inject()

        Loader {
            id: source
            anchors.fill: parent
            sourceComponent: slot.known !== undefined ? slot.known : null
            onLoaded: {
                slot.inject();
                slot.syncActiveState();
            }
            onStatusChanged: {
                if (status === Loader.Error)
                    console.warn("Indicators: failed to load indicator", slot.indicatorId);
            }
        }

        Connections {
            target: source.item
            ignoreUnknownSignals: true
            function onActiveChanged() {
                slot.syncActiveState();
            }
        }
    }
}
