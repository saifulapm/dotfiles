import QtQuick
import QtQuick.Shapes
import "lib/dekho.mjs" as D

// A one-line notice at the window's bottom, drawn in the release card's look at a small size: Paper's hard shadow, Artboard's rounded card ringed in its accent, Blueprint's cut corners.
Item {
    id: toast

    required property var dekho

    readonly property var c: dekho.c
    readonly property var fonts: dekho.fonts
    readonly property string voice: dekho.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property bool caps: voice === "caps"
    readonly property int pad: bracket ? 18 : 16
    readonly property int cut: 8

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
                shadow: hardShadow.visible,
                chamfer: chamfer.visible,
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
        id: hardShadow
        x: 4
        y: 4
        width: parent.width
        height: parent.height
        visible: toast.caps
        color: toast.c.ink ?? "black"
    }
    Rectangle {
        id: fill
        anchors.fill: parent
        visible: !toast.bracket
        radius: toast.plain ? 10 : 0
        color: toast.c.surface ?? "white"
        border.width: 1.5
        border.color: (toast.plain ? toast.c.accent : toast.c.ink) ?? "black"
    }
    Shape {
        id: chamfer
        anchors.fill: parent
        visible: toast.bracket
        preferredRendererType: Shape.GeometryRenderer

        ShapePath {
            strokeColor: toast.c.accent ?? "cyan"
            strokeWidth: 1
            fillColor: toast.c.surface ?? "black"
            PathPolyline {
                path: [Qt.point(toast.cut + 0.5, 0.5), Qt.point(toast.width - 0.5, 0.5), Qt.point(toast.width - 0.5, toast.height - toast.cut - 0.5), Qt.point(toast.width - toast.cut - 0.5, toast.height - 0.5), Qt.point(0.5, toast.height - 0.5), Qt.point(0.5, toast.cut + 0.5), Qt.point(toast.cut + 0.5, 0.5)]
            }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        width: toast.width - 2 * toast.pad
        textFormat: Text.PlainText
        elide: Text.ElideRight
        maximumLineCount: 1
        color: toast.c.ink ?? "black"
        font.family: (toast.bracket ? toast.fonts.mono : toast.fonts.ui) ?? ""
        font.pixelSize: 13
        font.letterSpacing: toast.bracket ? 0.7 : 0
    }
}
