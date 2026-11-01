import QtQuick
import "lib/hifi.mjs" as H

// A glass display in Hi-Fi's dress: the glass fill in a 1 px line frame, under a 1 px highlight of ink.
Rectangle {
    id: glass

    property var tokens: null
    readonly property var look: tokens ? H.glass(tokens) : null

    color: look ? look.fill : "transparent"
    border.width: look ? look.borderWidth : 0
    border.color: look ? look.border : "transparent"

    Rectangle {
        x: glass.border.width
        y: glass.border.width
        width: glass.width - 2 * glass.border.width
        height: 1
        color: glass.look ? glass.look.highlight : "transparent"
    }
}
