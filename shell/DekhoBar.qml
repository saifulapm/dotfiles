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
    readonly property var words: P.barText()
    readonly property string bodyFont: fonts.ui ?? ""
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
    implicitHeight: visible ? row.implicitHeight + 20 : 0

    RowLayout {
        id: row
        anchors.fill: parent
        anchors.leftMargin: 14
        anchors.rightMargin: 14
        spacing: 10

        // The tag sits in a pill of the accent's tint.
        Rectangle {
            id: tagBox
            implicitWidth: tagText.implicitWidth + 18
            implicitHeight: tagText.implicitHeight + 6
            radius: 8
            color: bar.look.label.fill

            Text {
                id: tagText
                anchors.centerIn: parent
                textFormat: Text.PlainText
                text: bar.words.tag
                color: bar.c.accent ?? "black"
                font.family: bar.bodyFont
                font.pixelSize: 12
                font.weight: Font.Medium
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
            font.pixelSize: 13
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
            font.pixelSize: 12
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
                implicitWidth: keyPair.implicitWidth + 14
                implicitHeight: keyPair.implicitHeight + 6
                radius: 6
                color: bar.look.tile.fill

                // A click on the key stops the film as the key does.
                DekhoClick {
                    name: "bar-stop"
                    onTapped: bar.dekho.stopPlay()
                }
                Row {
                    id: keyPair
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        id: keyName
                        textFormat: Text.PlainText
                        text: modelData.key
                        color: bar.c.ink ?? "black"
                        font.family: bar.bodyFont
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    Text {
                        id: keyWord
                        textFormat: Text.PlainText
                        text: modelData.word
                        color: bar.c.muted ?? "gray"
                        font.family: bar.bodyFont
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
