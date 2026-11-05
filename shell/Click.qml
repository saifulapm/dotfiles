import QtQuick

// What a click acts on, on every surface and App: the pointing hand over it and nothing drawn on hover, so a resting pointer never moves a selection; a click runs tapped, which does what Enter does there.
MouseArea {
    // The name a check finds it by through `dekho box` or `shell box`.
    property string name: ""

    signal tapped

    objectName: "click:" + name
    anchors.fill: parent
    cursorShape: Qt.PointingHandCursor
    onClicked: tapped()
}
