import QtQuick
import Quickshell
import "widgets"

// The bar. The only module instantiated at startup — everything else is
// LazyLoader-gated and summoned by IPC.
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

    // ------------------------------------------------------ widget registry
    readonly property var registry: ({
            "workspaces": workspacesComponent,
            "clock": clockComponent,
            "window": windowComponent
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
            color: barRoot.theme.surface0

            Row {
                anchors.left: parent.left
                anchors.leftMargin: barRoot.theme.space(2)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: barRoot.theme.space(2)
                Repeater {
                    model: barRoot.layoutOf.left
                    WidgetSlot {}
                }
            }

            Row {
                anchors.centerIn: parent
                spacing: barRoot.theme.space(2)
                Repeater {
                    model: barRoot.layoutOf.center
                    WidgetSlot {}
                }
            }

            Row {
                anchors.right: parent.right
                anchors.rightMargin: barRoot.theme.space(2)
                anchors.top: parent.top
                anchors.bottom: parent.bottom
                spacing: barRoot.theme.space(2)
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
        sourceComponent: known !== undefined ? known : missingComponent
        onLoaded: {
            if ("screenName" in item)
                item.screenName = panel.screen.name;
            if (known === undefined) {
                item.missingId = widgetId;
                console.warn("Bar: unknown widget id in config:", widgetId);
            }
        }
    }

    // ----------------------------------------------------- widget components
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
