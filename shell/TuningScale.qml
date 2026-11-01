import QtQuick
import "lib/hifi.mjs" as H

// A receiver's tuning scale along a glass display's bottom edge: amber ticks, the long ones every 40 px, and a red pointer.
Item {
    id: tuning

    property var tokens: null
    // Where the pointer stands, from 0 at the left to 1 at the right.
    property real at: 0.5
    readonly property var marks: tokens ? H.tuningScale(tokens, width, at) : ({ ticks: [], pointer: { x: 0, width: 0, color: "transparent" } })

    height: 10

    Repeater {
        model: tuning.marks.ticks

        Rectangle {
            required property var modelData
            x: modelData.x
            y: tuning.height - height
            width: 1
            height: modelData.major ? 8 : 4
            color: modelData.color
        }
    }

    Rectangle {
        x: tuning.marks.pointer.x
        width: tuning.marks.pointer.width
        height: tuning.height
        color: tuning.marks.pointer.color
    }
}
