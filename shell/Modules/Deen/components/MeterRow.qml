import QtQuick

// Dekho's progress row, itself omakade's achievement meter: a name on the left,
// a figure on the right in the accent, and a rounded track under both.
//
// A recitation verdict is a fraction of something — "24 of 29 words" — and it
// was a bare sentence in a Label. A bar states the same thing at a glance and,
// more usefully, states it in a colour: the fill carries the verdict, so a poor
// recitation reads as poor before you have read the number.
Column {
    id: meter

    required property var style
    required property string label
    // 0..1, clamped by the fill.
    required property real value
    // What the right-hand figure says. The caller has the units, this does not.
    property string valueText: Math.round(Math.max(0, Math.min(1, meter.value)) * 100) + "%"
    property color fillColor: style.accent

    spacing: style.ui(9)

    Item {
        width: parent.width
        height: Math.max(nameText.implicitHeight, figureText.implicitHeight)

        Text {
            id: nameText
            textFormat: Text.PlainText

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
            textFormat: Text.PlainText

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
