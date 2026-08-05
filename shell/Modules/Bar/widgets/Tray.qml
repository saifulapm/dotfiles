import QtQuick
import Quickshell
import Quickshell.Services.SystemTray
import "../components"
import "TrayModel.js" as TrayModel

// StatusNotifier tray, ported from omarchy's tray widget (CREDITS.md).
//
// Items fall into three buckets: pinned ones always sit on the bar, hidden
// ones never show, everything else lives in a drawer that stays collapsed
// behind a chevron and slides open (600 ms OutCubic, Waybar's tray-expander
// timing) while the pointer is over the tray. Right-clicking the chevron
// opens the manage card, whose Pin / Hide toggles persist the two id lists
// into this widget's inline shell.json entry.
//
// Per item: left click activates (or opens the menu for menu-only items),
// right click opens the menu, middle click secondary-activates, the wheel
// scrolls. Passive items are hidden from the bar but stay listed in the
// manage card.
Item {
    id: rootItem

    required property var theme
    property var bar: null
    property var settings: ({})

    readonly property string widgetId: settings && settings.id ? String(settings.id) : "tray"
    readonly property color barForeground: bar ? bar.barForeground : theme.textPrimary

    readonly property var pinnedIds: settings && Array.isArray(settings.pinned) ? settings.pinned : []
    readonly property var hiddenIds: settings && Array.isArray(settings.hidden) ? settings.hidden : []

    // An app the bar already carries a dedicated widget for keeps its status
    // out of the tray — otherwise Dropbox sits on the bar twice, once as its
    // own widget and once as an SNI item. Omarchy's TrayModel rule, and like
    // theirs it is keyed on the live layout: drop "dropbox" from the layout
    // and its own tray item comes straight back.
    function ownedByDedicatedWidget(item) {
        const layout = bar && bar.layoutConfig ? bar.layoutConfig : null;
        return TrayModel.ownedByDedicatedWidget(item, layout);
    }

    // Everything the tray knows about, for the manage card.
    readonly property var manageItems: SystemTray.items.values.filter(i => !rootItem.ownedByDedicatedWidget(i))
    // Passive items are idle-by-declaration and never reach the bar.
    readonly property var allItems: manageItems.filter(i => i.status !== Status.Passive)
    readonly property var pinnedItems: allItems.filter(i => rootItem.classify(i) === "pinned")
    readonly property var drawerItems: allItems.filter(i => rootItem.classify(i) === "drawer")

    readonly property int trayItemExtent: 27
    readonly property int drawerCount: drawerItems.length
    readonly property int drawerExtent: drawerCount * trayItemExtent
    // The drawer block reserves its full slide-in width at all times; the
    // chevron rides the reveal from its outer end inward.
    readonly property int drawerBlockWidth: allItems.length > 0 ? trayItemExtent + drawerExtent : 0

    property bool expanded: false
    property real revealProgress: expanded ? 1 : 0
    readonly property real revealExtent: drawerExtent * revealProgress

    Behavior on revealProgress {
        NumberAnimation {
            duration: 600
            easing.type: Easing.OutCubic
        }
    }

    function classify(item) {
        const iid = String(item.id || "");
        if (hiddenIds.indexOf(iid) !== -1)
            return "hidden";
        if (pinnedIds.indexOf(iid) !== -1)
            return "pinned";
        return "drawer";
    }

    function trayTooltip(item) {
        return item.tooltipTitle || item.title || item.id || "";
    }

    // Best human-readable name: title, else tooltip, else the trailing
    // segment of the bus id.
    function displayName(item) {
        const title = String(item.title || "").trim();
        if (title !== "")
            return title;
        const tooltip = String(item.tooltipTitle || "").trim();
        if (tooltip !== "")
            return tooltip;
        const iid = String(item.id || "");
        const slash = iid.lastIndexOf("/");
        return slash !== -1 ? iid.substring(slash + 1) : (iid || "Unknown");
    }

    function persistTrayState(pinned, hidden) {
        if (!bar || !bar.shell || typeof bar.shell.updateEntryInline !== "function")
            return;
        bar.shell.updateEntryInline(widgetId, {
            id: widgetId,
            pinned: pinned,
            hidden: hidden
        });
    }

    // Pinning and hiding are mutually exclusive: taking one sheds the other.
    function togglePin(iid) {
        const pinned = pinnedIds.slice();
        const hidden = hiddenIds.slice();
        const idx = pinned.indexOf(iid);
        if (idx !== -1) {
            pinned.splice(idx, 1);
        } else {
            pinned.push(iid);
            const hi = hidden.indexOf(iid);
            if (hi !== -1)
                hidden.splice(hi, 1);
        }
        persistTrayState(pinned, hidden);
    }

    function toggleHide(iid) {
        const pinned = pinnedIds.slice();
        const hidden = hiddenIds.slice();
        const idx = hidden.indexOf(iid);
        if (idx !== -1) {
            hidden.splice(idx, 1);
        } else {
            hidden.push(iid);
            const pi = pinned.indexOf(iid);
            if (pi !== -1)
                pinned.splice(pi, 1);
        }
        persistTrayState(pinned, hidden);
    }

    function openPanel() {
        panelLoader.active = true;
        panelLoader.item.anchorItem = expandIcon;
        panelLoader.item.toggle();
    }

    implicitWidth: drawerBlockWidth + pinnedRow.implicitWidth
    implicitHeight: parent ? parent.height : trayItemExtent
    // Stays mounted while only hidden items remain, so the chevron — and with
    // it the manage card — cannot be locked away by hiding everything.
    visible: allItems.length > 0

    Item {
        id: drawerArea

        x: 0
        width: rootItem.drawerBlockWidth
        height: rootItem.height
        visible: rootItem.allItems.length > 0

        // The collapsed drawer keeps its slide-in space reserved, and that
        // space is empty: mask it out so drifting past the tray neither pops
        // the drawer open nor swallows a click meant for what's underneath.
        // Omarchy's containmentMask, moved down onto the hovered item — a
        // pointer handler tests its own parent's containment, and a mask on an
        // ancestor does not gate the handlers nested below it.
        containmentMask: QtObject {
            function contains(point: point): bool {
                if (point.y < 0 || point.y > drawerArea.height)
                    return false;
                return point.x >= rootItem.drawerExtent - rootItem.revealExtent && point.x <= drawerArea.width;
            }
        }

        HoverHandler {
            onHoveredChanged: rootItem.expanded = hovered
        }

        BarIcon {
            id: expandIcon

            theme: rootItem.theme
            bar: rootItem.bar
            // MD chevron-left: the drawer opens leftward, away from the bar
            // edge. (Omarchy's FontAwesome chevron has no glyph in our
            // Symbols Nerd Font fallback.)
            glyph: "󰅁"
            tooltipText: "Tray — right-click to manage"
            x: rootItem.drawerExtent - rootItem.revealExtent

            onTapped: button => {
                if (button === Qt.RightButton)
                    rootItem.openPanel();
            }
        }

        Item {
            id: trayClip

            x: rootItem.trayItemExtent
            width: rootItem.drawerExtent
            height: rootItem.height
            clip: true

            Row {
                id: trayIcons

                x: rootItem.drawerExtent - rootItem.revealExtent
                height: parent.height
                spacing: 0
                layer.enabled: true

                Repeater {
                    model: rootItem.drawerItems
                    TrayItem {}
                }
            }
        }
    }

    Row {
        id: pinnedRow

        x: rootItem.drawerBlockWidth
        height: rootItem.height
        spacing: 0

        Repeater {
            model: rootItem.pinnedItems
            TrayItem {}
        }
    }

    LazyLoader {
        id: panelLoader

        active: false

        component: TrayPanel {
            theme: rootItem.theme
            tray: rootItem
        }
    }

    component TrayItem: BarButton {
        id: trayItemRoot

        required property var modelData

        theme: rootItem.theme
        bar: rootItem.bar
        fixedWidth: rootItem.trayItemExtent
        tooltipText: rootItem.trayTooltip(modelData)
        visible: modelData.status !== Status.Passive

        function displayMenu() {
            if (!modelData.hasMenu || !rootItem.bar)
                return;
            const point = trayItemRoot.mapToItem(rootItem.bar.contentItem, 0, trayItemRoot.height);
            modelData.display(rootItem.bar, Math.round(point.x), Math.round(point.y));
        }

        onTapped: button => {
            if (button === Qt.LeftButton) {
                if (modelData.onlyMenu)
                    trayItemRoot.displayMenu();
                else
                    modelData.activate();
            } else if (button === Qt.MiddleButton) {
                modelData.secondaryActivate();
            } else if (button === Qt.RightButton) {
                trayItemRoot.displayMenu();
            }
        }

        onWheelMoved: delta => modelData.scroll(delta, false)

        TrayIcon {
            width: 12
            height: 12
            icon: trayItemRoot.modelData.icon
            tint: rootItem.barForeground
        }
    }
}
