import QtQuick
import Quickshell
import "widgets"

// The bar, styled 100% after omarchy's: theme background surface, foreground
// text (colors.toml `foreground`, i.e. our ansi.white — not bright), zero
// spacing between widgets (each owns its margins), 8 px section insets,
// chrome-less buttons, red attention color, 420 ms color transitions on
// theme swap, and the clock pinned dead-center with neighbors flanking it.
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

    // Repeater models hold only the id strings, and keep their identity while
    // the id sequence is unchanged — so a settings write (which replaces the
    // whole config object) updates live widgets in place instead of
    // recreating them. Recreating would destroy the very panel the settings
    // were just edited from. The center split (omarchy's centerAnchor: the
    // clock pinned dead-center, neighbors flanking it) is computed in the
    // same pass — deriving it from separate reactive properties left a
    // transient evaluation where the flanking rows still contained the
    // clock, instantiating it twice.
    property var modelLeft: []
    property var modelRight: []
    property var modelCenterBefore: []
    property var modelCenterAfter: []
    property int centerAnchorIndex: -1

    onLayoutOfChanged: syncModels()
    Component.onCompleted: syncModels()

    function sameIds(a, b) {
        return a.join("\u001f") === b.join("\u001f");
    }

    function syncModels() {
        const leftIds = layoutOf.left.map(e => e.id);
        const centerIds = layoutOf.center.map(e => e.id);
        const rightIds = layoutOf.right.map(e => e.id);
        const anchor = centerIds.indexOf("clock");
        const before = anchor >= 0 ? centerIds.slice(0, anchor) : [];
        const after = anchor >= 0 ? centerIds.slice(anchor + 1) : centerIds;
        centerAnchorIndex = anchor;
        if (!sameIds(leftIds, modelLeft))
            modelLeft = leftIds;
        if (!sameIds(rightIds, modelRight))
            modelRight = rightIds;
        if (!sameIds(before, modelCenterBefore))
            modelCenterBefore = before;
        if (!sameIds(after, modelCenterAfter))
            modelCenterAfter = after;
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
            "reminder": reminderComponent,
            "stayawake": stayAwakeComponent,
            "ai": aiComponent,
            "weather": weatherComponent,
            "monitor": monitorComponent,
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

            // Cold-start metric consumed by bin/bench: ms from process launch
            // to this bar window finishing construction.
            Component.onCompleted: console.info("bench:first-bar", Date.now() - Quickshell.launchTime.getTime(), "ms")

            screen: modelData
            anchors {
                top: String(barRoot.config.position) !== "bottom"
                bottom: String(barRoot.config.position) === "bottom"
                left: true
                right: true
            }
            implicitHeight: barRoot.theme.barHeight

            // Omarchy bar palette: background = theme background, text =
            // theme foreground (our ansi.white), attention = red. 420 ms
            // InOutCubic transitions carry theme swaps.
            property color barBackground: barRoot.theme.surface1
            property color barForeground: barRoot.theme.col("ansi.white")

            color: barBackground
            Behavior on barBackground {
                ColorAnimation {
                    duration: 420
                    easing.type: Easing.InOutCubic
                }
            }
            Behavior on barForeground {
                ColorAnimation {
                    duration: 420
                    easing.type: Easing.InOutCubic
                }
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

            // Declared first so it sits under every widget; a HoverHandler
            // observes without consuming, so nothing above it is affected.
            Item {
                anchors.fill: parent
                HoverHandler {
                    onHoveredChanged: panel.setCenterSectionHovered(hovered)
                }
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
                        let localX = target.width / 2 - tooltipWindow.implicitWidth / 2;
                        let localY = target.height + 6;
                        if (String(barRoot.config.position) === "bottom")
                            localY = -tooltipWindow.implicitHeight - 6;
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
                    color: barRoot.theme.alpha(panel.barBackground, 0.97)
                    border.width: 1
                    border.color: panel.barForeground

                    Text {
                        id: tooltipLabel
                        anchors.centerIn: parent
                        text: panel.tooltipText
                        color: panel.barForeground
                        font.family: barRoot.theme.fontMono
                        font.pixelSize: barRoot.theme.fontPx(1.0)
                        horizontalAlignment: Text.AlignHCenter
                    }
                }
            }

            // ------------------------------------------------------ layout
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
                    }
                }
            }

            // Center anchor (the clock) is pinned to the true center.
            WidgetSlot {
                id: centerAnchorSlot
                visible: barRoot.centerAnchorIndex >= 0
                modelData: "clock"
                index: barRoot.centerAnchorIndex
                section: "center"
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
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
                    }
                }
            }
        }
    }

    component WidgetSlot: Loader {
        required property var modelData
        required property int index
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
        readonly property var known: barRoot.registry[widgetId]
        anchors.top: parent ? parent.top : undefined
        anchors.bottom: parent ? parent.bottom : undefined
        width: item ? item.implicitWidth : 0
        sourceComponent: known !== undefined ? known : missingComponent
        onEntryChanged: {
            if (item && "settings" in item)
                item.settings = entry;
        }
        onLoaded: {
            if ("screenName" in item)
                item.screenName = panel.screen.name;
            if ("bar" in item)
                item.bar = panel;
            if ("settings" in item)
                item.settings = entry;
            if (known === undefined) {
                item.missingId = widgetId;
                console.warn("Bar: unknown widget id in config:", widgetId);
            }
            // Dev hook (like QSHELL_DEV): auto-open a widget's panel so
            // headless sessions can verify panel rendering.
            if (Quickshell.env("QSHELL_TEST_PANEL") === widgetId && typeof item.openPanel === "function") {
                const target = item;
                Qt.callLater(() => target.openPanel());
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
        id: stayAwakeComponent
        StayAwake {
            theme: barRoot.theme
            idle: barRoot.shell.idle
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
            implicitWidth: missingLabel.implicitWidth + barRoot.theme.space(2)
            implicitHeight: parent ? parent.height : missingLabel.implicitHeight
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
