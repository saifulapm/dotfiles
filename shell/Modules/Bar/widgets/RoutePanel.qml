import QtQuick
import "../components"
import "../../../components"
import "RouteModel.js" as Model

// Route panel: where the workflow hub sends its questions. Three choices, Phone,
// this Device and Dulali, with the current one marked; when another machine holds
// Device the hero says which. A click runs `workflow route <choice>` and the
// marking follows the agent's next write of the route file, not the click.
BarPanel {
    id: panel

    required property var route

    readonly property var state: panel.route.state
    readonly property string current: Model.currentChoice(state, panel.route.machine)

    panelTitle: ""
    cardWidth: theme.space(70)

    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "Question route"
        meta: panel.current === "phone" ? "Questions go to Phone" : panel.current === "dulali" ? "Questions go to Dulali" : (panel.current === "elsewhere" ? "Questions go to " + Model.elsewhereLabel(panel.state, panel.route.machine) : "Questions go to " + Model.deviceLabel(panel.state, panel.route.machine))
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0

        icon: OpticalGlyph {
            text: Model.glyph(panel.state)
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.theme.textPrimary
        }
    }

    Row {
        spacing: panel.theme.space(1.5)

        PanelButton {
            theme: panel.theme
            label: "Phone"
            selected: panel.current === "phone"
            enabled: !panel.route.routeProcess.running
            onClicked: panel.route.setRoute("phone")
        }

        PanelButton {
            theme: panel.theme
            label: Model.deviceLabel(panel.state, panel.route.machine)
            selected: panel.current === "device"
            enabled: !panel.route.routeProcess.running
            onClicked: panel.route.setRoute("device")
        }

        PanelButton {
            theme: panel.theme
            label: "Dulali"
            selected: panel.current === "dulali"
            enabled: !panel.route.routeProcess.running
            onClicked: panel.route.setRoute("dulali")
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small
        visible: panel.route.lastError !== ""
        width: parent.width
        text: panel.route.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
    }

    Item {
        width: parent.width
        implicitHeight: hubButton.implicitHeight

        StyledText {
            theme: panel.theme
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: Model.waitingLine(panel.route.waiting)
        }

        PanelButton {
            id: hubButton
            theme: panel.theme
            anchors.right: parent.right
            label: "open hub"
            enabled: Model.hubUrl(panel.state) !== ""
            onClicked: panel.route.openHub()
        }
    }
}
