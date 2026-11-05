import QtQuick
import "lib/dekho.mjs" as D

// A one-line notice at the window's bottom, drawn in the release card's look at a small size: a rounded card ringed in the accent.
Item {
    id: toast

    required property var dekho

    readonly property var c: dekho.c
    readonly property var fonts: dekho.fonts
    readonly property int pad: 16

    // Shows words on one line, in place of any toast still up, for 2.4 s from now.
    function show(words) {
        label.text = D.title(words);
        hide.restart();
    }

    function state() {
        return {
            text: label.text,
            shown: visible,
            lines: label.lineCount,
            truncated: label.truncated,
            look: {
                radius: fill.radius,
                border: String(fill.border.color),
                accent: String(c.accent),
                ink: String(c.ink)
            }
        };
    }

    visible: hide.running
    width: Math.min(label.implicitWidth, 640 - 2 * pad) + 2 * pad
    height: 36

    Tick {
        id: hide
        interval: 2400
    }

    Rectangle {
        id: fill
        anchors.fill: parent
        radius: 10
        color: toast.c.surface ?? "white"
        border.width: 1.5
        border.color: toast.c.accent ?? "black"
    }

    Text {
        id: label
        anchors.centerIn: parent
        width: toast.width - 2 * toast.pad
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        color: toast.c.ink ?? "black"
        font.family: toast.fonts.ui ?? ""
        font.pixelSize: 13
    }
}
