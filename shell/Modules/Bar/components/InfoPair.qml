import QtQuick

// Label left, value right on one line. `copyValue` adds the click-to-copy
// affordance (the consumer decides what "copy" means via copyRequested).
Item {
    id: infoPair

    required property var theme
    property string label: ""
    property string value: ""
    property string copyValue: ""
    property color labelColor: theme.textPrimary
    property real labelOpacity: 0.6
    property color valueColor: theme.textPrimary

    signal copyRequested(string copyValue)

    width: parent ? parent.width : 0
    implicitHeight: visible ? Math.max(infoLabel.implicitHeight, infoValue.implicitHeight) : 0

    HoverHandler {
        id: infoHover
        enabled: infoPair.copyValue !== ""
        cursorShape: Qt.PointingHandCursor
    }

    TapHandler {
        enabled: infoPair.copyValue !== ""
        onTapped: infoPair.copyRequested(infoPair.copyValue)
    }

    PanelHint {
        theme: infoPair.theme
        visible: infoHover.hovered
        anchor: infoPair
        text: "Copy"
    }

    Text {
        id: infoLabel
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: infoPair.label
        color: infoPair.labelColor
        opacity: infoPair.labelOpacity
        font.family: infoPair.theme.fontUi
        font.pixelSize: infoPair.theme.fontPx(0.833)
    }

    Text {
        id: infoValue
        anchors.right: parent.right
        anchors.left: infoLabel.right
        anchors.leftMargin: infoPair.theme.space(2)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: infoPair.value
        color: infoPair.valueColor
        font.family: infoPair.theme.fontMono
        font.pixelSize: infoPair.theme.fontPx(0.833)
    }
}
