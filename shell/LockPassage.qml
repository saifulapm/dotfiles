import QtQuick
import "lib/passage.mjs" as P
import "lib/deen.mjs" as D

// The lock's passage, the day's other one: the paper's lines in the same order, smaller and every one centred.
Column {
    id: words

    required property var look
    required property var text
    readonly property var voiced: P.voiced(text.kind, text.ref)
    readonly property bool bangla: text.bn !== ""

    width: look.width
    spacing: look.gap

    Text {
        width: words.width
        horizontalAlignment: Text.AlignHCenter
        textFormat: Text.PlainText
        text: words.voiced.label
        color: words.look.label.color
        font.family: words.look.label.font
        font.pixelSize: words.look.label.size
        font.letterSpacing: 1.5
    }

    Text {
        visible: words.text.ar !== ""
        width: words.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: words.text.ar
        color: words.look.ar.color
        font.family: D.arabicFamily(Qt.fontFamilies())
        font.pixelSize: words.look.ar.size
        lineHeight: 1.5
    }

    Text {
        visible: words.text.bn_pron !== ""
        width: words.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: words.text.bn_pron
        color: words.look.pron.color
        font.family: words.look.pron.font
        font.pixelSize: words.look.pron.size
        lineHeightMode: Text.FixedHeight
        lineHeight: words.look.pron.size * words.look.pron.height
    }

    Text {
        visible: words.bangla
        width: words.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: words.text.bn
        color: words.look.bn.color
        font.family: words.look.bn.font
        font.pixelSize: words.look.bn.size
        lineHeightMode: Text.FixedHeight
        lineHeight: words.look.bn.size * words.look.bn.height
    }

    // A fixed pitch, as on the paper, so a fallback face's glyph such as ﷺ opens no line wider.
    Text {
        visible: words.text.en !== ""
        width: words.width
        horizontalAlignment: Text.AlignHCenter
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: words.text.en
        color: words.look.en.color
        font.family: words.look.en.font
        font.pixelSize: words.look.en.size
        lineHeightMode: Text.FixedHeight
        lineHeight: words.look.en.size * words.look.en.height
    }

    Text {
        width: words.width
        horizontalAlignment: Text.AlignHCenter
        elide: Text.ElideRight
        textFormat: Text.PlainText
        text: words.voiced.ref
        color: words.look.ref.color
        font.family: words.bangla ? words.look.bnRef.font : words.look.ref.font
        font.pixelSize: words.bangla ? words.look.bnRef.size : words.look.ref.size
    }
}
