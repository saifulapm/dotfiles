import QtQuick
import Quickshell.Services.SystemTray
import "../components"

// StatusNotifier tray, omarchy-sized: 27 px slots, image icons at 12 px
// with crisp sourceSize. Left click activates (or opens the menu for
// menu-only items), right click opens the menu, middle click
// secondary-activates, wheel scrolls. Passive items are hidden.
Item {
    id: rootItem

    required property var theme
    property var bar: null

    readonly property var shownItems: SystemTray.items.values.filter(i => i.status !== Status.Passive)

    implicitWidth: row.implicitWidth
    implicitHeight: parent ? parent.height : row.implicitHeight
    visible: shownItems.length > 0

    Row {
        id: row
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        spacing: 0

        Repeater {
            model: rootItem.shownItems

            delegate: BarButton {
                id: itemButton

                required property var modelData

                theme: rootItem.theme
                bar: rootItem.bar
                fixedWidth: 27
                tooltipText: modelData.tooltipTitle || modelData.title || modelData.id

                onTapped: button => {
                    if (button === Qt.LeftButton) {
                        if (modelData.onlyMenu)
                            itemButton.openMenu();
                        else
                            modelData.activate();
                    } else if (button === Qt.MiddleButton) {
                        modelData.secondaryActivate();
                    } else if (button === Qt.RightButton) {
                        itemButton.openMenu();
                    }
                }

                onWheelMoved: delta => modelData.scroll(delta, false)

                function openMenu() {
                    if (!modelData.hasMenu || !rootItem.bar)
                        return;
                    const point = itemButton.mapToItem(rootItem.bar.contentItem, 0, itemButton.height);
                    modelData.display(rootItem.bar, Math.round(point.x), Math.round(point.y));
                }

                Image {
                    anchors.verticalCenter: parent.verticalCenter
                    width: 12
                    height: 12
                    source: itemButton.modelData.icon
                    sourceSize.width: width * (Screen.devicePixelRatio || 1)
                    sourceSize.height: height * (Screen.devicePixelRatio || 1)
                    fillMode: Image.PreserveAspectFit
                }
            }
        }
    }
}
