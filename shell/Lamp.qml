import QtQuick
import QtQuick.Effects
import "lib/hifi.mjs" as H

// A round pilot lamp in Hi-Fi's dress; a lit, red or green lamp glows in its own colour.
Item {
    id: lamp

    property var tokens: null
    // lit, unlit, red or green; Item already owns state.
    property string light: "unlit"
    property int size: 6
    readonly property var look: tokens ? H.lamp(tokens, light, size) : ({ size: size, color: "transparent", glow: "transparent" })

    width: size
    height: size

    Loader {
        active: lamp.look.glow !== "transparent"
        anchors.fill: parent
        sourceComponent: RectangularShadow {
            blur: lamp.size * 1.2
            radius: lamp.size / 2
            color: Qt.alpha(lamp.look.glow, 0.7)
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: lamp.size / 2
        color: lamp.look.color
    }
}
