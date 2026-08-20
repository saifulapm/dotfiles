import QtQuick

// Label left, value right on one line. `copyValue` adds the click-to-copy
// affordance (the consumer decides what "copy" means via copyRequested).
Item {
    id: infoPair

    required property var theme
    property string label: ""
    property string value: ""
    property string copyValue: ""
    // Off by default: the pair is Small, the role every bar panel measured it
    // at. The Dekho hub declares its own screen-scaled type (its `fonts`
    // object) because StyledText's roles top out at bar-and-panel sizes, and a
    // 10 px facts block inside 73 px hero type reads as a rendering fault —
    // the same reason PlaybackView draws its own section caption instead of
    // using SectionHeader. One knob, so the pair keeps one implementation.
    property int pixelSize: 0
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
        // roleScale, not a repeated 0.833: the override changes the size, not
        // which step of the scale this is.
        font.pixelSize: infoPair.pixelSize > 0 ? infoPair.pixelSize : infoPair.theme.fontPx(roleScale)
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
        font.pixelSize: infoPair.pixelSize > 0 ? infoPair.pixelSize : infoPair.theme.fontPx(roleScale)
        mono: true
        color: infoPair.valueColor
    }
}
