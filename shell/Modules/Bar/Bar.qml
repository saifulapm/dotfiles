import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "widgets"
import "BarModel.js" as BarModel

// The bar, styled 100% after omarchy's: theme background surface, foreground
// text (colors.toml `foreground`, i.e. our ansi.white — not bright), zero
// spacing between widgets (each owns its margins), 8 px section insets,
// chrome-less buttons, red attention color, 420 ms color transitions on
// theme swap, and a configurable center anchor pinned dead-center.
//
// The interaction machinery below is omarchy's too (CREDITS.md): press-drag a
// widget to reorder it, press-drag the empty center to move the bar to any of
// the four screen edges, double-click it to toggle transparency (with an
// auto-contrast foreground sampled from the wallpaper behind the bar), an
// accent pill under the widget whose panel is open, and Tab to walk between
// panels.
//
// `bar.position` of "left" or "right" turns the whole thing on its side: the
// sections stack, each widget is a bar-thickness cell, the clock becomes a
// stack of short lines, and panels open beside the bar. Section names stay as
// they are — on a vertical bar "left" is the top end and "right" the bottom —
// so moving the bar never rewrites the layout.
//
// Widgets live in the registry below and are instantiated only when named in
// the config's bar.left / bar.center / bar.right arrays. Unknown ids render
// an error chip instead of silently vanishing.
Scope {
    id: barRoot

    required property var shell
    required property var theme
    required property var niri
    property var config: ({})

    readonly property string statePath: Quickshell.env("HOME") + "/.local/state/qshell"
    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin/"

    // Layout entries are either plain widget-id strings ("clock") or inline
    // settings objects ({"id": "clock", "format": …}), omarchy-style. Both
    // normalize to objects here; the entry reaches its widget as `settings`.
    function normalizeEntry(entry) {
        if (typeof entry === "string")
            return ({
                    id: entry
                });
        if (entry && typeof entry === "object" && typeof entry.id === "string")
            return entry;
        return ({
                id: String(entry)
            });
    }

    readonly property var layoutOf: ({
            left: (Array.isArray(config.left) ? config.left : []).map(normalizeEntry),
            center: (Array.isArray(config.center) ? config.center : []).map(normalizeEntry),
            right: (Array.isArray(config.right) ? config.right : []).map(normalizeEntry)
        })

    // Any of the four screen edges. "left"/"right" turn the bar on its side:
    // the sections stack top→center→bottom, each widget is a bar-thickness
    // wide cell, and panels open beside the bar instead of under it.
    readonly property string position: BarModel.normalizePosition(config.position)
    readonly property bool vertical: BarModel.isVerticalPosition(position)
    // The bar's thickness. Omarchy's two sizes: a column needs more room than
    // a strip, so a vertical bar is its own theme token.
    readonly property int barSize: vertical ? theme.barWidthVertical : theme.barHeight
    // Which center widget is pinned dead-center. Omarchy's centerAnchor,
    // configurable here instead of hardcoded to the clock; an id that is not
    // in the center section falls back to centering the whole group.
    readonly property string centerAnchorId: String(config.centerAnchor === undefined || config.centerAnchor === null ? "clock" : config.centerAnchor)

    // Repeater models hold only the id strings, and keep their identity while
    // the id sequence is unchanged — so a settings write (which replaces the
    // whole config object) updates live widgets in place instead of
    // recreating them. Recreating would destroy the very panel the settings
    // were just edited from. The center split (the anchor pinned dead-center,
    // neighbors flanking it) is computed in the same pass — deriving it from
    // separate reactive properties left a transient evaluation where the
    // flanking rows still contained the anchor, instantiating it twice.
    property var modelLeft: []
    property var modelRight: []
    property var modelCenterBefore: []
    property var modelCenterAfter: []
    property int centerAnchorIndex: -1
    property string centerAnchorWidget: ""

    onLayoutOfChanged: syncModels()
    onCenterAnchorIdChanged: syncModels()
    Component.onCompleted: {
        syncModels();
        applyTransparency();
    }

    function sameIds(a, b) {
        // Element-wise: no join separator is safe against ids that could
        // themselves contain it.
        return a.length === b.length && a.every((id, i) => id === b[i]);
    }

    function syncModels() {
        const leftIds = layoutOf.left.map(e => e.id);
        const centerIds = layoutOf.center.map(e => e.id);
        const rightIds = layoutOf.right.map(e => e.id);
        const anchor = centerIds.indexOf(centerAnchorId);
        const before = anchor >= 0 ? centerIds.slice(0, anchor) : [];
        const after = anchor >= 0 ? centerIds.slice(anchor + 1) : centerIds;
        centerAnchorIndex = anchor;
        centerAnchorWidget = anchor >= 0 ? centerIds[anchor] : "";
        if (!sameIds(leftIds, modelLeft))
            modelLeft = leftIds;
        if (!sameIds(rightIds, modelRight))
            modelRight = rightIds;
        if (!sameIds(before, modelCenterBefore))
            modelCenterBefore = before;
        if (!sameIds(after, modelCenterAfter))
            modelCenterAfter = after;
    }

    // --------------------------------------------------------- bar palette
    // Omarchy bar palette: background = theme background, text = theme
    // foreground (our ansi.white), attention = red. 420 ms InOutCubic
    // transitions carry theme swaps — but not the auto-contrast swap, which
    // has to land in the same frame as the transparency it belongs to.
    // Read through the [bar] surface, so a theme (or the machine override) can
    // restyle the bar alone; each key falls back to the base token it always
    // used.
    readonly property color barBackground: theme.bar.background
    readonly property color themeForeground: theme.bar.text
    // The other candidate for a transparent bar's text: the bar's own
    // background color, which is by construction the opposite polarity of the
    // foreground and so reads over a wallpaper the foreground disappears into.
    // Taken without the alpha companion — a translucent contrast color would
    // defeat the purpose.
    readonly property color themeContrastForeground: theme.sCol("bar", "background", theme.surface1)
    property color transparentForeground: themeForeground
    property bool useTransparentForeground: false
    property bool foregroundAnimationEnabled: true
    readonly property color barForeground: useTransparentForeground ? transparentForeground : themeForeground

    // ------------------------------------------------------- transparency
    // bar.transparent in shell.json, toggled by double-clicking empty bar
    // space. `transparent` only follows once a foreground has been sampled,
    // so the bar never spends a frame with unreadable text over the wallpaper.
    readonly property bool requestedTransparent: config.transparent === true
    property bool transparent: false

    onRequestedTransparentChanged: applyTransparency()
    onThemeForegroundChanged: scheduleForegroundRefresh()
    onThemeContrastForegroundChanged: scheduleForegroundRefresh()
    onPositionChanged: scheduleForegroundRefresh()

    function applyTransparency() {
        if (!requestedTransparent) {
            foregroundAnimationEnabled = false;
            useTransparentForeground = false;
            transparent = false;
            transparentForeground = themeForeground;
            restoreForegroundAnimation();
            return;
        }
        scheduleForegroundRefresh();
    }

    // Two frames of snapped color, then animations back on: a sampled
    // foreground must not crossfade through the color it was replacing.
    function restoreForegroundAnimation() {
        Qt.callLater(() => Qt.callLater(() => barRoot.foregroundAnimationEnabled = true));
    }

    function scheduleForegroundRefresh() {
        if (!requestedTransparent) {
            transparentForeground = themeForeground;
            return;
        }
        foregroundTimer.restart();
    }

    function colorHex(value) {
        const c = typeof value === "string" ? Qt.color(value) : value;
        const channel = v => {
            const s = Math.round(Math.max(0, Math.min(1, v)) * 255).toString(16);
            return s.length < 2 ? "0" + s : s;
        };
        return "#" + channel(c.r) + channel(c.g) + channel(c.b);
    }

    property bool foregroundRefreshPending: false

    function refreshTransparentForeground() {
        if (!requestedTransparent)
            return;
        if (foregroundProc.running) {
            // The in-flight sample bakes the wallpaper and theme colors of its
            // launch into argv, so a refresh landing mid-run must re-fire when
            // it exits or the bar keeps a stale contrast color.
            foregroundRefreshPending = true;
            return;
        }
        const first = Quickshell.screens.length > 0 ? Quickshell.screens[0] : null;
        // The sampled strip is the one the bar actually covers, which on a
        // vertical bar is a column down the left or right edge.
        foregroundProc.command = [barRoot.binDir + "bar-text-color", barRoot.position, String(barRoot.barSize), colorHex(barRoot.themeForeground), colorHex(barRoot.themeContrastForeground)].concat(first ? ["--screen", Math.round(first.width) + "x" + Math.round(first.height)] : []);
        foregroundProc.running = true;
    }

    Timer {
        id: foregroundTimer
        interval: 120
        onTriggered: barRoot.refreshTransparentForeground()
    }

    Process {
        id: foregroundProc
        stdout: SplitParser {
            onRead: line => {
                const value = String(line || "").trim();
                if (!/^#[0-9A-Fa-f]{6}$/.test(value))
                    return;
                barRoot.foregroundAnimationEnabled = false;
                barRoot.transparentForeground = value;
                if (barRoot.requestedTransparent) {
                    barRoot.useTransparentForeground = true;
                    barRoot.transparent = true;
                }
                barRoot.restoreForegroundAnimation();
            }
        }
        onExited: {
            if (barRoot.foregroundRefreshPending) {
                barRoot.foregroundRefreshPending = false;
                barRoot.refreshTransparentForeground();
            }
        }
    }

    // The wallpaper the sample is taken from. Theirs watches the state dir for
    // their `current` symlink; ours watches the file whose content IS the
    // wallpaper path (Modules/Background writes it).
    FileView {
        path: barRoot.statePath + "/background"
        watchChanges: true
        printErrors: false
        onFileChanged: {
            reload();
            barRoot.scheduleForegroundRefresh();
        }
        onLoaded: barRoot.scheduleForegroundRefresh()
        Component.onCompleted: reload()
    }

    // ---------------------------------------------------------- bar hiding
    // Presence of the `bar-off` flag = bar hidden, so the bar can be taken off
    // screen without killing the shell (omarchy's omarchy-toggle-bar). The
    // watcher covers the file AND its directory, so an external touch/rm of
    // the flag moves the bar too.
    property bool barHidden: false

    function setBarHidden(hidden) {
        barHidden = hidden;
        Quickshell.execDetached(["bash", "-c", hidden ? "mkdir -p " + statePath + " && touch " + statePath + "/bar-off" : "rm -f " + statePath + "/bar-off"]);
    }

    FileView {
        path: barRoot.statePath + "/bar-off"
        watchChanges: true
        printErrors: false
        onLoaded: barRoot.barHidden = true
        onLoadFailed: barRoot.barHidden = false
        onFileChanged: reload()
        // Neither loaded nor loadFailed fires until something reads the view.
        Component.onCompleted: reload()
    }

    IpcHandler {
        target: "bar"

        // NOTE: `qs ipc call bar show` prints the target listing — the
        // quickshell CLI parses a bare `show` as its own subcommand. Use
        // `qs ipc call bar -- show`.
        function show(): string {
            barRoot.setBarHidden(false);
            return "ok";
        }

        function hide(): string {
            barRoot.setBarHidden(true);
            return "ok";
        }

        function toggle(): string {
            barRoot.setBarHidden(!barRoot.barHidden);
            return barRoot.barHidden ? "hidden" : "shown";
        }

        function status(): string {
            return JSON.stringify({
                hidden: barRoot.barHidden,
                position: barRoot.position,
                vertical: barRoot.vertical,
                size: barRoot.barSize,
                transparent: barRoot.transparent,
                requestedTransparent: barRoot.requestedTransparent,
                foreground: barRoot.colorHex(barRoot.barForeground),
                centerAnchor: barRoot.centerAnchorId,
                anchored: barRoot.centerAnchorIndex >= 0
            });
        }

        // Omarchy's summonBarWidget: any process (a niri bind) can open a
        // widget's panel — `qs ipc call bar open audio`. First bar that
        // carries the widget wins, which is per-screen-identical layouts in
        // practice.
        function open(widgetId: string): string {
            for (const b of barRoot.screenBars)
                if (b.summonWidget(widgetId))
                    return "ok";
            return "no widget with a panel: " + widgetId;
        }

        // Omarchy's hideBarWidget, generalized: closes whatever panel is
        // open on any screen.
        function closePanel(): string {
            let closed = false;
            for (const b of barRoot.screenBars) {
                if (b.activePanel) {
                    b.activePanel.close();
                    closed = true;
                }
            }
            return closed ? "ok" : "no panel open";
        }
    }

    // The per-screen bar windows, registered so the IPC verbs above can
    // reach their slot lists.
    property var screenBars: []

    function registerScreenBar(b) {
        if (b && screenBars.indexOf(b) === -1)
            screenBars.push(b);
    }

    function unregisterScreenBar(b) {
        const i = screenBars.indexOf(b);
        if (i >= 0)
            screenBars.splice(i, 1);
    }

    // ------------------------------------------------- persisted mutations
    function toggleTransparency() {
        shell.updateBarConfig({
            transparent: !requestedTransparent
        });
    }

    function setPosition(value) {
        shell.updateBarConfig({
            position: BarModel.normalizePosition(value)
        });
    }

    // `fromRef`/`beforeRef` are section indices here (ids are not unique);
    // BarModel.moveEntry also still accepts id strings for other callers.
    function moveWidget(fromSection, fromRef, toSection, beforeRef) {
        return shell.moveBarEntry(fromSection, fromRef, toSection, beforeRef);
    }

    // ------------------------------------------------------- drag-to-reorder
    // Shared by every bar surface: one drag at a time, and the ghost windows
    // below read this state to draw it.
    property var dragSource: null
    property var dragWindow: null
    property var dragScreen: null
    property url dragImageUrl: ""
    property var dropTarget: null
    property bool dropAfter: false
    property var dropMarkerGeometry: null
    property real dragScreenX: 0
    property real dragScreenY: 0
    property real dragOffsetX: 0
    property real dragOffsetY: 0

    function clearDrag() {
        dragSource = null;
        dragWindow = null;
        dragScreen = null;
        dragImageUrl = "";
        dropTarget = null;
        dropAfter = false;
        dropMarkerGeometry = null;
        dragScreenX = 0;
        dragScreenY = 0;
        dragOffsetX = 0;
        dragOffsetY = 0;
    }

    function captureDragGhost(slot) {
        const item = slot ? slot.activeItem : null;
        dragImageUrl = "";
        if (!item || typeof item.grabToImage !== "function")
            return;
        const w = Math.max(1, Math.ceil(item.width || item.implicitWidth || slot.width || 1));
        const h = Math.max(1, Math.ceil(item.height || item.implicitHeight || slot.height || 1));
        item.grabToImage(result => {
            if (barRoot.dragSource !== slot || !result || !result.url)
                return;
            barRoot.dragImageUrl = result.url;
        }, Qt.size(w, h));
    }

    // ---------------------------------------------------------- bar move
    property bool barMoveActive: false
    property string barMoveCandidate: ""
    property var barMoveScreen: null

    function beginBarMove(screen) {
        barMoveScreen = screen;
        barMoveCandidate = position;
        barMoveActive = true;
    }

    function updateBarMove(screenPoint) {
        if (!barMoveActive || !barMoveScreen)
            return;
        // Their nearestScreenEdge, unconstrained: all four edges are bars the
        // shell can render, so the triangle the pointer is in names the edge.
        barMoveCandidate = BarModel.nearestScreenEdge(screenPoint, barMoveScreen.width, barMoveScreen.height);
    }

    function clearBarMove() {
        barMoveActive = false;
        barMoveCandidate = "";
        barMoveScreen = null;
    }

    function finishBarMove() {
        const edge = barMoveCandidate;
        const changed = barMoveActive && edge && edge !== position;
        clearBarMove();
        if (changed)
            setPosition(edge);
    }

    // ------------------------------------------------------ widget registry
    readonly property var registry: ({
            "launcher": launcherComponent,
            "workspaces": workspacesComponent,
            "clock": clockComponent,
            "window": windowComponent,
            "audio": audioComponent,
            "mic": micComponent,
            "network": networkComponent,
            "bluetooth": bluetoothComponent,
            "battery": batteryComponent,
            "media": mediaComponent,
            "kb": kbComponent,
            "tray": trayComponent,
            "update": updateComponent,
            "indicators": indicatorsComponent,
            "dnd": dndComponent,
            "dictation": dictationComponent,
            "reminder": reminderComponent,
            "stayawake": stayAwakeComponent,
            "nightlight": nightLightComponent,
            "screenrecording": screenRecordingComponent,
            "ai": aiComponent,
            "weather": weatherComponent,
            "monitor": monitorComponent,
            "dropbox": dropboxComponent,
            "tailscale": tailscaleComponent,
            "spacer": spacerComponent
        })

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: panel

            required property var modelData

            // Widgets reach the shell (updateEntryInline, toggleLauncher)
            // through their injected `bar`.
            readonly property var shell: barRoot.shell
            // The normalized layout, for widgets whose behavior depends on
            // what else is on the bar — the tray suppresses the SNI item of
            // any app that has a dedicated widget in the layout.
            readonly property var layoutConfig: barRoot.layoutOf
            // Which edge the bar is on, for panels anchoring under (or over,
            // or beside) their widget, and the orientation every widget lays
            // itself out along.
            readonly property string position: barRoot.position
            readonly property bool vertical: barRoot.vertical
            readonly property int barSize: barRoot.barSize

            // Cold-start metric consumed by bin/bench: ms from process launch
            // to this bar window finishing construction. Registration rides
            // the same handler — a delegate can only declare one.
            Component.onCompleted: {
                console.info("bench:first-bar", Date.now() - Quickshell.launchTime.getTime(), "ms");
                barRoot.registerScreenBar(panel);
            }

            screen: modelData
            visible: !barRoot.barHidden
            // Their anchor set: a bar spans the edge it sits on and is pinned
            // to it, so a vertical bar takes both top and bottom and only its
            // own side, and the free axis is left at 0 (the layer surface
            // stretches it).
            anchors {
                top: barRoot.position === "top" || barRoot.vertical
                bottom: barRoot.position === "bottom" || barRoot.vertical
                left: barRoot.position === "left" || !barRoot.vertical
                right: barRoot.position === "right" || !barRoot.vertical
            }
            implicitWidth: barRoot.vertical ? barRoot.barSize : 0
            implicitHeight: barRoot.vertical ? 0 : barRoot.barSize

            property color barBackground: barRoot.barBackground
            property color barForeground: barRoot.barForeground

            // A transparent bar needs a non-opaque surface format, or the
            // compositor draws it black instead of showing the desktop.
            color: barRoot.transparent ? "transparent" : barBackground
            surfaceFormat.opaque: false
            WlrLayershell.namespace: "qshell-bar"
            WlrLayershell.layer: WlrLayer.Top

            Behavior on barBackground {
                ColorAnimation {
                    duration: 420
                    easing.type: Easing.InOutCubic
                }
            }
            Behavior on barForeground {
                enabled: barRoot.foregroundAnimationEnabled
                ColorAnimation {
                    duration: 420
                    easing.type: Easing.InOutCubic
                }
            }

            // ------------------------------------------------- registries
            // Every clickable inside this bar surface (BarButton registers
            // itself), and every widget slot. Both are omarchy's: the first
            // is how a left click survives the drag MouseArea covering the
            // widgets, the second is what drop targeting and panel
            // navigation walk.
            property var clickTargets: []
            property var moduleSlots: []

            function registerClickTarget(target) {
                if (!target || clickTargets.indexOf(target) !== -1)
                    return;
                const next = clickTargets.slice();
                next.push(target);
                clickTargets = next;
            }

            function unregisterClickTarget(target) {
                clickTargets = clickTargets.filter(item => item !== target);
            }

            function registerModuleSlot(slot) {
                if (!slot || moduleSlots.indexOf(slot) !== -1)
                    return;
                const next = moduleSlots.slice();
                next.push(slot);
                moduleSlots = next;
            }

            function unregisterModuleSlot(slot) {
                moduleSlots = moduleSlots.filter(item => item !== slot);
            }

            // The IPC summon path (bar open <widgetId>). Same eligibility
            // rules as panelNavigationSlots: a drawn slot whose widget
            // exposes openPanel().
            function summonWidget(widgetId) {
                for (let i = 0; i < moduleSlots.length; i++) {
                    const slot = moduleSlots[i];
                    if (!slot || slot.widgetId !== widgetId)
                        continue;
                    const item = slot.activeItem;
                    if (!item || item.visible !== true || typeof item.openPanel !== "function")
                        continue;
                    item.openPanel();
                    return true;
                }
                return false;
            }

            Component.onDestruction: barRoot.unregisterScreenBar(panel)

            // A target only takes a click while it is on screen and enabled —
            // our stand-in for their interactive/pressable/concealed trio
            // (a collapsed indicator sets enabled:false and opacity 0).
            function moduleTargetClickable(target) {
                return !!target && target.visible !== false && target.opacity !== 0 && target.enabled !== false && typeof target.triggerPress === "function";
            }

            // Reverse registration order approximates topmost-first: a nested
            // button registers after the widget that contains it.
            function moduleClickTargetAt(slot, localX, localY) {
                for (let i = clickTargets.length - 1; i >= 0; i--) {
                    const target = clickTargets[i];
                    if (!moduleTargetClickable(target))
                        continue;
                    let p;
                    try {
                        p = slot.mapToItem(target, localX, localY);
                    } catch (e) {
                        continue;
                    }
                    if (p.x >= 0 && p.x <= target.width && p.y >= 0 && p.y <= target.height)
                        return target;
                }
                if (moduleTargetClickable(slot.activeItem))
                    return slot.activeItem;
                return null;
            }

            function pressModuleClickTarget(slot, button, localX, localY) {
                const target = moduleClickTargetAt(slot, localX, localY);
                if (!target)
                    return false;
                target.triggerPress(button);
                return true;
            }

            // ------------------------------------------------ drop geometry
            // The bar window spans the output horizontally but sits at one
            // edge, so a scene point inside it is offset from the screen point
            // the full-screen ghost overlay draws in.
            function windowScreenPoint(scenePoint) {
                let x = scenePoint.x;
                let y = scenePoint.y;
                if (barRoot.position === "bottom")
                    y += Math.max(0, panel.screen.height - panel.height);
                else if (barRoot.position === "right")
                    x += Math.max(0, panel.screen.width - panel.width);
                return {
                    x: x,
                    y: y
                };
            }

            function slotScenePoint(slot) {
                try {
                    return slot.mapToItem(null, 0, 0);
                } catch (e) {
                    return {
                        x: slot.x,
                        y: slot.y
                    };
                }
            }

            function dropMarkerRect(slot, after) {
                if (!slot)
                    return null;
                const p = windowScreenPoint(slotScenePoint(slot));
                const thickness = 3; // omarchy's Style.spacing.xs
                // The marker lies across the bar at the insertion boundary, so
                // it is a vertical rule on a horizontal bar and a horizontal
                // one on a vertical bar.
                if (barRoot.vertical)
                    return {
                        x: p.x,
                        y: p.y + (after ? slot.height : 0) - thickness / 2,
                        width: slot.width,
                        height: thickness
                    };
                return {
                    x: p.x + (after ? slot.width : 0) - thickness / 2,
                    y: p.y,
                    width: thickness,
                    height: slot.height
                };
            }

            function moduleDropAtScene(scenePoint, sourceSlot) {
                // A drop outside the bar surface is a cancelled drag, not a
                // move to the far end of the bar.
                if (scenePoint.x < 0 || scenePoint.x > panel.width || scenePoint.y < 0 || scenePoint.y > panel.height)
                    return null;

                const candidates = [];
                for (let i = 0; i < moduleSlots.length; i++) {
                    const slot = moduleSlots[i];
                    if (!slot || slot === sourceSlot || !slot.visible || slot.width <= 0 || slot.height <= 0)
                        continue;
                    const p = slotScenePoint(slot);
                    candidates.push({
                        slot: slot,
                        x: p.x,
                        y: p.y,
                        width: slot.width,
                        height: slot.height
                    });
                }
                return BarModel.nearestDropTarget(candidates, scenePoint, barRoot.vertical);
            }

            function visibleModuleSlotAt(section, sectionIndex, sourceSlot) {
                for (let i = 0; i < moduleSlots.length; i++) {
                    const slot = moduleSlots[i];
                    if (!slot || slot === sourceSlot || slot.section !== section || slot.index + slot.indexOffset !== sectionIndex)
                        continue;
                    if (!slot.visible || slot.width <= 0 || slot.height <= 0)
                        continue;
                    return slot;
                }
                return null;
            }

            // The section index the moved widget lands in front of when it is
            // dropped on the far edge of a target: the next one that is
            // actually drawn, so a hidden neighbour cannot swallow the move.
            // -1 appends.
            function nextVisibleModuleIndex(section, afterIndex, sourceSlot) {
                const entries = barRoot.layoutOf[section] || [];
                for (let i = afterIndex + 1; i < entries.length; i++) {
                    if (visibleModuleSlotAt(section, i, sourceSlot))
                        return i;
                }
                return -1;
            }

            function dropAtTarget(sourceSlot, targetSlot, after) {
                if (!sourceSlot || !targetSlot)
                    return false;
                // Entries are addressed by section index, not id: ids are not
                // unique (two spacers), and an id lookup would move the first
                // instance instead of the dragged one.
                const sourceIndex = sourceSlot.index + sourceSlot.indexOffset;
                const targetIndex = targetSlot.index + targetSlot.indexOffset;
                const beforeIndex = after ? nextVisibleModuleIndex(targetSlot.section, targetIndex, sourceSlot) : targetIndex;
                if (sourceSlot.section === targetSlot.section && sourceIndex === beforeIndex)
                    return false;
                return barRoot.moveWidget(sourceSlot.section, sourceIndex, targetSlot.section, beforeIndex);
            }

            // ------------------------------------------- panel navigation
            // Panel-owning widgets of one section, in layout order.
            function panelNavigationSlots(section) {
                const entries = barRoot.layoutOf[section] || [];
                const slots = [];
                for (let i = 0; i < entries.length; i++) {
                    const id = entries[i].id;
                    for (let j = 0; j < moduleSlots.length; j++) {
                        const slot = moduleSlots[j];
                        if (!slot || slot.section !== section || slot.widgetId !== id)
                            continue;
                        const item = slot.activeItem;
                        if (!item || item.visible !== true || !slot.visible || slot.width <= 0 || slot.height <= 0)
                            continue;
                        if (typeof item.openPanel !== "function")
                            continue;
                        slots.push(slot);
                        break;
                    }
                }
                return slots;
            }

            function switchPanelFrom(owner, direction) {
                if (!owner)
                    return false;
                let currentSlot = null;
                for (let i = 0; i < moduleSlots.length; i++) {
                    if (moduleSlots[i] && moduleSlots[i].activeItem === owner) {
                        currentSlot = moduleSlots[i];
                        break;
                    }
                }
                if (!currentSlot)
                    return false;

                const slots = panelNavigationSlots(currentSlot.section);
                if (slots.length < 2)
                    return false;
                const currentIndex = slots.indexOf(currentSlot);
                if (currentIndex < 0)
                    return false;

                const step = direction < 0 ? -1 : 1;
                const nextSlot = slots[(currentIndex + step + slots.length) % slots.length];
                if (!nextSlot || !nextSlot.activeItem || nextSlot.activeItem === owner)
                    return false;
                nextSlot.activeItem.openPanel();
                return true;
            }

            // ------------------------------------------- indicator reveal
            // Omarchy's center-section hover, ported: their center module
            // list fills the whole bar surface behind the left/right
            // sections, so the pointer anywhere on the bar reveals the
            // collapsed indicators — which is the only way to reach them
            // when nothing is active and the widget has no width of its own.
            // The 120 ms release debounce is theirs; the suppression while a
            // widget panel is open replaces the per-panel opt-outs their
            // clock and weather panels set by hand.
            property bool centerSectionHovered: false
            property bool centerSectionRevealHeld: false
            readonly property bool centerHoverRevealSuppressed: activePanel !== null

            function setCenterSectionHovered(hovered) {
                centerSectionHovered = hovered;
                if (hovered) {
                    centerRevealTimer.stop();
                    centerSectionRevealHeld = true;
                } else {
                    centerRevealTimer.restart();
                }
            }

            Timer {
                id: centerRevealTimer
                interval: 120
                onTriggered: panel.centerSectionRevealHeld = panel.centerSectionHovered
            }

            // Declared first so it sits under every widget: presses on empty
            // bar space reach it, presses on a widget are taken by that
            // widget's own slot area above.
            CenterGestureArea {
                anchors.fill: parent
                barWindow: panel
            }

            // One widget panel open at a time per screen.
            property var activePanel: null

            function requestPanel(p) {
                if (activePanel && activePanel !== p)
                    activePanel.close();
                activePanel = p;
            }

            function releasePanel(p) {
                if (activePanel === p)
                    activePanel = null;
            }

            // ------------------------------------------------------ tooltip
            // One shared tooltip per bar surface, 400 ms delayed, anchored
            // 6 px off the hovered widget on the desktop-facing side.
            property Item tooltipTarget: null
            property string tooltipText: ""
            property bool tooltipShown: false

            function showTooltip(target, text) {
                // No tooltips mid-gesture: the pointer is carrying a widget
                // (or the bar) and a hover bubble on top of the ghost reads
                // as a stuck artifact.
                if (barRoot.dragSource || barRoot.barMoveActive)
                    return;
                tooltipTarget = target;
                tooltipText = text;
                tooltipTimer.restart();
            }

            function hideTooltip(target) {
                if (tooltipTarget !== target)
                    return;
                tooltipTimer.stop();
                tooltipShown = false;
                tooltipTarget = null;
            }

            function clearTooltip() {
                tooltipTimer.stop();
                tooltipShown = false;
                tooltipTarget = null;
            }

            Timer {
                id: tooltipTimer
                interval: 400
                onTriggered: panel.tooltipShown = panel.tooltipTarget !== null
            }

            PopupWindow {
                id: tooltipWindow

                visible: panel.tooltipShown && panel.tooltipTarget !== null && panel.tooltipText !== ""
                color: "transparent"
                implicitWidth: Math.ceil(tooltipBubble.implicitWidth)
                implicitHeight: Math.ceil(tooltipBubble.implicitHeight)

                anchor {
                    id: tooltipAnchor
                    window: panel
                    adjustment: PopupAdjustment.Slide
                    edges: Edges.Top | Edges.Left
                    gravity: Edges.Bottom | Edges.Right
                    rect.width: 1
                    rect.height: 1

                    onAnchoring: {
                        const target = panel.tooltipTarget;
                        if (!target)
                            return;
                        // Their four cases: the bubble sits 6 px off the
                        // widget on the side the desktop is on.
                        let localX = target.width / 2 - tooltipWindow.implicitWidth / 2;
                        let localY = target.height + 6;
                        if (barRoot.position === "bottom") {
                            localY = -tooltipWindow.implicitHeight - 6;
                        } else if (barRoot.position === "left") {
                            localX = target.width + 6;
                            localY = target.height / 2 - tooltipWindow.implicitHeight / 2;
                        } else if (barRoot.position === "right") {
                            localX = -tooltipWindow.implicitWidth - 6;
                            localY = target.height / 2 - tooltipWindow.implicitHeight / 2;
                        }
                        const point = panel.contentItem.mapFromItem(target, localX, localY);
                        tooltipAnchor.rect.x = Math.round(point.x);
                        tooltipAnchor.rect.y = Math.round(point.y);
                    }
                }

                Rectangle {
                    id: tooltipBubble
                    implicitWidth: tooltipLabel.implicitWidth + 20
                    implicitHeight: tooltipLabel.implicitHeight + 14
                    radius: barRoot.theme.radiusBase
                    // The [tooltip] surface. Defaults reproduce what this
                    // bubble always drew (bar background at 0.97, foreground
                    // text and border) — but the bubble is opaque chrome of
                    // its own, so it takes the theme's foreground rather than
                    // the bar's wallpaper-sampled contrast color.
                    color: barRoot.theme.tooltip.background
                    border.width: 1
                    border.color: barRoot.theme.tooltip.border

                    Text {
                        id: tooltipLabel
                        anchors.centerIn: parent
                        text: panel.tooltipText
                        color: barRoot.theme.tooltip.text
                        font.family: barRoot.theme.fontMono
                        font.pixelSize: barRoot.theme.fontPx(1.0)
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // ------------------------------------------------------ layout
            // Two arrangements of the same three sections, one loaded at a
            // time (omarchy's horizontalBar / verticalBar). On a vertical bar
            // "left" means the top end, "right" the bottom one, and the
            // center anchor is pinned to the vertical center — the sections
            // keep their config names so moving the bar never rewrites the
            // layout.
            Loader {
                anchors.fill: parent
                sourceComponent: barRoot.vertical ? verticalBar : horizontalBar
            }

            Component {
                id: horizontalBar

                Item {
                    anchors.fill: parent

                    Row {
                        anchors.left: parent.left
                        anchors.leftMargin: 8
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        spacing: 0
                        Repeater {
                            model: barRoot.modelLeft
                            WidgetSlot {
                                section: "left"
                                barWindow: panel
                            }
                        }
                    }

                    // Center anchor (by default the clock) is pinned to the
                    // true center; the flanking rows hang off it.
                    WidgetSlot {
                        id: centerAnchorSlot
                        visible: barRoot.centerAnchorIndex >= 0
                        modelData: barRoot.centerAnchorWidget
                        index: barRoot.centerAnchorIndex
                        section: "center"
                        barWindow: panel
                        anchors.horizontalCenter: parent.horizontalCenter
                        anchors.verticalCenter: parent.verticalCenter
                    }

                    Row {
                        anchors.right: centerAnchorSlot.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        spacing: 0
                        visible: barRoot.centerAnchorIndex >= 0
                        Repeater {
                            model: barRoot.modelCenterBefore
                            WidgetSlot {
                                section: "center"
                                barWindow: panel
                            }
                        }
                    }

                    Row {
                        anchors.left: barRoot.centerAnchorIndex >= 0 ? centerAnchorSlot.right : undefined
                        anchors.horizontalCenter: barRoot.centerAnchorIndex >= 0 ? undefined : parent.horizontalCenter
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        spacing: 0
                        Repeater {
                            model: barRoot.modelCenterAfter
                            WidgetSlot {
                                section: "center"
                                barWindow: panel
                                indexOffset: barRoot.centerAnchorIndex >= 0 ? barRoot.centerAnchorIndex + 1 : 0
                            }
                        }
                    }

                    Row {
                        anchors.right: parent.right
                        anchors.rightMargin: 8
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        spacing: 0
                        Repeater {
                            model: barRoot.modelRight
                            WidgetSlot {
                                section: "right"
                                barWindow: panel
                            }
                        }
                    }
                }
            }

            Component {
                id: verticalBar

                Item {
                    anchors.fill: parent

                    Column {
                        anchors.top: parent.top
                        anchors.topMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 0
                        Repeater {
                            model: barRoot.modelLeft
                            WidgetSlot {
                                section: "left"
                                barWindow: panel
                            }
                        }
                    }

                    WidgetSlot {
                        id: centerAnchorSlotVertical
                        visible: barRoot.centerAnchorIndex >= 0
                        modelData: barRoot.centerAnchorWidget
                        index: barRoot.centerAnchorIndex
                        section: "center"
                        barWindow: panel
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                    }

                    Column {
                        anchors.bottom: centerAnchorSlotVertical.top
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 0
                        visible: barRoot.centerAnchorIndex >= 0
                        Repeater {
                            model: barRoot.modelCenterBefore
                            WidgetSlot {
                                section: "center"
                                barWindow: panel
                            }
                        }
                    }

                    Column {
                        anchors.top: barRoot.centerAnchorIndex >= 0 ? centerAnchorSlotVertical.bottom : undefined
                        anchors.verticalCenter: barRoot.centerAnchorIndex >= 0 ? undefined : parent.verticalCenter
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 0
                        Repeater {
                            model: barRoot.modelCenterAfter
                            WidgetSlot {
                                section: "center"
                                barWindow: panel
                                indexOffset: barRoot.centerAnchorIndex >= 0 ? barRoot.centerAnchorIndex + 1 : 0
                            }
                        }
                    }

                    Column {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 8
                        anchors.horizontalCenter: parent.horizontalCenter
                        spacing: 0
                        Repeater {
                            model: barRoot.modelRight
                            WidgetSlot {
                                section: "right"
                                barWindow: panel
                            }
                        }
                    }
                }
            }
        }
    }

    // ------------------------------------------------------- ghost overlays
    // Both ghosts are full-screen Overlay windows with an EMPTY input mask —
    // quickshell turns that into true clickthrough, so they can sit under the
    // cursor without stealing the gesture's pointer grab.
    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: ghostWindow

            required property var modelData

            readonly property bool screenMatches: barRoot.dragScreen === modelData || (barRoot.dragScreen && modelData && barRoot.dragScreen.name === modelData.name)
            readonly property bool active: barRoot.dragSource !== null && barRoot.dragScreen !== null && screenMatches
            readonly property var sourceItem: barRoot.dragSource ? barRoot.dragSource.activeItem : null
            readonly property int ghostPadding: 1
            readonly property int ghostWidth: sourceItem ? Math.max(1, Math.ceil(sourceItem.width)) : 1
            readonly property int ghostHeight: sourceItem ? Math.max(1, Math.ceil(sourceItem.height)) : 1

            screen: modelData
            visible: active && sourceItem !== null
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "qshell-bar-drag-ghost"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {}

            Item {
                visible: ghostWindow.visible
                x: Math.round(barRoot.dragScreenX - barRoot.dragOffsetX - ghostWindow.ghostPadding)
                y: Math.round(barRoot.dragScreenY - barRoot.dragOffsetY - ghostWindow.ghostPadding)
                width: ghostWindow.ghostWidth + ghostWindow.ghostPadding * 2
                height: ghostWindow.ghostHeight + ghostWindow.ghostPadding * 2

                Rectangle {
                    anchors.fill: parent
                    color: barRoot.transparent ? "transparent" : barRoot.barBackground
                    border.width: 1
                    border.color: barRoot.barForeground
                    radius: Math.min(barRoot.theme.radiusBase, height / 2)
                    opacity: barRoot.transparent ? 0.45 : 0.94
                }

                Image {
                    anchors.fill: parent
                    anchors.margins: ghostWindow.ghostPadding
                    source: barRoot.dragImageUrl
                    fillMode: Image.Stretch
                    smooth: true
                    opacity: 0.84
                }
            }

            // The drop marker: an accent pill at the slot boundary the widget
            // would land on.
            Rectangle {
                readonly property var targetRect: barRoot.dropMarkerGeometry

                visible: ghostWindow.active && targetRect !== null
                x: targetRect ? Math.round(targetRect.x) : 0
                y: targetRect ? Math.round(targetRect.y) : 0
                width: targetRect ? targetRect.width : 0
                height: targetRect ? targetRect.height : 0
                color: barRoot.theme.accent
                radius: Math.min(width, height) / 2
            }
        }
    }

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: moveGhostWindow

            required property var modelData

            readonly property bool screenMatches: barRoot.barMoveScreen === modelData || (barRoot.barMoveScreen && modelData && barRoot.barMoveScreen.name === modelData.name)

            screen: modelData
            visible: barRoot.barMoveActive && screenMatches
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.namespace: "qshell-bar-move-ghost"
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            anchors {
                top: true
                bottom: true
                left: true
                right: true
            }
            mask: Region {}

            // One fixed-geometry slab per edge, crossfaded on candidate
            // changes. Resizing a single slab between edges repaints
            // mid-transition and flickers; fading between static ones does
            // not. All four of theirs, each drawn at the thickness that edge
            // would actually give the bar.
            Repeater {
                model: ["top", "bottom", "left", "right"]

                Rectangle {
                    required property string modelData

                    readonly property bool edgeVertical: modelData === "left" || modelData === "right"
                    readonly property int edgeSize: edgeVertical ? barRoot.theme.barWidthVertical : barRoot.theme.barHeight

                    x: modelData === "right" ? parent.width - edgeSize : 0
                    y: modelData === "bottom" ? parent.height - edgeSize : 0
                    width: edgeVertical ? edgeSize : parent.width
                    height: edgeVertical ? parent.height : edgeSize
                    color: barRoot.transparent ? "transparent" : barRoot.barBackground
                    border.width: 1
                    border.color: barRoot.barForeground
                    visible: opacity > 0
                    opacity: barRoot.barMoveCandidate === modelData ? (barRoot.transparent ? 0.45 : 0.7) : 0

                    Behavior on opacity {
                        NumberAnimation {
                            duration: 140
                            easing.type: Easing.OutCubic
                        }
                    }
                }
            }
        }
    }

    // --------------------------------------------------------- gesture area
    // Press-drag the empty bar space to move the bar to another screen edge;
    // double-click it to toggle transparency. Omarchy's CenterGestureArea.
    component CenterGestureArea: MouseArea {
        id: gestureArea

        required property var barWindow

        property bool dragging: false
        property bool suppressClick: false
        property real pressedX: 0
        property real pressedY: 0
        readonly property real dragThreshold: 4

        acceptedButtons: Qt.LeftButton
        cursorShape: dragging ? Qt.ClosedHandCursor : Qt.ArrowCursor
        pressAndHoldInterval: 200

        function startDrag(x, y) {
            if (dragging)
                return;
            dragging = true;
            barWindow.clearTooltip();
            barRoot.beginBarMove(barWindow.screen);
            barRoot.updateBarMove(barWindow.windowScreenPoint(gestureArea.mapToItem(null, x, y)));
        }

        HoverHandler {
            onHoveredChanged: gestureArea.barWindow.setCenterSectionHovered(hovered)
        }

        onPressed: mouse => {
            dragging = false;
            suppressClick = false;
            pressedX = mouse.x;
            pressedY = mouse.y;
        }

        onPressAndHold: mouse => startDrag(mouse.x, mouse.y)

        onPositionChanged: mouse => {
            if (!(mouse.buttons & Qt.LeftButton))
                return;
            if (!dragging) {
                if (Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY) < dragThreshold)
                    return;
                startDrag(mouse.x, mouse.y);
                return;
            }
            barRoot.updateBarMove(barWindow.windowScreenPoint(gestureArea.mapToItem(null, mouse.x, mouse.y)));
        }

        onReleased: mouse => {
            if (!dragging)
                return;
            dragging = false;
            suppressClick = true;
            barRoot.finishBarMove();
            mouse.accepted = true;
        }

        onCanceled: {
            dragging = false;
            suppressClick = false;
            barRoot.clearBarMove();
        }

        onClicked: mouse => {
            if (suppressClick) {
                suppressClick = false;
                mouse.accepted = true;
            }
        }

        onDoubleClicked: mouse => {
            if (suppressClick) {
                suppressClick = false;
                return;
            }
            if (mouse.button === Qt.LeftButton) {
                barRoot.toggleTransparency();
                mouse.accepted = true;
            }
        }
    }

    // ------------------------------------------------------------ the slot
    // One widget's place on the bar: it owns the widget's Loader, the
    // press/drag area over it, the open-panel pill, and the drag-source
    // treatment. Omarchy's ModuleSlot.
    component WidgetSlot: Item {
        id: slot

        required property var modelData
        required property int index
        required property var barWindow
        property string section: "center"
        // The flanking center rows repeat over slices of the center model;
        // the offset maps a slice-local index back to the section index.
        property int indexOffset: 0
        readonly property string widgetId: String(modelData)
        // Reactive against the live config: a settings write lands here and
        // is pushed into the running widget without recreating it.
        readonly property var entry: {
            const arr = barRoot.layoutOf[section];
            const e = Array.isArray(arr) ? arr[index + indexOffset] : undefined;
            return e && e.id === widgetId ? e : ({
                    id: widgetId
                });
        }
        // Looked up on demand rather than cached in a property: when the
        // configured center anchor changes, the slot's id and a cached
        // component would be dirtied in an undefined order, and the loader
        // could mount (and warn about) the previous id's component.
        function componentFor(id) {
            return barRoot.registry[id];
        }
        readonly property var activeItem: slotLoader.item
        readonly property bool dragSource: barRoot.dragSource === slot
        readonly property bool panelOpen: barWindow.activePanel !== null && barWindow.activePanel.anchorItem === activeItem
        // A widget can say how long the open-panel pill should be, so it
        // tracks what the widget paints rather than the slot it fills.
        readonly property real panelIndicatorExtent: {
            const key = barRoot.vertical ? "openPanelIndicatorHeight" : "openPanelIndicatorWidth";
            const hint = activeItem && key in activeItem ? activeItem[key] : undefined;
            if (hint !== undefined && hint !== null && hint > 0)
                return Math.round(hint);
            return Math.max(10, Math.round((barRoot.vertical ? slot.height : slot.width) * 0.55));
        }

        // Across the bar the slot is the bar's thickness; along it, whatever
        // the widget paints. A widget that hides itself takes no space
        // (omarchy's rule — ours used to keep the fixedWidth of a hidden
        // button as a dead gap).
        width: barRoot.vertical ? barRoot.barSize : (activeItem && activeItem.visible ? activeItem.implicitWidth : 0)
        height: barRoot.vertical ? (activeItem && activeItem.visible ? activeItem.implicitHeight : 0) : barRoot.barSize
        z: slotPointer.dragging ? 100 : 0

        Component.onCompleted: barWindow.registerModuleSlot(slot)
        Component.onDestruction: {
            if (barRoot.dragSource === slot)
                barRoot.clearDrag();
            barWindow.unregisterModuleSlot(slot);
        }

        // The lifted widget leaves a hint of itself behind.
        Rectangle {
            visible: slot.dragSource
            anchors.fill: parent
            anchors.margins: 1
            color: barRoot.transparent ? "transparent" : barRoot.barBackground
            border.width: 1
            border.color: barRoot.barForeground
            radius: Math.min(barRoot.theme.radiusBase, height / 2)
            opacity: barRoot.transparent ? 0.22 : 0.32
        }

        Loader {
            id: slotLoader
            anchors.fill: parent
            // The center-anchor slot exists even when the configured anchor id
            // is not in the center section; without this it would mount a
            // second copy of a widget that is already in a flanking row.
            active: slot.widgetId !== ""
            opacity: slot.dragSource ? 0.22 : 1.0
            sourceComponent: slot.componentFor(slot.widgetId) !== undefined ? slot.componentFor(slot.widgetId) : missingComponent
            onLoaded: {
                if ("screenName" in item)
                    item.screenName = slot.barWindow.screen.name;
                if ("bar" in item)
                    item.bar = slot.barWindow;
                if ("settings" in item)
                    item.settings = slot.entry;
                if (slot.componentFor(slot.widgetId) === undefined) {
                    item.missingId = slot.widgetId;
                    console.warn("Bar: unknown widget id in config:", slot.widgetId);
                }
                // Dev hook (like QSHELL_DEV): auto-open a widget's panel so
                // headless sessions can verify panel rendering. Delayed by a
                // timer rather than Qt.callLater — in the frame the bar is
                // built in, a widget's panel LazyLoader still has no item and
                // openPanel() throws on it.
                if (Quickshell.env("QSHELL_TEST_PANEL") === slot.widgetId)
                    testPanelTimer.start();
            }
        }

        onEntryChanged: {
            if (slotLoader.item && "settings" in slotLoader.item)
                slotLoader.item.settings = entry;
        }

        Timer {
            id: testPanelTimer
            interval: 400
            onTriggered: {
                if (slot.activeItem && typeof slot.activeItem.openPanel === "function")
                    slot.activeItem.openPanel();
            }
        }

        // The open-panel pill: an accent bar on the widget's inner edge — the
        // one facing the desktop — so it underlines a top bar, overlines a
        // bottom one, and points inward from a left or right one. It reads as
        // pointing at the panel that opened.
        Rectangle {
            readonly property int inset: 2

            visible: opacity > 0
            opacity: slot.panelOpen && !slot.dragSource ? 0.9 : 0
            color: barRoot.theme.accent
            width: barRoot.vertical ? 2 : slot.panelIndicatorExtent
            height: barRoot.vertical ? slot.panelIndicatorExtent : 2
            radius: Math.min(width, height) / 2
            x: barRoot.vertical ? (barRoot.position === "left" ? parent.width - width - inset : inset) : Math.round((parent.width - width) / 2)
            y: barRoot.vertical ? Math.round((parent.height - height) / 2) : (barRoot.position === "top" ? parent.height - height - inset : inset)
            z: 50

            Behavior on opacity {
                NumberAnimation {
                    duration: 120
                    easing.type: Easing.OutCubic
                }
            }
        }

        // Press-drag to reorder. Declared last so it is above the widget: it
        // takes the left press before any handler under it, which is why a
        // click that did not become a drag is dispatched back through the
        // bar's click-target registry. Right and middle buttons are not
        // accepted here and reach the widget's own handlers untouched.
        //
        // drag.target is deliberately unset: the slot is owned by a Row, and
        // mutating slot.x can leave stale offsets that overlap neighbours
        // after a small aborted drag.
        MouseArea {
            id: slotPointer

            property bool dragging: false
            property bool suppressClick: false
            property real pressedX: 0
            property real pressedY: 0
            readonly property real dragThreshold: 4

            anchors.fill: parent
            acceptedButtons: Qt.LeftButton
            enabled: slot.visible && slot.width > 0 && slot.height > 0
            propagateComposedEvents: true

            onPressed: mouse => {
                dragging = false;
                suppressClick = false;
                pressedX = mouse.x;
                pressedY = mouse.y;
                barRoot.clearDrag();
            }

            onPositionChanged: mouse => {
                if (!(mouse.buttons & Qt.LeftButton))
                    return;
                if (Math.abs(mouse.x - pressedX) + Math.abs(mouse.y - pressedY) >= dragThreshold) {
                    if (!dragging) {
                        barRoot.dragWindow = slot.barWindow;
                        barRoot.dragScreen = slot.barWindow.screen;
                        barRoot.dragOffsetX = pressedX;
                        barRoot.dragOffsetY = pressedY;
                        barRoot.captureDragGhost(slot);
                        barRoot.dragSource = slot;
                    }
                    dragging = true;
                    slot.barWindow.clearTooltip();
                }

                if (dragging) {
                    const scenePoint = slot.mapToItem(null, mouse.x, mouse.y);
                    const screenPoint = slot.barWindow.windowScreenPoint(scenePoint);
                    barRoot.dragScreenX = screenPoint.x;
                    barRoot.dragScreenY = screenPoint.y;

                    const drop = slot.barWindow.moduleDropAtScene(scenePoint, slot);
                    barRoot.dropTarget = drop ? drop.slot : null;
                    barRoot.dropAfter = drop ? drop.after : false;
                    barRoot.dropMarkerGeometry = drop ? slot.barWindow.dropMarkerRect(drop.slot, drop.after) : null;
                }
            }

            onReleased: mouse => {
                const wasDragging = dragging;
                const targetSlot = barRoot.dropTarget;
                const afterTarget = barRoot.dropAfter;

                if (wasDragging)
                    suppressClick = true;
                dragging = false;
                barRoot.clearDrag();

                if (wasDragging && targetSlot) {
                    slot.barWindow.dropAtTarget(slot, targetSlot, afterTarget);
                    mouse.accepted = true;
                } else if (!wasDragging) {
                    mouse.accepted = false;
                }
            }

            onCanceled: {
                dragging = false;
                suppressClick = false;
                barRoot.clearDrag();
            }

            onClicked: mouse => {
                if (suppressClick) {
                    suppressClick = false;
                    mouse.accepted = true;
                    return;
                }
                if (!slot.barWindow.pressModuleClickTarget(slot, mouse.button, mouse.x, mouse.y))
                    mouse.accepted = false;
            }
        }
    }

    // ----------------------------------------------------- widget components
    Component {
        id: launcherComponent
        LauncherButton {
            theme: barRoot.theme
            shell: barRoot.shell
        }
    }

    Component {
        id: workspacesComponent
        Workspaces {
            theme: barRoot.theme
            niri: barRoot.niri
        }
    }

    Component {
        id: clockComponent
        Clock {
            theme: barRoot.theme
        }
    }

    Component {
        id: windowComponent
        ActiveWindow {
            theme: barRoot.theme
            niri: barRoot.niri
        }
    }

    Component {
        id: audioComponent
        AudioWidget {
            theme: barRoot.theme
            audio: barRoot.shell.audio
        }
    }

    Component {
        id: micComponent
        Mic {
            theme: barRoot.theme
            audio: barRoot.shell.audio
        }
    }

    Component {
        id: networkComponent
        NetworkWidget {
            theme: barRoot.theme
        }
    }

    Component {
        id: bluetoothComponent
        BluetoothWidget {
            theme: barRoot.theme
        }
    }

    Component {
        id: batteryComponent
        Battery {
            theme: barRoot.theme
        }
    }

    Component {
        id: mediaComponent
        Media {
            theme: barRoot.theme
        }
    }

    Component {
        id: kbComponent
        KeyboardLayout {
            theme: barRoot.theme
            niri: barRoot.niri
        }
    }

    Component {
        id: trayComponent
        Tray {
            theme: barRoot.theme
        }
    }

    Component {
        id: updateComponent
        SystemUpdate {
            theme: barRoot.theme
        }
    }

    Component {
        id: indicatorsComponent
        Indicators {
            theme: barRoot.theme
            shell: barRoot.shell
        }
    }

    Component {
        id: dndComponent
        Dnd {
            theme: barRoot.theme
            notifs: barRoot.shell.notifs
        }
    }

    Component {
        id: dictationComponent
        Dictation {
            theme: barRoot.theme
        }
    }

    Component {
        id: stayAwakeComponent
        StayAwake {
            theme: barRoot.theme
            idle: barRoot.shell.idle
        }
    }

    Component {
        id: nightLightComponent
        NightLight {
            theme: barRoot.theme
            nightlight: barRoot.shell.nightlight
        }
    }

    Component {
        id: screenRecordingComponent
        ScreenRecording {
            theme: barRoot.theme
            shell: barRoot.shell
        }
    }

    Component {
        id: reminderComponent
        Reminder {
            theme: barRoot.theme
            shell: barRoot.shell
        }
    }

    Component {
        id: aiComponent
        Ai {
            theme: barRoot.theme
        }
    }

    Component {
        id: weatherComponent
        Weather {
            theme: barRoot.theme
        }
    }

    Component {
        id: monitorComponent
        MonitorWidget {
            theme: barRoot.theme
            shell: barRoot.shell
        }
    }

    Component {
        id: dropboxComponent
        Dropbox {
            theme: barRoot.theme
        }
    }

    Component {
        id: tailscaleComponent
        Tailscale {
            theme: barRoot.theme
        }
    }

    Component {
        id: spacerComponent
        Spacer {
            theme: barRoot.theme
        }
    }

    Component {
        id: missingComponent
        Item {
            property string missingId: "?"
            implicitWidth: barRoot.vertical ? barRoot.barSize : missingLabel.implicitWidth + barRoot.theme.space(2)
            implicitHeight: barRoot.vertical ? missingLabel.implicitHeight + barRoot.theme.space(2) : (parent ? parent.height : missingLabel.implicitHeight)
            Text {
                id: missingLabel
                anchors.centerIn: parent
                color: barRoot.theme.error
                font.family: barRoot.theme.fontMono
                font.pixelSize: barRoot.theme.fontPx(0.917)
                text: "[" + parent.missingId + "?]"
            }
        }
    }
}
