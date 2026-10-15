import QtQuick
import "../components"
import "../../../components"
import "RouteModel.js" as Model

// Route: where the workflow hub sends its questions, as one bar button. A
// phone mark while they go to the phone, a monitor mark while they go to a
// device, and the waiting count beside it in the accent while any wait. The mark draws only what
// the agent's route file says; with no file it hides.
//
// Left click opens the panel with the three choices.
BarButton {
    id: rootItem

    // A fixed slot for the mark alone; with a count beside it the row sizes
    // the button.
    fixedWidth: vertical || badgeText !== "" ? -1 : 27
    fixedHeight: vertical ? 27 : -1

    // The shared service, injected by the bar's registry.
    required property RouteService route

    readonly property string badgeText: Model.badge(route.state)

    visible: Model.visible(route.state)
    tooltipText: "Questions: " + (route.state.route === "device" ? "Device" : route.state.route === "dulali" ? "Dulali" : "Phone") + ", " + Model.waitingLine(route.state)

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
    }

    // The waiting count beside the mark, at the bar's own small size: a
    // corner pill at this scale is too small to read.
    StyledText {
        theme: rootItem.theme
        role: StyledText.Small
        mono: true

        anchors.verticalCenter: parent.verticalCenter
        visible: rootItem.badgeText !== "" && !rootItem.vertical
        text: rootItem.badgeText
        color: rootItem.theme.accent
    }

    PanelLoader {
        id: panelLoader
    }
}
