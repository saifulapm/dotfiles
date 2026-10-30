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
    readonly property var voiced: P.voiced(tokens.type.voice, passage.pick.kind, text.ref)
    readonly property string arabic: D.arabicFamily(Qt.fontFamilies())
    readonly property real side: look.pad[1]

    // What this sheet draws, for passage state: each line's text and drawn family, and the block's box in the window.
    function drawn() {
        const a = block.mapToItem(null, 0, 0);
        const label = look.frame === "card" ? frameLabel : stackLabel;
        return {
            label: label.text,
            ar: arText.visible ? arText.text : "",
            en: enText.text,
            ref: refText.text,
            family: { label: label.fontInfo.family, ar: arText.visible ? arText.fontInfo.family : "", en: enText.fontInfo.family, ref: refText.fontInfo.family },
            box: { x: a.x, y: a.y, w: block.width, h: block.height }
        };
    }

    Item {
        id: block
        anchors.centerIn: parent
        width: words.look.width
        height: stack.implicitHeight + words.look.pad[0] + words.look.pad[2]

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
                id: enText
                width: stack.width
                horizontalAlignment: words.look.en.align === "center" ? Text.AlignHCenter : Text.AlignLeft
                wrapMode: Text.WordWrap
                textFormat: Text.PlainText
                text: words.text.en
                color: words.tokens.color.ink
                font.family: words.look.en.font
                font.italic: words.look.en.italic
                font.pixelSize: words.look.en.size
                lineHeight: words.look.en.height
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
                    font.family: words.look.ref.font
                    font.pixelSize: words.look.ref.size
                    font.letterSpacing: words.look.ref.spacing
                }
            }
        }
    }
}
