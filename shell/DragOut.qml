import QtQuick

// What drags out of the shell to another window: a press moved past the drag threshold hands mime to the platform's drag as a copy; a press released short of it is a click, which the user of this area handles in onClicked.
MouseArea {
    id: area

    // The name a check finds it by through `shell box`, as a Click's.
    property string name: ""
    // The formats the drag carries, as {type: data}.
    property var mime: ({})
    // Whether this press may start a drag at all.
    property bool offering: true
    // The picture under the pointer while it drags, or "" for none.
    property url image: ""
    // True from a drag's start to its drop. Drag.active falls as the platform drag takes the pointer, so its start and finish set this.
    property bool dragging: false

    objectName: "click:" + name
    drag.target: offer

    Item {
        id: offer
        Drag.active: area.drag.active && area.offering
        Drag.dragType: Drag.Automatic
        Drag.supportedActions: Qt.CopyAction
        Drag.mimeData: area.mime
        Drag.imageSource: area.image
        Drag.hotSpot.x: -14
        Drag.hotSpot.y: -18
        Drag.onDragStarted: area.dragging = true
        Drag.onDragFinished: area.dragging = false
    }
}
