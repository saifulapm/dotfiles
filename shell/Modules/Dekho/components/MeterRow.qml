import QtQuick

// omakade's achievement progress row: a name on the left, a figure on the right
// in the accent, and a rounded track under both. Here it is how far into a
// title you are, and how well a swarm is feeding mpv — the two things in this
// module that are a fraction of something.
Column {
    id: meter

    required property var style
    required property string label
    // 0..1, clamped by the fill.
    required property real value
    // What the right-hand figure says. A percentage for a resume point, a rate
    // for a swarm — the caller has the units, this does not.
    property string valueText: Math.round(Math.max(0, Math.min(1, meter.value)) * 100) + "%"
    property color fillColor: style.accent

    spacing: style.ui(9)

    Item {
        width: parent.width
        height: Math.max(nameText.implicitHeight, figureText.implicitHeight)

        Text {
            id: nameText

            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: meter.label
            color: meter.style.fg
            font.family: meter.style.fontFamily
            font.pixelSize: meter.style.type(11)
            font.weight: Font.DemiBold
        }

        Text {
            id: figureText

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            text: meter.valueText
            color: meter.fillColor
            font.family: meter.style.fontFamily
            font.pixelSize: meter.style.type(11)
            font.weight: Font.DemiBold
        }
    }

    Rectangle {
        width: parent.width
        height: meter.style.ui(5)
        radius: height / 2
        color: meter.style.alpha(meter.style.fg, 0.1)

        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, meter.value))
            height: parent.height
            radius: parent.radius
            color: meter.fillColor

            Behavior on width {
                NumberAnimation {
                    duration: meter.style.normal
                    easing.type: meter.style.easing
                }
            }
        }
    }
}
