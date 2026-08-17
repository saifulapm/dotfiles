import QtQuick

// The UPPERCASE letter-spaced caption over a panel section, with an optional
// right-aligned value ("OUTPUT ... 65%"). One shared copy of the header every
// ported panel used to declare privately; the value column's color and
// tracking stay per-site so extraction changes no pixels.
Item {
    id: header

    required property var theme
    property string label: ""
    property string value: ""
    property bool dimmed: false
    property color valueColor: theme.textPrimary
    property real valueSpacing: 0

    implicitHeight: Math.max(headerLabel.implicitHeight, headerValue.implicitHeight) + theme.space(1)

    StyledText {
        id: headerLabel
        theme: header.theme
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        text: header.label
        role: StyledText.Caption
        mono: true
        muted: true
        font.letterSpacing: 1.2
        font.weight: Font.DemiBold
    }

    StyledText {
        id: headerValue
        theme: header.theme
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        text: header.value
        visible: text !== ""
        opacity: header.dimmed ? 0.5 : 1
        role: StyledText.Caption
        mono: true
        color: header.valueColor
        font.letterSpacing: header.valueSpacing
        font.weight: Font.DemiBold
    }
}
