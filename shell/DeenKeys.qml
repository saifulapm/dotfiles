import QtQuick
import QtQuick.Layouts

// The keys along a Deen page's foot, as each board strips them: Paper's tracked caps, Artboard's grey chips, Blueprint's bracketed accent keys; pairs are [key, word].
ColumnLayout {
    id: strip

    required property var deen
    property var pairs: []

    readonly property var c: deen.c
    readonly property string voice: deen.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property string bodyFont: (bracket ? deen.fonts.mono : deen.fonts.ui) ?? ""

    function drawn() {
        const out = [];
        for (let i = 0; i < keyList.count; i++) {
            const k = keyList.itemAt(i);
            if (k)
                out.push(k.drawn());
        }
        return out;
    }

    spacing: 0

    Item {
        Layout.fillWidth: true
        implicitHeight: 1

        Rectangle {
            anchors.fill: parent
            visible: !strip.bracket
            color: (strip.voice === "caps" ? strip.c.ink : strip.c.line) ?? "gray"
        }
        Dashed {
            anchors.fill: parent
            visible: strip.bracket
            color: strip.c.line ?? "gray"
        }
    }

    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: strip.plain ? 14 : 16
        Layout.rightMargin: strip.plain ? 14 : 16
        Layout.topMargin: strip.plain ? 10 : 11
        Layout.bottomMargin: strip.plain ? 10 : 11
        spacing: strip.plain ? 8 : 16

        Repeater {
            id: keyList
            model: strip.deen.look.keys(strip.pairs)

            Rectangle {
                required property var modelData

                function drawn() {
                    return [keyName.text, keyWord.text];
                }
                implicitWidth: keyPair.implicitWidth + (strip.plain ? 14 : 0)
                implicitHeight: keyPair.implicitHeight + (strip.plain ? 6 : 0)
                radius: 6
                color: strip.plain ? strip.deen.look.tile.fill : "transparent"

                Row {
                    id: keyPair
                    anchors.centerIn: parent
                    spacing: strip.bracket ? 8 : 6

                    Text {
                        id: keyName
                        textFormat: Text.PlainText
                        text: modelData.key
                        color: (strip.bracket ? strip.c.accent : strip.c.ink) ?? "black"
                        font.family: strip.bodyFont
                        font.pixelSize: strip.voice === "caps" ? 10 : 11
                        font.weight: strip.plain ? Font.Medium : Font.Bold
                        font.letterSpacing: strip.voice === "caps" ? 1 : strip.bracket ? 1.5 : 0
                    }
                    Text {
                        id: keyWord
                        textFormat: Text.PlainText
                        text: modelData.word
                        color: strip.c.muted ?? "gray"
                        font.family: strip.bodyFont
                        font.pixelSize: strip.voice === "caps" ? 10 : 11
                        font.letterSpacing: strip.voice === "caps" ? 1 : strip.bracket ? 1.5 : 0
                    }
                }
            }
        }
    }
}
