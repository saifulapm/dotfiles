import QtQuick
import "../components"

// Omarchy-style workspaces: the focused one is a filled circle glyph, the
// rest show their number; empty workspaces sit at half strength; urgent
// turns the attention color. 20 px slots, chrome-less.
Item {
    id: rootItem

    required property var theme
    required property var niri
    property var bar: null
    property string screenName: ""

    readonly property var shown: niri.workspaces.filter(w => screenName === "" || w.output === screenName)

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
        columns: rootItem.vertical ? 1 : Math.max(1, rootItem.shown.length)
        columnSpacing: rootItem.vertical ? 0 : 1
        rowSpacing: rootItem.vertical ? 2 : 0

        Repeater {
            model: rootItem.shown

            delegate: BarButton {
                id: wsButton

                required property var modelData

                theme: rootItem.theme
                bar: rootItem.bar
                fixedWidth: rootItem.vertical ? -1 : 20
                fixedHeight: rootItem.vertical ? rootItem.barSize : -1
                active: modelData.is_urgent === true
                opacity: modelData.is_active || modelData.active_window_id !== null ? 1 : 0.5

                onTapped: rootItem.niri.focusWorkspace(wsButton.modelData.id)

                OpticalGlyph {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: wsButton.modelData.is_active === true
                    text: "󱓻" // md-circle_medium, omarchy's focused marker
                    color: wsButton.contentColor
                    pixelSize: 13
                }

                Text {
                    anchors.verticalCenter: parent.verticalCenter
                    visible: wsButton.modelData.is_active !== true
                    text: wsButton.modelData.name || wsButton.modelData.idx
                    color: wsButton.contentColor
                    font.family: rootItem.theme.fontMono
                    font.pixelSize: rootItem.theme.fontPx(1.0)
                    renderType: Text.NativeRendering
                }
            }
        }
    }
}
