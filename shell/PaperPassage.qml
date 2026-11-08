import QtQuick
import "lib/passage.mjs" as P
import "lib/deen.mjs" as D

// The day's passage on one paper sheet, in that sheet's theme; Paper.qml loads it by URL once the sheet has tokens and the passage its text.
Item {
    id: words

    required property var tokens
    required property var passage
    readonly property var look: P.look(tokens)
    readonly property var text: passage.text
    readonly property var voiced: P.voiced(text.kind, text.ref)
    readonly property string arabic: D.arabicFamily(Qt.fontFamilies())
    readonly property real side: look.pad[1]
    // An ayah, hadith or dua day draws Bangla; a quote, its fallback too, draws English.
    readonly property bool bangla: text.bn !== ""

    // What this sheet draws, for passage state: each line's text and drawn family, and the block's box in the window.
    function drawn() {
        const a = block.mapToItem(null, 0, 0);
        const b = block.mapToItem(null, block.width, block.height);
        return {
            label: frameLabel.text,
            ar: arText.visible ? arText.text : "",
            bn_pron: pronText.visible ? pronText.text : "",
            bn: bnText.visible ? bnText.text : "",
            en: enText.visible ? enText.text : "",
            ref: refText.text,
            family: {
                label: frameLabel.fontInfo.family,
                ar: arText.visible ? arText.fontInfo.family : "",
                bn_pron: pronText.visible ? pronText.fontInfo.family : "",
                bn: bnText.visible ? bnText.fontInfo.family : "",
                en: enText.visible ? enText.fontInfo.family : "",
                ref: refText.fontInfo.family
            },
            bnLines: { count: bnText.lineCount, height: bnText.contentHeight, pitch: bnText.font.pixelSize * words.look.bn.height },
            // A comma's advance in the Bangla meaning's font, in ems: a face with no comma of its own takes one from a fallback, wide in a monospace one.
            bnComma: bnComma.advanceWidth / bnText.font.pixelSize,
            box: { x: a.x, y: a.y, w: b.x - a.x, h: b.y - a.y }
        };
    }

    TextMetrics {
        id: bnComma
        font: bnText.font
        text: ","
    }

    Item {
        id: block
        anchors.centerIn: parent
        width: words.look.width
        height: stack.implicitHeight + words.look.pad[0] + words.look.pad[2]
        // A passage taller than the paper less 96 px each side, the island's and the margins' room, draws smaller as a whole.
        scale: Math.min(1, (words.height - 192) / height)

        // No card: the words sit on the paper itself, the kind first.
        Column {
            id: stack
            x: words.side
            y: words.look.pad[0]
            width: block.width - 2 * words.side
            spacing: words.look.gap

            Text {
                id: frameLabel
                textFormat: Text.PlainText
                text: words.voiced.label
                color: words.look.label.color
                font.family: words.look.label.font
                font.pixelSize: words.look.label.size
            }

            Text {
                id: arText
                visible: words.text.ar !== ""
                width: stack.width
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: words.text.ar
                color: words.look.ink
                font.family: words.arabic
                font.pixelSize: words.look.ar.size
                lineHeight: 1.5
            }

            Text {
                id: pronText
                visible: words.text.bn_pron !== ""
                width: stack.width
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: words.text.bn_pron
                color: words.look.pron.color
                font.family: words.look.pron.font
                font.pixelSize: words.look.pron.size
                lineHeightMode: Text.FixedHeight
                lineHeight: words.look.pron.size * words.look.pron.height
            }

            // The meaning in Bangla, upright.
            Text {
                id: bnText
                visible: words.bangla
                width: stack.width
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: words.text.bn
                color: words.look.ink
                font.family: words.look.bn.font
                font.pixelSize: words.look.bn.size
                lineHeightMode: Text.FixedHeight
                lineHeight: words.look.bn.size * words.look.bn.height
            }

            Text {
                id: enText
                visible: words.text.en !== ""
                width: stack.width
                horizontalAlignment: Text.AlignLeft
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: words.text.en
                color: words.look.ink
                font.family: words.look.en.font
                font.pixelSize: words.look.en.size
                // A fixed pitch, as the boards' CSS line-height, so a glyph from a fallback face such as ﷺ opens no line wider.
                lineHeightMode: Text.FixedHeight
                lineHeight: words.look.en.size * words.look.en.height
            }

            Text {
                id: refText
                width: stack.width
                horizontalAlignment: Text.AlignLeft
                elide: Text.ElideRight
                textFormat: Text.PlainText
                text: words.voiced.ref
                color: words.look.ref.color
                font.family: words.bangla ? words.look.bnRef.font : words.look.ref.font
                font.pixelSize: words.bangla ? words.look.bnRef.size : words.look.ref.size
            }
        }
    }
}
