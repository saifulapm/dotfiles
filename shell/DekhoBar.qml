import QtQuick
import QtQuick.Layouts
import "lib/dekho-playing.mjs" as P

// The now-playing bar, in the keys strip's place at the foot of a page while a film or episode plays in its unit: the tag, the title, a series' episode and the key that stops it, in the strip's own margins and faces.
Item {
    id: bar

    required property var dekho

    readonly property var c: dekho.c
    readonly property var fonts: dekho.fonts
    readonly property var look: dekho.look
    readonly property string voice: dekho.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property bool caps: voice === "caps"
    readonly property var words: P.barText(voice)
    readonly property string bodyFont: (bracket ? fonts.mono : fonts.ui) ?? ""
    readonly property var now: dekho.nowPlaying

    function drawn() {
        return {
            shown: visible && height > 0,
            tag: tagText.text,
            title: titleText.text,
            lines: titleText.lineCount,
            episode: episodeText.text,
            keys: Array.from({
                length: keyRow.count
            }, (_, i) => keyRow.itemAt(i).drawn()),
            look: {
                tagFill: String(tagBox.color),
                tagRadius: tagBox.radius,
                font: titleText.font.family
            }
        };
    }

    visible: now !== null
    implicitHeight: visible ? row.implicitHeight + (plain ? 20 : 22) : 0

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: bar.plain ? 14 : 16
        anchors.rightMargin: bar.plain ? 14 : 16
        spacing: bar.plain ? 10 : 12

        // Artboard pills the tag in its accent's tint, Paper inks it, Blueprint brackets it in its accent.
        Rectangle {
            id: tagBox
            implicitWidth: tagText.implicitWidth + (bar.bracket ? 0 : bar.plain ? 18 : 12)
            implicitHeight: tagText.implicitHeight + (bar.bracket ? 0 : bar.plain ? 6 : 4)
            radius: bar.plain ? 8 : 0
            color: bar.plain ? bar.look.label.fill : bar.caps ? bar.c.ink ?? "black" : "transparent"

            Text {
                id: tagText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: bar.words.tag
                color: (bar.plain || bar.bracket ? bar.c.accent : bar.c.surface) ?? "black"
                font.family: bar.bodyFont
                font.pixelSize: bar.plain ? 12 : 10
                font.weight: bar.plain ? Font.Medium : Font.Bold
                font.letterSpacing: bar.plain ? 0 : 1.4
            }
        }
        Text {
            id: titleText
            Layout.fillWidth: true
            Layout.maximumWidth: implicitWidth
            textFormat: Text.PlainText
            text: bar.now ? bar.now.title : ""
            color: bar.c.ink ?? "black"
            font.family: bar.bodyFont
            font.pixelSize: bar.plain ? 13 : 12
            font.weight: Font.Medium
            elide: Text.ElideRight
            maximumLineCount: 1
        }
        Text {
            id: episodeText
            visible: text !== ""
            textFormat: Text.PlainText
            text: bar.now ? bar.now.episode : ""
            color: bar.c.muted ?? "gray"
            font.family: bar.bodyFont
            font.pixelSize: bar.plain ? 12 : 11
            font.letterSpacing: bar.bracket ? 0.7 : 0
        }
        Item {
            Layout.fillWidth: true
        }

        // The key that stops it, drawn as the keys strip draws its keys.
        Repeater {
            id: keyRow
            model: bar.look.keys(bar.words.keys)

            Rectangle {
                required property var modelData
                function drawn() {
                    return [keyName.text, keyWord.text];
                }
                implicitWidth: keyPair.implicitWidth + (bar.plain ? 14 : 0)
                implicitHeight: keyPair.implicitHeight + (bar.plain ? 6 : 0)
                radius: 6
                color: bar.plain ? bar.look.tile.fill : "transparent"

                // A click on the key stops the film as the key does.
                DekhoClick {
                    name: "bar-stop"
                    onTapped: bar.dekho.stopPlay()
                }
                Row {
                    id: keyPair
                    anchors.centerIn: parent
                    spacing: bar.bracket ? 8 : 6

                    Text {
                        id: keyName
                        textFormat: Text.PlainText
                        text: modelData.key
                        color: (bar.bracket ? bar.c.accent : bar.c.ink) ?? "black"
                        font.family: bar.bodyFont
                        font.pixelSize: bar.caps ? 10 : 11
                        font.weight: bar.plain ? Font.Medium : Font.Bold
                        font.letterSpacing: bar.caps ? 1 : bar.bracket ? 1.5 : 0
                    }
                    Text {
                        id: keyWord
                        textFormat: Text.PlainText
                        text: modelData.word
                        color: bar.c.muted ?? "gray"
                        font.family: bar.bodyFont
                        font.pixelSize: bar.caps ? 10 : 11
                        font.letterSpacing: bar.caps ? 1 : bar.bracket ? 1.5 : 0
                    }
                }
            }
        }
    }
}
