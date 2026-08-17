import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Widgets
import "../../components"
import "MenuModel.js" as MenuModel
import "../../components/FilterKeys.js" as FilterKeys
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

    // The declared tree, plus the desktop-app rows merged into it (see
    // mergeAppRows) — so unlike `built` these are reassigned, not bound.
    readonly property var built: MenuModel.buildItems(MenuTree.TREE)
    property var items: built.items
    property var itemOrder: built.itemOrder

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
    // The ceiling on the rows region — omarchy's, and their reason: "a card
    // that swallows the whole screen reads as a page, not a menu". 64e20f8
    // raised theirs from 60% of the screen to 70%.
    //
    // Ours was a flat theme.space(110) = 440 px. That is 41% of this laptop's
    // 1066 and would be under a quarter of a 4K panel, so the root menu (9
    // rows, 428 px) already sat one row from clipping and a filtered list —
    // taller rows, frozen at the starting height — showed seven. A ceiling
    // belongs to the display, not to a number of pixels, so it follows the
    // surface, which is anchored to all four edges and therefore screen-sized.
    // The fallback only applies before the window reports a height.
    readonly property int maxListHeight: Math.round((menuSurface.height > 0 ? menuSurface.height : 1000) * 0.7)
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

    // ---------------------------------------------- dmenu modes + providers
    // Omarchy's generic picker/prompt: scripts summon the menu with a payload
    // {mode: "select"|"input", prompt, options[], selectionFile, doneFile}
    // (bin/menu-select / bin/menu-input build it) and poll for doneFile —
    // which this side GUARANTEES on every exit path, else the caller hangs.
    property var promptState: null

    // Provider rows (their runtime submenus): a tree entry carrying
    // `provider: "<name>"` runs the registry script on every entry —
    // volatile, so the ✓ tracks reality — and shows its label\tvalue\tcurrent
    // lines as action rows.
    readonly property var providers: ({
            "power-profiles": {
                script: "current=$(powerprofilesctl get 2>/dev/null); power-profile list 2>/dev/null | while read -r p; do [ -z \"$p\" ] && continue; printf '%s\\t%s\\t%s\\n' \"$p\" \"$p\" \"$current\"; done",
                icon: "󰐋",
                actionFor: function (value) {
                    return "power-profile autodetect " + "'" + String(value).replace(/'/g, "'\\''") + "'";
                }
            }
        })
    property var providerRows: null
    property string providerLabel: ""

    // `apps` names a provider too, but it is not one of those: only the
    // registry-backed names open the separate provider view.
    function isScriptProvider(entry) {
        return !!(entry && entry.provider && providers[entry.provider]);
    }

    // ------------------------------------------------------------ app rows
    // Omarchy's QML-native apps provider: the rows come from DesktopEntries
    // in-process and are merged into the tree as real children of `apps`, so
    // an installed application is ranked in search, carries its breadcrumb and
    // answers Backspace exactly like a declared row — where our old Apps entry
    // handed off to the launcher overlay and stranded you there.
    //
    // Bound, not read once: the first touch of DesktopEntries only STARTS the
    // .desktop scan, so an imperative read at open time sees an empty list and
    // the Apps card comes up empty. The binding also covers a rescan — an app
    // installed while the shell runs appears without a restart.
    readonly property var desktopApps: DesktopEntries.applications.values

    onDesktopAppsChanged: {
        mergeAppRows();
        if (opened)
            rebuildDisplay();
    }

    // Re-run on every open too, for the case where the scan finished before
    // this surface was ever loaded — then the change signal never fires here.
    function mergeAppRows() {
        const all = desktopApps || [];
        const rows = [];

        for (let i = 0; i < all.length; i++) {
            const app = all[i];
            const appId = String(app.id || "");
            if (!appId || app.noDisplay)
                continue;
            const subtext = String(app.genericName || app.comment || "");
            // .desktop Keywords are the "gimp for photoshop" half of a launcher
            // search; as aliases they feed the tree's own ranking.
            const aliases = subtext ? [subtext] : [];
            const keywords = app.keywords || [];
            for (let k = 0; k < keywords.length; k++)
                aliases.push(String(keywords[k]));
            rows.push({
                id: "apps." + appId,
                parent: "apps",
                kind: "app",
                icon: "",
                appIcon: String(app.icon || ""),
                appId: appId,
                label: String(app.name || appId),
                title: "",
                target: "",
                description: subtext,
                action: "",
                call: "",
                state: "",
                provider: "",
                aliases: aliases,
                when: "",
                checked: "",
                order: 0
            });
        }

        // DesktopEntries hands its values back in no particular order, and
        // reorders them when an application starts — the menu is alphabetical.
        rows.sort((a, b) => a.label.toLowerCase().localeCompare(b.label.toLowerCase()) || a.id.localeCompare(b.id));

        const merged = MenuModel.mergeAppRows(items, itemOrder, rows);
        items = merged.items;
        itemOrder = merged.itemOrder;
    }

    // Same path as the launcher: gtk-launch inside a transient
    // app-graphical.slice unit (bin/app-run) rather than the entry's own
    // execute(), which would make the app a child of qshell.service and put
    // the whole shell in systemd-oomd's kill pool with it.
    function launchApp(appId) {
        if (!appId)
            return;
        Quickshell.execDetached(["app-run", "gtk-launch", String(appId)]);
    }

    function promptOpen(payloadJson) {
        let p = null;
        try {
            p = JSON.parse(String(payloadJson || "{}"));
        } catch (e) {
            return;
        }
        if (!p || (p.mode !== "select" && p.mode !== "input") || !p.doneFile)
            return;
        const options = [];
        const raw = Array.isArray(p.options) ? p.options : [];
        for (let i = 0; i < raw.length; i++) {
            const s = String(raw[i]);
            const tab = s.indexOf("\t");
            options.push(tab >= 0 ? {
                icon: s.substring(0, tab),
                label: s.substring(tab + 1)
            } : {
                icon: "",
                label: s
            });
        }
        shellRoot.dismissBarPanels();
        promptState = {
            mode: p.mode,
            prompt: String(p.prompt || (p.mode === "input" ? "Input" : "Select")),
            options: options,
            selectionFile: String(p.selectionFile || ""),
            doneFile: String(p.doneFile)
        };
        providerRows = null;
        activeMenu = "root";
        navStack = [];
        filterText = "";
        selectedIndex = 0;
        frozenListHeight = -1;
        opened = true;
        rebuildDisplay();
    }

    function finalizePrompt(text) {
        if (!promptState)
            return;
        const state = promptState;
        promptState = null;
        // One bash sequence: the selection lands BEFORE the done marker, so
        // the polling caller never reads a half-written answer. Cancel
        // REMOVES the selection file — mktemp pre-creates it, and an empty
        // typed answer must stay distinguishable from a dismissal.
        if (text !== null && text !== undefined && state.selectionFile)
            Quickshell.execDetached(["bash", "-c", "printf '%s' \"$2\" > \"$1\"; touch \"$3\"", "qshell-menu-prompt", state.selectionFile, String(text), state.doneFile]);
        else
            Quickshell.execDetached(["bash", "-c", "rm -f \"$1\"; touch \"$2\"", "qshell-menu-prompt", state.selectionFile, state.doneFile]);
    }

    function openProvider(entry) {
        const def = providers[entry.provider];
        if (!def)
            return;
        freezeListHeight();
        providerLabel = entry.title || entry.label;
        providerRows = [];
        filterText = "";
        selectedIndex = 0;
        if (providerProc.running) {
            // Re-entered while the previous script is still collecting: the
            // command change would be ignored and the stale run's tail would
            // parse as THIS provider's rows. Kill the stale run and start
            // this entry cleanly once it has exited — same as guardProc.
            providerProc.pendingEntry = entry;
            providerProc.running = false;
            rebuildDisplay();
            return;
        }
        providerProc.icon = def.icon || entry.icon || "";
        providerProc.actionForName = entry.provider;
        providerProc.collected = "";
        providerProc.command = ["bash", "-lc", def.script];
        providerProc.running = true;
        rebuildDisplay();
    }

    Process {
        id: providerProc
        property string collected: ""
        property string icon: ""
        property string actionForName: ""
        property var pendingEntry: null
        stdout: SplitParser {
            onRead: data => providerProc.collected += data + "\n"
        }
        onExited: (exitCode, exitStatus) => {
            if (providerProc.pendingEntry) {
                // This exit is the kill from openProvider, not an answer:
                // discard the partial output and start the pending entry —
                // its per-provider state applies only now, with its own run.
                const entry = providerProc.pendingEntry;
                const pdef = menuRoot.providers[entry.provider];
                providerProc.pendingEntry = null;
                providerProc.icon = pdef.icon || entry.icon || "";
                providerProc.actionForName = entry.provider;
                providerProc.collected = "";
                providerProc.command = ["bash", "-lc", pdef.script];
                providerProc.running = true;
                return;
            }
            const def = menuRoot.providers[actionForName];
            if (!def || menuRoot.providerRows === null)
                return;
            // A script that failed has no complete answer: keep the empty
            // loading view rather than committing whatever half-list it
            // printed before dying (omarchy 3d033d1).
            if (exitCode !== 0 || exitStatus !== 0)
                return;
            const rows = [];
            const lines = collected.split("\n");
            for (let i = 0; i < lines.length; i++) {
                const parts = lines[i].split("\t");
                if (parts.length < 2 || !parts[0])
                    continue;
                rows.push({
                    label: parts[0],
                    value: parts[1],
                    current: parts.length > 2 && parts[1] === parts[2],
                    icon: icon,
                    action: def.actionFor(parts[1])
                });
            }
            menuRoot.providerRows = rows;
            if (menuRoot.opened)
                menuRoot.rebuildDisplay();
        }
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
        mergeAppRows();
        evaluateGuards();
        rebuildDisplay();
    }

    function hide() {
        // Every dismissal answers a pending prompt as cancelled — scrim
        // click, Escape, another overlay stealing the surface — or the
        // caller polls its done file forever.
        if (promptState)
            finalizePrompt(null);
        providerRows = null;
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
            // App rows are never routable: their aliases carry .desktop
            // Keywords and GenericName for search, so an installed application
            // could otherwise shadow a route (htop ships `Keywords=system;`).
            if (!entry || entry.kind === "app")
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
        if (isScriptProvider(entry)) {
            // Script-provider entries have no tree children — landing on them
            // as a plain submenu would show an empty card.
            show();
            openProvider(entry);
            return "ok";
        }
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
        if (promptState)
            return false; // Backspace/Left never leaves a prompt half-open
        if (providerRows !== null) {
            providerRows = null;
            filterText = "";
            selectedIndex = 0;
            rebuildDisplay();
            return true;
        }
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
        if (promptState && promptState.mode === "input") {
            finalizePrompt(filterText);
            hide();
            return;
        }
        if (index < 0 || index >= displayModel.count)
            return;
        const row = displayModel.get(index);
        if (row.kind === "prompt-option") {
            finalizePrompt(row.label);
            hide();
            return;
        }
        if (row.kind === "menu" || row.kind === "link") {
            const entry = entryFor(row.itemId);
            if (isScriptProvider(entry)) {
                openProvider(entry);
                return;
            }
            setActiveMenu(row.target || row.itemId, true);
            return;
        }
        if (row.kind === "app") {
            hide();
            launchApp(row.appId);
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

        // Prompt and provider views bypass the tree entirely: their rows are
        // synthesized in the displayRow shape the delegate already reads.
        if (promptState) {
            if (promptState.mode === "select") {
                const q = filterText.trim().toLowerCase();
                for (let p = 0; p < promptState.options.length; p++) {
                    const opt = promptState.options[p];
                    if (q && opt.label.toLowerCase().indexOf(q) < 0)
                        continue;
                    displayModel.append({
                        itemId: "prompt-" + p,
                        kind: "prompt-option",
                        icon: opt.icon,
                        appIcon: "",
                        appId: "",
                        label: opt.label,
                        target: "",
                        detail: "",
                        path: "",
                        childCount: 0,
                        action: "",
                        call: "",
                        score: 0,
                        section: ""
                    });
                }
            }
            if (selectedIndex >= displayModel.count)
                selectedIndex = Math.max(0, displayModel.count - 1);
            return;
        }
        if (providerRows !== null) {
            for (let v = 0; v < providerRows.length; v++) {
                const row = providerRows[v];
                displayModel.append({
                    itemId: "provider-" + v,
                    kind: "action",
                    icon: row.icon,
                    appIcon: "",
                    appId: "",
                    label: row.label + (row.current ? " ✓" : ""),
                    target: "",
                    detail: "",
                    path: "",
                    childCount: 0,
                    action: row.action,
                    call: "",
                    score: 0,
                    section: ""
                });
            }
            if (selectedIndex >= displayModel.count)
                selectedIndex = Math.max(0, displayModel.count - 1);
            return;
        }

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
        onExited: (exitCode, exitStatus) => {
            if (guardProc.pendingScript) {
                const script = guardProc.pendingScript;
                guardProc.pendingScript = "";
                guardProc.collected = "";
                guardProc.command = ["bash", "-lc", script];
                guardProc.running = true;
                return;
            }
            // A batch that died answered nothing: keep the previous answers
            // rather than un-hiding every row missing from a truncated set
            // (omarchy 3d033d1).
            if (exitCode !== 0 || exitStatus !== 0)
                return;
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

    OverlaySurface {
        id: menuSurface

        theme: menuRoot.theme
        opened: menuRoot.opened
        namespace: "qshell-menu"
        cardWidth: menuRoot.cardWidth
        cardHeight: menuRoot.cardMargin * 2 + menuRoot.headerHeight + menuRoot.theme.space(3) + menuRoot.listHeight
        onDismissed: menuRoot.hide()

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
                } else if (FilterKeys.printable(event)) {
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
                            if (menuRoot.promptState)
                                return menuRoot.promptState.prompt + "…";
                            if (menuRoot.providerRows !== null)
                                return menuRoot.providerLabel + "…";
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

                        delegate: CursorSurface {
                            id: row

                            required property int index
                            required property string kind
                            required property string icon
                            required property string appIcon
                            required property string label
                            required property string detail

                            readonly property bool isSubmenu: row.kind === "menu" || row.kind === "link"
                            readonly property bool isApp: row.kind === "app"

                            theme: menuRoot.theme
                            width: list.width
                            height: menuRoot.rowHeight
                            // Hovering moves the selection, so the cursor and
                            // the choice are one state and the fill says it.
                            bordered: false
                            current: row.index === menuRoot.selectedIndex

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

                            Item {
                                id: glyph
                                anchors.left: parent.left
                                anchors.leftMargin: menuRoot.theme.space(2)
                                anchors.verticalCenter: parent.verticalCenter
                                width: menuRoot.theme.space(9)
                                height: parent.height

                                Text {
                                    anchors.centerIn: parent
                                    visible: !row.isApp
                                    text: row.icon
                                    color: menuRoot.theme.textPrimary
                                    font.family: "Symbols Nerd Font"
                                    font.pixelSize: menuRoot.theme.fontPx(1.333)
                                }

                                // App rows carry a themed icon name, not a
                                // glyph — same source the launcher uses.
                                IconImage {
                                    anchors.centerIn: parent
                                    visible: row.isApp
                                    implicitSize: menuRoot.theme.space(6)
                                    source: row.isApp ? Quickshell.iconPath(row.appIcon, "application-x-executable") : ""
                                }
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
