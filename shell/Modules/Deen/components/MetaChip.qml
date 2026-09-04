import QtQuick

// A fact that is not a control: the tajweed legend's four families, and the
// surah's own "6 ayat" and "Meccan".
//
// It is deliberately NOT a disabled GlassButton. A chip that looks pressable
// and is not is worse than a plain label — and this module has real chips
// beside these, so the two have to be told apart at a glance: no hover, no
// focus ring, and a rest colour a step quieter than a button's 0.045.
Rectangle {
    id: chip

    required property var style
    required property string text
    // Unset leaves the dot out entirely, which is what the plain facts want.
    property color dotColor: "transparent"
    readonly property bool hasDot: chip.dotColor.a > 0

    implicitWidth: label.implicitWidth + style.ui(20) + (chip.hasDot ? style.ui(15) : 0)
    implicitHeight: style.rowControl
    radius: height / 2
    color: style.alpha(style.fg, 0.05)
    border.width: style.hairline
    border.color: style.alpha(style.fg, 0.1)

    Row {
        anchors.centerIn: parent
        spacing: chip.style.ui(6)

        Rectangle {
            anchors.verticalCenter: parent.verticalCenter
            visible: chip.hasDot
            width: chip.style.ui(9)
            height: width
            radius: width / 2
            color: chip.dotColor
        }

        Text {
            id: label
            textFormat: Text.PlainText

            anchors.verticalCenter: parent.verticalCenter
            text: chip.text
            color: chip.style.muted
            font.family: chip.style.fontFamily
            font.pixelSize: chip.style.type(10)
            font.weight: Font.Medium
        }
    }
}
