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

    StyledText {
        id: infoLabel
        theme: infoPair.theme
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: infoPair.label
        role: StyledText.Small
        color: infoPair.labelColor
        opacity: infoPair.labelOpacity
    }

    // The value is mono because it IS one — an IP, a hostname, a byte count.
    StyledText {
        id: infoValue
        theme: infoPair.theme
        anchors.right: parent.right
        anchors.left: infoLabel.right
        anchors.leftMargin: infoPair.theme.space(2)
        anchors.verticalCenter: parent.verticalCenter
        horizontalAlignment: Text.AlignRight
        elide: Text.ElideRight
        text: infoPair.value
        role: StyledText.Small
        mono: true
        color: infoPair.valueColor
    }
}
