import QtQuick

// What a click acts on in Dekho: the pointing hand over it and nothing drawn on hover; a click runs tapped, which does what Enter does there.
MouseArea {
    // The name a check finds it by through `dekho box`.
    property string name: ""

    signal tapped

    objectName: "click:" + name
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: tapped()
}
