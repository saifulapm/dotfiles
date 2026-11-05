import QtQuick
import QtQuick.Layouts

// The keys along a Deen page's foot as grey chips; pairs are [key, word].
ColumnLayout {
    id: strip

    required property var deen
    property var pairs: []

    readonly property var c: deen.c
    readonly property string bodyFont: deen.fonts.ui ?? ""

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

    Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: strip.c.line ?? "gray"
    }

    Flow {
        Layout.fillWidth: true
        Layout.leftMargin: 14
        Layout.rightMargin: 14
        Layout.topMargin: 10
        Layout.bottomMargin: 10
        spacing: 8

        Repeater {
            id: keyList
            model: strip.deen.look.keys(strip.pairs)

            Rectangle {
                required property var modelData

                function drawn() {
                    return [keyName.text, keyWord.text];
                }
                implicitWidth: keyPair.implicitWidth + 14
                implicitHeight: keyPair.implicitHeight + 6
                radius: 6
                color: strip.deen.look.tile.fill

                Row {
                    id: keyPair
                    anchors.centerIn: parent
                    spacing: 6

                    Text {
                        id: keyName
                        textFormat: Text.PlainText
                        text: modelData.key
                        color: strip.c.ink ?? "black"
                        font.family: strip.bodyFont
                        font.pixelSize: 11
                        font.weight: Font.Medium
                    }
                    Text {
                        id: keyWord
                        textFormat: Text.PlainText
                        text: modelData.word
                        color: strip.c.muted ?? "gray"
                        font.family: strip.bodyFont
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
