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
    // 0 to 1: a lamp warming up draws nearer unlit and glows fainter; the bar's lamps follow the theme switch's sweep.
    property real warmth: 1
    readonly property var look: tokens ? H.warmLamp(tokens, light, size, warmth) : ({ size: size, color: "transparent", glow: "transparent" })

    width: size
    height: size

    Loader {
        active: lamp.look.glow !== "transparent"
        anchors.fill: parent
        opacity: lamp.warmth
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
