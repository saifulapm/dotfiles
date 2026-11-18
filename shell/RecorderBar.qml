import QtQuick
import "." as Root
import "lib/surface.mjs" as S
import "lib/island-tones.mjs" as T

// The Recorder's bar inside the island, on its fill (board 9): the record icon, the region's size, then Cancel and Start.
Item {
    id: bar

    required property var recorder
    required property var theme

    readonly property var tokens: theme.tokens
    readonly property var fonts: tokens ? tokens.type : ({})
    // The island's own text and fill, and the tones lifted to read on it.
    readonly property color on: S.surfaceStyle(tokens, "island").text
    readonly property color fill: S.surfaceStyle(tokens, "island").fill
    readonly property var tones: tokens ? T.islandTones(tokens) : ({ muted: "gray", accent: "blue", danger: "red", ok: "green" })
    // What the recorder's state reads: the size as drawn and the buttons' boxes.
    readonly property string sizeText: size.text
    readonly property Item cancelButton: cancel
    readonly property Item startButton: start

    // A recording starts on the frame after Start, with the bar already gone, so none of it is in the recording.
    visible: !recorder.pending && !recorder.recording

    // A press on the bar between its buttons is the bar's, so it never draws a new region under the island.
    MouseArea {
        anchors.fill: parent
    }

    Row {
        x: 16
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: String.fromCodePoint(0xF044A)
            color: bar.tones.danger
            font.family: "Symbols Nerd Font Mono"
            font.pixelSize: 16
        }

        Text {
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: "Record"
            color: bar.on
            font.family: bar.fonts.ui ?? ""
            font.pixelSize: 13
            font.weight: Font.Bold
        }

        Text {
            id: size
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            text: bar.recorder.region.w + " × " + bar.recorder.region.h
            color: bar.tones.muted
            font.family: bar.fonts.ui ?? ""
            font.pixelSize: 12
        }
    }

    Row {
        anchors.right: parent.right
        anchors.rightMargin: 12
        anchors.verticalCenter: parent.verticalCenter
        spacing: 12

        Rectangle {
            id: cancel
            width: cancelText.implicitWidth + 28
            height: 34
            radius: 10
            color: Qt.alpha(bar.on, 0.07)

            Text {
                id: cancelText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Cancel"
                color: bar.on
                font.family: bar.fonts.ui ?? ""
                font.pixelSize: 13
            }

            Root.Click {
                name: "record:cancel"
                onTapped: bar.recorder.close()
            }
        }

        // Inverted: the island's text as the fill, its fill as the text.
        Rectangle {
            id: start
            width: startText.implicitWidth + 28
            height: 34
            radius: 10
            color: bar.on

            Text {
                id: startText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: "Start"
                color: bar.fill
                font.family: bar.fonts.ui ?? ""
                font.pixelSize: 13
                font.weight: Font.Bold
            }

            Root.Click {
                name: "record:start"
                onTapped: bar.recorder.begin()
            }
        }
    }
}
