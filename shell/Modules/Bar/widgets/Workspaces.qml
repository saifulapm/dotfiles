import QtQuick
import "../components"
import "../../../components"

// Omarchy-style workspaces: the focused one is a filled circle glyph, the
// rest show their number; empty workspaces sit at half strength; urgent
// turns the attention color. 20 px slots, chrome-less.
//
// The Repeater's model is the id sequence only, held back by the sameIds
// guard (Bar.qml's syncModels rule): niri pushes a rebuilt workspaces array
// on every focus event, and feeding that array to the Repeater destroyed and
// rebuilt every delegate per event, per screen (S3). Now a focus change only
// re-resolves each live delegate's `ws` lookup; delegates are created and
// destroyed exactly when membership or order changes.
Item {
    id: rootItem

    required property var theme
    required property var niri
    property var bar: null
    property string screenName: ""

    // Stable delegate model: this screen's workspace ids, in niri's order.
    property var shownIds: []

    function syncShownIds() {
        const ids = [];
        for (const w of niri.workspaces) {
            if (screenName === "" || w.output === screenName)
                ids.push(w.id);
        }
        if (ids.length !== shownIds.length || !ids.every((id, i) => id === shownIds[i]))
            shownIds = ids;
    }

    // The live workspace object for a delegate. Re-evaluated on every niri
    // event (the array binding is what carries the change), null for the
    // beat between a workspace vanishing and its delegate being torn down.
    function workspaceById(id) {
        return niri.workspaces.find(w => w.id === id) || null;
    }

    onScreenNameChanged: syncShownIds()
    Component.onCompleted: syncShownIds()

    Connections {
        target: rootItem.niri
        function onWorkspacesChanged() {
            rootItem.syncShownIds();
        }
    }

    readonly property bool vertical: bar ? bar.vertical === true : false
    readonly property int barSize: bar ? bar.barSize : theme.barHeight

    implicitWidth: bar && bar.vertical === true ? barSize : grid.implicitWidth
    implicitHeight: bar && bar.vertical === true ? grid.implicitHeight : barSize

    // Omarchy's grid: one row of pips on a horizontal bar, one column on a
    // vertical one, with their spacing pair (1 px between columns, 2 px
    // between rows).
    Grid {
        id: grid
        // Filled rather than anchored per orientation: on a horizontal bar the
        // pips take their height from the row that holds them, and on a
        // vertical one they carry their own (see the fixedHeight below), so
        // one anchor set serves both without a size cycle.
        anchors.centerIn: parent
        columns: rootItem.vertical ? 1 : Math.max(1, rootItem.shownIds.length)
        columnSpacing: rootItem.vertical ? 0 : 1
        rowSpacing: rootItem.vertical ? 2 : 0

        Repeater {
            model: rootItem.shownIds

            delegate: BarButton {
                id: wsButton

                // The workspace id; the object behind it lives in `ws`.
                required property var modelData

                readonly property var ws: rootItem.workspaceById(modelData)

                theme: rootItem.theme
                bar: rootItem.bar
                fixedWidth: rootItem.vertical ? -1 : 20
                fixedHeight: rootItem.vertical ? rootItem.barSize : -1
                active: wsButton.ws ? wsButton.ws.is_urgent === true : false
                opacity: !wsButton.ws || wsButton.ws.is_active || wsButton.ws.active_window_id !== null ? 1 : 0.5

                onTapped: rootItem.niri.focusWorkspace(wsButton.modelData)

                OpticalGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: wsButton.ws ? wsButton.ws.is_active === true : false
                    text: "󱓻" // md-circle_medium, omarchy's focused marker
                    color: wsButton.contentColor
                    pixelSize: 13
                    colorAnimationEnabled: !wsButton.bar || wsButton.bar.foregroundAnimationEnabled === true
                }

                StyledText {
                    theme: rootItem.theme
                    role: StyledText.BodyLarge
                    mono: true

                    anchors.verticalCenter: parent.verticalCenter
                    visible: !wsButton.ws || wsButton.ws.is_active !== true
                    text: wsButton.ws ? String(wsButton.ws.name || wsButton.ws.idx) : ""
                    color: wsButton.contentColor
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
