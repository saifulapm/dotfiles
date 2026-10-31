import QtQuick
import QtQuick.Effects
import "." as Root
import "lib/passage.mjs" as P
import "lib/deen.mjs" as D

// The day's passage on one paper sheet, in that sheet's theme; Paper.qml loads it by URL once the sheet has tokens and the passage its text.
Item {
    id: words

    required property var tokens
    required property var passage
    readonly property var look: P.look(tokens)
    readonly property var text: passage.text
    // The sheet's own voice, so an outgoing sheet keeps its theme's words until it goes.
    readonly property var voiced: P.voiced(tokens.type.voice, text.kind, text.ref)
    readonly property string arabic: D.arabicFamily(Qt.fontFamilies())
    readonly property real side: look.pad[1]
    // An ayah, hadith or dua day draws Bangla; a quote, its fallback too, draws English.
    readonly property bool bangla: text.bn !== ""

    // What this sheet draws, for passage state: each line's text and drawn family, and the block's box in the window.
    function drawn() {
        const a = block.mapToItem(null, 0, 0);
        const b = block.mapToItem(null, block.width, block.height);
        const label = look.frame === "card" ? frameLabel : stackLabel;
        return {
            label: label.text,
            ar: arText.visible ? arText.text : "",
            bn_pron: pronText.visible ? pronText.text : "",
            bn: bnText.visible ? bnText.text : "",
            en: enText.visible ? enText.text : "",
            ref: refText.text,
            family: {
                label: label.fontInfo.family,
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

        // Artboard: a selected artboard, the card ringed in the accent with its four handles.
        Root.Surface {
            anchors.fill: parent
            visible: words.look.frame === "card"
            tokens: words.tokens
            role: "card"
            restyle: ({ frame: { width: 2, color: words.tokens.color.accent } })
        }

        Text {
            id: frameLabel
            visible: words.look.frame === "card"
            y: -height - 13
            textFormat: Text.PlainText
            text: words.voiced.label
            color: words.look.label.color
            font.family: words.look.label.font
            font.pixelSize: words.look.label.size
        }

        // Blueprint: crop marks at the block's corners.
        Repeater {
            model: words.look.frame === "marks" ? [[0, 0], [1, 0], [0, 1], [1, 1]] : []

            Item {
                required property var modelData
                x: modelData[0] * (block.width - width)
                y: modelData[1] * (block.height - height)
                width: 22
                height: 22

                Rectangle {
                    y: parent.modelData[1] * (parent.height - height)
                    width: parent.width
                    height: 1
                    color: words.tokens.color.accent
                }
                Rectangle {
                    x: parent.modelData[0] * (parent.width - width)
                    width: 1
                    height: parent.height
                    color: words.tokens.color.accent
                }
            }
        }

        Column {
            id: stack
            x: words.side
            y: words.look.pad[0]
            width: block.width - 2 * words.side
            spacing: words.look.gap

            Text {
                id: stackLabel
                visible: words.look.frame !== "card"
                width: stack.width
                horizontalAlignment: words.look.frame === "none" ? Text.AlignHCenter : Text.AlignLeft
                textFormat: Text.PlainText
                text: words.voiced.label
                color: words.look.label.color
                font.family: words.look.label.font
                font.pixelSize: words.look.label.size
                font.letterSpacing: words.look.label.spacing
            }

            Text {
                id: arText
                visible: words.text.ar !== ""
                width: stack.width
                horizontalAlignment: words.look.ar.align === "center" ? Text.AlignHCenter : Text.AlignRight
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: words.text.ar
                color: words.tokens.color.ink
                font.family: words.arabic
                font.pixelSize: words.look.ar.size
                lineHeight: 1.5
                // Blueprint's ink glows; the layer is made only for a theme that asks for it.
                layer.enabled: words.look.ar.glow !== ""
                layer.effect: MultiEffect {
                    shadowEnabled: true
                    shadowColor: words.look.ar.glow || "transparent"
                    shadowOpacity: 0.35
                    shadowBlur: 1
                    blurMax: 22
                    shadowHorizontalOffset: 0
                    shadowVerticalOffset: 0
                }
            }

            Text {
                id: pronText
                visible: words.text.bn_pron !== ""
                width: stack.width
                horizontalAlignment: words.look.en.align === "center" ? Text.AlignHCenter : Text.AlignLeft
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: words.text.bn_pron
                color: words.look.pron.color
                font.family: words.look.pron.font
                font.pixelSize: words.look.pron.size
                lineHeightMode: Text.FixedHeight
                lineHeight: words.look.pron.size * words.look.pron.height
            }

            // The meaning in Bangla, upright in every theme.
            Text {
                id: bnText
                visible: words.bangla
                width: stack.width
                horizontalAlignment: words.look.en.align === "center" ? Text.AlignHCenter : Text.AlignLeft
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: words.text.bn
                color: words.tokens.color.ink
                font.family: words.look.bn.font
                font.pixelSize: words.look.bn.size
                lineHeightMode: Text.FixedHeight
                lineHeight: words.look.bn.size * words.look.bn.height
            }

            Text {
                id: enText
                visible: words.text.en !== ""
                width: stack.width
                horizontalAlignment: words.look.en.align === "center" ? Text.AlignHCenter : Text.AlignLeft
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: words.text.en
                color: words.tokens.color.ink
                font.family: words.look.en.font
                font.italic: words.look.en.italic
                font.pixelSize: words.look.en.size
                // A fixed pitch, as the boards' CSS line-height, so a glyph from a fallback face such as ﷺ opens no line wider.
                lineHeightMode: Text.FixedHeight
                lineHeight: words.look.en.size * words.look.en.height
            }

            Rectangle {
                visible: words.look.rule !== null
                x: words.look.rule && words.look.rule.width > 0 ? (stack.width - width) / 2 : 0
                width: words.look.rule && words.look.rule.width > 0 ? words.look.rule.width : stack.width
                height: 1
                color: words.look.rule ? words.look.rule.color : "transparent"
            }

            // Blueprint's reference sits on a dimension line with end ticks across the block; the others are a plain line of text.
            Item {
                width: stack.width
                height: words.look.ref.dimension ? 29 : refText.implicitHeight

                Rectangle {
                    visible: words.look.ref.dimension
                    y: Math.round(parent.height / 2)
                    width: parent.width
                    height: 1
                    color: words.look.ref.color
                }
                Repeater {
                    model: words.look.ref.dimension ? [0, 1] : []

                    Rectangle {
                        required property int modelData
                        x: modelData * (stack.width - 1)
                        y: (parent.height - height) / 2
                        width: 1
                        height: 22
                        color: words.look.ref.color
                    }
                }
                Rectangle {
                    visible: words.look.ref.dimension
                    anchors.centerIn: refText
                    width: refText.implicitWidth + 38
                    height: parent.height
                    color: words.tokens.color.paper
                }

                Text {
                    id: refText
                    width: words.look.ref.dimension ? Math.min(implicitWidth, stack.width - 60) : stack.width
                    x: words.look.ref.dimension ? (stack.width - width) / 2 : 0
                    anchors.verticalCenter: parent.verticalCenter
                    horizontalAlignment: words.look.ref.align === "center" ? Text.AlignHCenter : Text.AlignLeft
                    elide: Text.ElideRight
                    textFormat: Text.PlainText
                    text: words.voiced.ref
                    color: words.look.ref.color
                    font.family: words.bangla ? words.look.bnRef.font : words.look.ref.font
                    font.pixelSize: words.bangla ? words.look.bnRef.size : words.look.ref.size
                    // Spacing would break Bangla's conjuncts apart.
                    font.letterSpacing: words.bangla ? 0 : words.look.ref.spacing
                }
            }
        }
    }
}
