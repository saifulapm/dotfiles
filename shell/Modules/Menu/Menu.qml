import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "MenuModel.js" as MenuModel
import "MenuTree.js" as MenuTree

// Command menu: one hierarchical tree of everything the desktop can do,
// centered over a scrim in the launcher's visual language. Framework ported
// from omarchy's menu plugin (CREDITS.md) — submenus by dotted id, type to
// filter the WHOLE tree by label/id/aliases with their ranking, `when` guards
// batched into a single bash run, ✓ on checked rows. The tree itself is ours,
// in MenuTree.js.
//
// LazyLoader-gated — nothing here exists until first summoned via IPC.
Scope {
    id: menuRoot

    required property var theme
    required property var shellRoot

    property bool opened: false
    property string activeMenu: "root"
    property string filterText: ""
    property int selectedIndex: 0
    property var navStack: []

    readonly property var built: MenuModel.buildItems(MenuTree.TREE)
    readonly property var items: built.items
    readonly property var itemOrder: built.itemOrder

    // id → true|false. `when` and `checked` are shell tests, evaluated in one
    // batched bash run per open; `state` rows resolve in-process instead.
    property var whenResults: ({})
    property var shellChecked: ({})
    property var checkedResults: ({})

    // ------------------------------------------------------------ geometry
    readonly property int cardWidth: theme.space(120)
    readonly property int rowSpacing: theme.space(1)
    readonly property int rowHeight: filterText ? theme.space(14) : theme.space(11)
    readonly property int dividerHeight: theme.space(5)
    readonly property int headerHeight: theme.space(10)
    readonly property int cardMargin: theme.space(4)
    readonly property int maxListHeight: theme.space(110)
    // The starting menu sets the height ceiling: the first submenu move or
    // search keystroke freezes it, so drilling into a longer menu (or the
    // taller filtered rows) scrolls behind the fold instead of growing the
    // card — omarchy's cap-at-the-starting-menu rule.
    property int frozenListHeight: -1
    // Rows are uniform (the detail line is shown on all of them or none), so
    // the card can size itself without measuring the delegates.
    readonly property int listHeight: {
        const count = Math.max(1, displayModel.count);
        const divider = searchDivider ? dividerHeight + rowSpacing : 0;
        const cap = frozenListHeight >= 0 ? Math.min(maxListHeight, frozenListHeight) : maxListHeight;
        return Math.min(cap, count * rowHeight + (count - 1) * rowSpacing + divider);
    }
    property bool searchDivider: false

    function freezeListHeight() {
        if (opened && frozenListHeight < 0)
            frozenListHeight = listHeight;
    }

    function entryFor(id) {
        return MenuModel.item(items, id);
    }

    function isVisible(entry) {
        return MenuModel.isVisible(items, itemOrder, whenResults, entry);
    }

    // ---------------------------------------------------------- open/close
    function show() {
        activeMenu = "root";
        navStack = [];
        filterText = "";
        selectedIndex = 0;
        frozenListHeight = -1;
        opened = true;
        evaluateGuards();
        rebuildDisplay();
    }

    function hide() {
        opened = false;
        filterText = "";
        frozenListHeight = -1;
    }

    function toggle() {
        if (opened)
            hide();
        else
            show();
    }

    // Callers may pass an id ("system", "capture.region") or any alias
    // declared in the tree ("power", "screenshot"). An alias that lands on a
    // leaf runs it outright instead of opening a menu with no children —
    // omarchy's openRoute.
    function resolveRoute(input) {
        const raw = String(input || "").toLowerCase().replace(/_/g, "-");
        if (!raw || raw === "go" || raw === "menu" || raw === "root")
            return "root";
        // An exact id beats any alias (omarchy 0269fe0): an entry declared
        // earlier must never capture a later entry's id through its aliases
        // (capture.annotate's "clipboard" alias vs the clipboard picker).
        if (entryFor(raw))
            return raw;
        for (let i = 0; i < itemOrder.length; i++) {
            const entry = entryFor(itemOrder[i]);
            if (!entry)
                continue;
            for (let j = 0; j < entry.aliases.length; j++) {
                if (String(entry.aliases[j]).toLowerCase().replace(/_/g, "-") === raw)
                    return entry.id;
            }
        }
        return raw;
    }

    function openRoute(route) {
        let id = resolveRoute(route);
        const entry = entryFor(id);
        if (entry && entry.kind === "action") {
            hide();
            runRow(entry.call, entry.action);
            return "ok";
        }
        if (entry && entry.kind === "link" && entry.target)
            id = entry.target;
        show();
        if (entryFor(id) && id !== activeMenu) {
            // A routed open lands directly on this menu: it IS the starting
            // menu, so assign it without freezing the height at root's.
            activeMenu = id;
            rebuildDisplay();
        }
        return "ok";
    }

    // ------------------------------------------------------------- actions
    function runAction(command) {
        if (!command)
            return;
        Quickshell.execDetached(["bash", "-lc", String(command)]);
    }

    // Rows the shell itself owns: no subprocess, no `qs ipc` round trip.
    function runCall(name) {
        switch (name) {
        case "launcher":
            shellRoot.toggleLauncher();
            break;
        case "themes":
            shellRoot.toggleThemes();
            break;
        case "wallpaper":
            shellRoot.toggleWallpaper();
            break;
        case "emojis":
            shellRoot.toggleEmojis();
            break;
        case "clipboard":
            shellRoot.toggleClipboard();
            break;
        case "reminders":
            shellRoot.toggleReminders();
            break;
        case "lock":
            shellRoot.lockSession();
            break;
        case "dnd":
            shellRoot.notifs.dnd = !shellRoot.notifs.dnd;
            break;
        case "nightlight":
            shellRoot.nightlight.toggle();
            break;
        case "blur":
            shellRoot.blur.toggle();
            break;
        default:
            console.warn("Menu: unknown call:", name);
        }
    }

    // In-shell equivalents of omarchy's `checked` shell tests.
    function stateValue(name) {
        switch (name) {
        case "dnd":
            return !!shellRoot.notifs.dnd;
        case "nightlight":
            return !!shellRoot.nightlight.enabled;
        case "blur":
            return !!shellRoot.blur.enabled;
        default:
            return false;
        }
    }

    function runRow(call, action) {
        if (call)
            runCall(call);
        else
            runAction(action);
    }

    // ---------------------------------------------------------- navigation
    function setActiveMenu(id, pushHistory) {
        freezeListHeight();
        if (!entryFor(id))
            id = "root";
        if (pushHistory && id !== activeMenu)
            navStack = navStack.concat([activeMenu]);
        activeMenu = id;
        filterText = "";
        selectedIndex = 0;
        rebuildDisplay();
    }

    function goBack() {
        if (activeMenu === "root")
            return false;

        if (navStack.length > 0) {
            const previous = navStack[navStack.length - 1];
            navStack = navStack.slice(0, navStack.length - 1);
            setActiveMenu(previous, false);
            return true;
        }

        const active = entryFor(activeMenu);
        setActiveMenu(active && active.parent ? active.parent : "root", false);
        return true;
    }

    function setFilter(next) {
        freezeListHeight();
        filterText = next;
        selectedIndex = 0;
        rebuildDisplay();
    }

    function select(delta) {
        const count = displayModel.count;
        if (count === 0)
            return;
        selectedIndex = (selectedIndex + delta + count) % count;
        list.positionViewAtIndex(selectedIndex, ListView.Contain);
    }

    function activateIndex(index) {
        if (index < 0 || index >= displayModel.count)
            return;
        const row = displayModel.get(index);
        if (row.kind === "menu" || row.kind === "link") {
            setActiveMenu(row.target || row.itemId, true);
            return;
        }
        hide();
        runRow(row.call, row.action);
    }

    // ------------------------------------------------------------- display
    ListModel {
        id: displayModel
    }

    function rebuildDisplay() {
        const checked = {};
        for (const key in shellChecked)
            checked[key] = shellChecked[key];
        for (let s = 0; s < itemOrder.length; s++) {
            const stateEntry = entryFor(itemOrder[s]);
            if (stateEntry && stateEntry.state)
                checked[stateEntry.id] = stateValue(stateEntry.state);
        }
        checkedResults = checked;

        displayModel.clear();
        searchDivider = false;

        const active = entryFor(activeMenu) ? activeMenu : "root";
        activeMenu = active;
        const query = filterText.trim();
        let rows = [];

        if (query) {
            // Search covers the whole subtree below the current menu (the
            // whole tree at root). Rows that live here come first; everything
            // found deeper follows under a divider, each carrying the
            // breadcrumb of where it actually lives.
            const currentRows = [];
            const drilldownRows = [];

            for (let i = 0; i < itemOrder.length; i++) {
                const entry = entryFor(itemOrder[i]);
                if (!entry || entry.id === "root")
                    continue;
                if (!MenuModel.isDescendantOf(items, entry.id, active))
                    continue;
                if (!MenuModel.matchesQuery(entry, query, isVisible(entry)))
                    continue;

                const detail = MenuModel.parentPathFor(items, entry.id);
                const row = MenuModel.displayRow(items, itemOrder, checkedResults, entry, detail, MenuModel.searchScore(items, entry, query));
                if (entry.parent === active)
                    currentRows.push(row);
                else
                    drilldownRows.push(row);
            }

            const searchSort = (a, b) => a.score !== b.score ? a.score - b.score : a.path.localeCompare(b.path);
            currentRows.sort(searchSort);
            drilldownRows.sort(searchSort);
            searchDivider = currentRows.length > 0 && drilldownRows.length > 0;
            if (searchDivider) {
                for (let d = 0; d < drilldownRows.length; d++)
                    drilldownRows[d].section = "drilldown";
            }
            rows = currentRows.concat(drilldownRows);
        } else {
            for (let j = 0; j < itemOrder.length; j++) {
                const child = entryFor(itemOrder[j]);
                if (!child || child.parent !== active)
                    continue;
                if (!isVisible(child))
                    continue;
                rows.push(MenuModel.displayRow(items, itemOrder, checkedResults, child, child.description, child.order));
            }
        }

        for (let k = 0; k < rows.length; k++)
            displayModel.append(rows[k]);

        if (displayModel.count === 0)
            selectedIndex = 0;
        else if (selectedIndex >= displayModel.count)
            selectedIndex = displayModel.count - 1;
        else if (selectedIndex < 0)
            selectedIndex = 0;
    }

    // -------------------------------------------------------------- guards
    // One bash run for every `when`/`checked` test in the tree, on open —
    // omarchy's batched guard evaluation. Nothing waits on it: the menu draws
    // with the previous answers and refreshes when the batch lands.
    function evaluateGuards() {
        let script = "";
        for (let i = 0; i < itemOrder.length; i++) {
            const entry = entryFor(itemOrder[i]);
            if (!entry)
                continue;
            if (entry.when)
                script += "if { " + entry.when + "; } >/dev/null 2>&1; then echo " + entry.id + ":w:1; else echo " + entry.id + ":w:0; fi\n";
            if (entry.checked)
                script += "if { " + entry.checked + "; } >/dev/null 2>&1; then echo " + entry.id + ":c:1; else echo " + entry.id + ":c:0; fi\n";
        }
        if (!script) {
            whenResults = ({});
            shellChecked = ({});
            return;
        }
        if (guardProc.running) {
            // Reopened while the previous batch is still collecting: wiping
            // `collected` under the live SplitParser would make onExited
            // commit a truncated tail as the guard answers. Kill the stale
            // run and start this script cleanly once it has exited.
            guardProc.pendingScript = script;
            guardProc.running = false;
            return;
        }
        guardProc.collected = "";
        guardProc.command = ["bash", "-lc", script];
        guardProc.running = true;
    }

    Process {
        id: guardProc
        property string collected: ""
        property string pendingScript: ""
        stdout: SplitParser {
            onRead: data => guardProc.collected += data + "\n"
        }
        onExited: {
            if (guardProc.pendingScript) {
                const script = guardProc.pendingScript;
                guardProc.pendingScript = "";
                guardProc.collected = "";
                guardProc.command = ["bash", "-lc", script];
                guardProc.running = true;
                return;
            }
            const nextWhen = {};
            const nextChecked = {};
            const lines = guardProc.collected.split("\n");
            for (let i = 0; i < lines.length; i++) {
                const line = lines[i].trim();
                if (!line)
                    continue;
                const colon = line.lastIndexOf(":");
                if (colon < 0)
                    continue;
                const value = line.substring(colon + 1) === "1";
                const rest = line.substring(0, colon);
                const tagAt = rest.lastIndexOf(":");
                if (tagAt < 0)
                    continue;
                const id = rest.substring(0, tagAt);
                const tag = rest.substring(tagAt + 1);
                if (tag === "w")
                    nextWhen[id] = value;
                else if (tag === "c")
                    nextChecked[id] = value;
            }
            menuRoot.whenResults = nextWhen;
            menuRoot.shellChecked = nextChecked;
            if (menuRoot.opened)
                menuRoot.rebuildDisplay();
        }
    }

    PanelWindow {
        visible: menuRoot.opened
        anchors {
            top: true
            bottom: true
            left: true
            right: true
        }
        exclusionMode: ExclusionMode.Ignore
        color: "transparent"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.namespace: "qshell-menu"
        WlrLayershell.keyboardFocus: menuRoot.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

        // Card-shaped compositor blur behind the glass fill; the scrim
        // around it stays a plain dim (see BarPanel.qml).
        BackgroundEffect.blurRegion: menuRoot.theme.blurActive && menuRoot.opened ? cardBlurRegion : null

        Region {
            id: cardBlurRegion
            item: card
            radius: card.radius
        }

        Rectangle {
            anchors.fill: parent
            color: menuRoot.theme.alpha(menuRoot.theme.surface0, 0.5)

            MouseArea {
                anchors.fill: parent
                onClicked: menuRoot.hide()
            }
        }

        Rectangle {
            id: card
            anchors.centerIn: parent
            width: menuRoot.cardWidth
            height: menuRoot.cardMargin * 2 + menuRoot.headerHeight + menuRoot.theme.space(3) + menuRoot.listHeight
            radius: menuRoot.theme.radius(1.5)
            color: menuRoot.theme.glass(menuRoot.theme.surface1)
            border.width: menuRoot.theme.borderWidth
            border.color: menuRoot.theme.surface3

            opacity: menuRoot.opened ? 1 : 0
            scale: menuRoot.opened ? 1 : 0.96
            Behavior on opacity {
                NumberAnimation {
                    duration: menuRoot.theme.time(0.8)
                    easing.type: menuRoot.theme.easing
                }
            }
            Behavior on scale {
                NumberAnimation {
                    duration: menuRoot.theme.time(0.8)
                    easing.type: menuRoot.theme.easing
                }
            }

            MouseArea {
                // Swallow clicks so they don't fall through to the scrim.
                anchors.fill: parent
            }

            Item {
                id: keyCatcher
                anchors.fill: parent
                focus: true

                // Type-to-filter owns the keyboard, so j/k only navigate while
                // the query is empty (or with Ctrl held) — otherwise they are
                // just letters, like every other printable key.
                Keys.onPressed: event => {
                    const ctrl = (event.modifiers & Qt.ControlModifier) !== 0;
                    const vimNav = (event.key === Qt.Key_J || event.key === Qt.Key_K) && (ctrl || menuRoot.filterText === "");

                    if (event.key === Qt.Key_Escape) {
                        if (menuRoot.filterText)
                            menuRoot.setFilter("");
                        else if (!menuRoot.goBack())
                            menuRoot.hide();
                    } else if (event.key === Qt.Key_Backspace) {
                        if (menuRoot.filterText)
                            menuRoot.setFilter(menuRoot.filterText.slice(0, -1));
                        else
                            menuRoot.goBack();
                    } else if (vimNav) {
                        menuRoot.select(event.key === Qt.Key_J ? 1 : -1);
                    } else if (event.key === Qt.Key_Down) {
                        menuRoot.select(1);
                    } else if (event.key === Qt.Key_Up) {
                        menuRoot.select(-1);
                    } else if (event.key === Qt.Key_PageDown) {
                        menuRoot.select(6);
                    } else if (event.key === Qt.Key_PageUp) {
                        menuRoot.select(-6);
                    } else if (event.key === Qt.Key_Left) {
                        menuRoot.goBack();
                    } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Right) {
                        menuRoot.activateIndex(menuRoot.selectedIndex);
                    } else if (event.text && event.text.length === 1 && event.text.charCodeAt(0) >= 32 && event.text.charCodeAt(0) !== 127 && (event.modifiers === Qt.NoModifier || event.modifiers === Qt.ShiftModifier)) {
                        menuRoot.setFilter(menuRoot.filterText + event.text);
                    } else {
                        return;
                    }
                    event.accepted = true;
                }

                Column {
                    anchors.fill: parent
                    anchors.margins: menuRoot.cardMargin
                    spacing: menuRoot.theme.space(3)

                    // Header doubles as the query line: the current menu's
                    // title until you type, then what you typed.
                    Item {
                        width: parent.width
                        height: menuRoot.headerHeight

                        Text {
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                            text: {
                                if (menuRoot.filterText)
                                    return menuRoot.filterText;
                                const entry = menuRoot.entryFor(menuRoot.activeMenu);
                                return (entry ? entry.title || entry.label : "Go") + "…";
                            }
                            color: menuRoot.theme.textPrimary
                            opacity: menuRoot.filterText ? 1 : 0.58
                            font.family: menuRoot.theme.fontUi
                            font.pixelSize: menuRoot.theme.fontPx(1.167)
                            font.weight: Font.DemiBold
                        }
                    }

                    Item {
                        width: parent.width
                        height: menuRoot.listHeight

                        ListView {
                            id: list
                            anchors.fill: parent
                            clip: true
                            model: displayModel
                            spacing: menuRoot.rowSpacing
                            currentIndex: menuRoot.selectedIndex
                            boundsBehavior: Flickable.StopAtBounds

                            section.property: "section"
                            section.criteria: ViewSection.FullString
                            section.delegate: Item {
                                required property string section

                                width: ListView.view.width
                                height: section === "drilldown" ? menuRoot.dividerHeight : 0
                                visible: section === "drilldown"

                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    height: menuRoot.theme.borderWidth
                                    color: menuRoot.theme.alpha(menuRoot.theme.textPrimary, 0.2)
                                }
                            }

                            delegate: Rectangle {
                                id: row

                                required property int index
                                required property string kind
                                required property string icon
                                required property string label
                                required property string detail

                                readonly property bool hasCursor: row.index === menuRoot.selectedIndex
                                readonly property bool isSubmenu: row.kind === "menu" || row.kind === "link"

                                width: list.width
                                height: menuRoot.rowHeight
                                radius: menuRoot.theme.radius(0.75)
                                color: row.hasCursor ? menuRoot.theme.alpha(menuRoot.theme.accent, 0.18) : "transparent"

                                MouseArea {
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onEntered: menuRoot.selectedIndex = row.index
                                    onClicked: {
                                        menuRoot.selectedIndex = row.index;
                                        menuRoot.activateIndex(row.index);
                                    }
                                }

                                Text {
                                    id: glyph
                                    anchors.left: parent.left
                                    anchors.leftMargin: menuRoot.theme.space(2)
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: menuRoot.theme.space(9)
                                    horizontalAlignment: Text.AlignHCenter
                                    text: row.icon
                                    color: menuRoot.theme.textPrimary
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: menuRoot.theme.fontPx(1.333)
                                }

                                Column {
                                    anchors.left: glyph.right
                                    anchors.leftMargin: menuRoot.theme.space(2)
                                    anchors.right: chevron.left
                                    anchors.rightMargin: menuRoot.theme.space(2)
                                    anchors.verticalCenter: parent.verticalCenter
                                    spacing: menuRoot.theme.space(0.5)

                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        text: row.label
                                        color: menuRoot.theme.textPrimary
                                        font.family: menuRoot.theme.fontUi
                                        font.pixelSize: menuRoot.theme.fontPx(1.0)
                                    }

                                    // While filtering, the second line says
                                    // where the row actually lives.
                                    Text {
                                        width: parent.width
                                        elide: Text.ElideRight
                                        visible: menuRoot.filterText !== "" && row.detail !== ""
                                        text: row.detail
                                        color: menuRoot.theme.textMuted
                                        font.family: menuRoot.theme.fontUi
                                        font.pixelSize: menuRoot.theme.fontPx(0.833)
                                    }
                                }

                                Text {
                                    id: chevron
                                    anchors.right: parent.right
                                    anchors.rightMargin: menuRoot.theme.space(3)
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: row.isSubmenu ? "›" : ""
                                    opacity: 0.45
                                    color: menuRoot.theme.textPrimary
                                    font.family: menuRoot.theme.fontUi
                                    font.pixelSize: menuRoot.theme.fontPx(1.333)
                                }
                            }
                        }

                        Text {
                            anchors.centerIn: parent
                            visible: displayModel.count === 0
                            horizontalAlignment: Text.AlignHCenter
                            text: menuRoot.filterText ? "No matches for “" + menuRoot.filterText + "”" : "Nothing here yet"
                            color: menuRoot.theme.textMuted
                            font.family: menuRoot.theme.fontUi
                            font.pixelSize: menuRoot.theme.fontPx(1.0)
                        }
                    }
                }
            }
        }
    }
}
