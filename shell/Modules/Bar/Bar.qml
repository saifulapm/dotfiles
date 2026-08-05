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

    readonly property var layoutOf: ({
            left: Array.isArray(config.left) ? config.left : [],
            center: Array.isArray(config.center) ? config.center : [],
            right: Array.isArray(config.right) ? config.right : []
        })

    // The clock anchors the center section like omarchy's centerAnchor:
    // widgets before it lay out leftward, widgets after it rightward, and
    // the clock itself never moves off dead-center.
    readonly property int centerAnchorIndex: layoutOf.center.indexOf("clock")
    readonly property var centerBefore: centerAnchorIndex >= 0 ? layoutOf.center.slice(0, centerAnchorIndex) : []
    readonly property var centerAfter: centerAnchorIndex >= 0 ? layoutOf.center.slice(centerAnchorIndex + 1) : layoutOf.center

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
            "dnd": dndComponent,
            "spacer": spacerComponent
        })

    Variants {
        model: Quickshell.screens

        delegate: PanelWindow {
            id: panel

            required property var modelData

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
                    model: barRoot.layoutOf.left
                    WidgetSlot {}
                }
            }

            // Center anchor (the clock) is pinned to the true center.
            WidgetSlot {
                id: centerAnchorSlot
                visible: barRoot.centerAnchorIndex >= 0
                modelData: "clock"
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
                    model: barRoot.centerBefore
                    WidgetSlot {}
                }
            }

            Row {
                anchors.left: barRoot.centerAnchorIndex >= 0 ? centerAnchorSlot.right : undefined
                anchors.horizontalCenter: barRoot.centerAnchorIndex >= 0 ? undefined : parent.horizontalCenter
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 0
                Repeater {
                    model: barRoot.centerAfter
                    WidgetSlot {}
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: 8
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: 0
                Repeater {
                    model: barRoot.layoutOf.right
                    WidgetSlot {}
                }
            }
        }
    }

    component WidgetSlot: Loader {
        required property var modelData
        readonly property string widgetId: String(modelData)
        readonly property var known: barRoot.registry[widgetId]
        anchors.top: parent ? parent.top : undefined
        anchors.bottom: parent ? parent.bottom : undefined
        width: item ? item.implicitWidth : 0
        sourceComponent: known !== undefined ? known : missingComponent
        onLoaded: {
            if ("screenName" in item)
                item.screenName = panel.screen.name;
            if ("bar" in item)
                item.bar = panel;
            if (known === undefined) {
                item.missingId = widgetId;
                console.warn("Bar: unknown widget id in config:", widgetId);
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
        id: dndComponent
        Dnd {
            theme: barRoot.theme
            notifs: barRoot.shell.notifs
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
