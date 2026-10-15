import QtQuick
import "../components"
import "../../../components"
import "RouteModel.js" as Model

// Route: where the workflow hub sends its questions, as one bar button. A
// phone mark while they go to the phone, a monitor mark while they go to a
// device, and an accent count badge while any wait. The mark draws only what
// the agent's route file says; with no file it hides.
//
// Left click opens the panel with the two choices.
BarButton {
    id: rootItem

    fixedWidth: vertical ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // The shared service, injected by the bar's registry.
    required property RouteService route

    readonly property string badgeText: Model.badge(route.state)

    visible: Model.visible(route.state)
    tooltipText: "Questions: " + (route.state.route === "device" ? "Device" : "Phone") + ", " + Model.waitingLine(route.state)

    onTapped: {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("RoutePanel.qml", {
                theme: rootItem.theme,
                route: rootItem.route
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    Item {
        implicitWidth: 13
        implicitHeight: 13

        OpticalGlyph {
            anchors.centerIn: parent
            text: Model.glyph(rootItem.route.state)
            pixelSize: 13
            verticalInkCenter: true
            color: rootItem.barFg
            colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
        }

        // HubSync's corner badge, carrying the waiting count in the accent.
        Rectangle {
            id: badge

            visible: rootItem.badgeText !== ""
            width: Math.max(height, badgeLabel.implicitWidth + 3)
            height: Math.max(7, parent.height * 0.42)
            radius: height / 2
            color: rootItem.theme.accent
            border.width: 1
            border.color: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
            anchors.right: parent.right
            anchors.bottom: parent.bottom

            Text {
                id: badgeLabel
                textFormat: Text.PlainText
                anchors.centerIn: parent
                text: rootItem.badgeText
                color: rootItem.bar ? rootItem.bar.barBackground : rootItem.theme.surface1
                font.family: rootItem.theme.fontUi
                font.pixelSize: Math.max(6, badge.height * 0.72)
                font.bold: true
            }
        }
    }

    PanelLoader {
        id: panelLoader
    }
}
