import QtQuick
import QtQuick.Controls

// The one raised surface on a page: an ayah, large, on its own card.
//
// Extracted because Recite and Memorise draw exactly this and drew it twice —
// same Flow, same right-to-left, same verdict colours, same 1.7 leading — and
// the two copies had already drifted (only one of them explained a wrong word
// on hover). The difference between the screens is whether the text starts
// hidden, which is one property.
//
// EVERY WORD IS ONE Text, AND THAT IS LOAD-BEARING. Arabic letters change shape
// according to their neighbours, so a word split across several Items would
// render as disconnected letter forms. The words come from the VERDICT rather
// than from splitting the ayah here, because `deen` drops tokens that normalise
// away and its indices count the tokens it kept — splitting again in QML would
// eventually disagree with it about which word is which.
//
// A plain Rectangle, not a rounded clip: rounding a filled rect is free,
// rounding its contents would cost a framebuffer per instance.
Rectangle {
    id: surface

    required property var style
    // `{words: [{op, reference, heard}]}` once a recitation has been scored,
    // null before one. Not the raw result — a recitation that VAD heard nothing
    // in has a result and no verdict, and painting one would tell someone whose
    // microphone was muted that they got every word wrong.
    property var verdict: null
    // The ayah as one string. It is what the dots are counted from, and what
    // gets drawn when there is nothing better.
    property string plain: ""
    // `deen api ayah`'s word list, with tajweed segments. Optional: it is the
    // best of the three renderings and the reason to prefer it is that a screen
    // asking you to recite correctly may as well colour the rules while you can
    // still act on them. Memorisation does not get it — `hifz due` carries no
    // word list, and a revealed answer is not a reading exercise.
    property var words: null
    // Memorisation hides the text until it has been recited. A dot per word
    // rather than a blank box: knowing how many words are coming is part of
    // recalling an ayah, and a blank tells you nothing about whether you have
    // finished.
    property bool masked: false

    // THREE RENDERINGS, IN ORDER OF WHAT THEY KNOW. A verdict knows which words
    // were right and outranks everything; a word list knows the tajweed; a bare
    // string knows only where the spaces are. They are ranked rather than
    // merged because verdict colour and tajweed colour are the same channel
    // saying two different things, and a word painted both is a word painted
    // neither.
    readonly property var wordModel: surface.verdict ? surface.verdict.words : (surface.words && surface.words.length > 0 ? surface.words : (surface.plain ? surface.plain.split(/\s+/) : []))
    readonly property bool tajweed: !surface.verdict && surface.words && surface.words.length > 0

    implicitHeight: Math.max(style.ui(150), (surface.masked ? maskLine.implicitHeight : flow.height) + style.ui(56))
    color: style.panel
    radius: style.radiusLg
    border.width: style.hairline
    border.color: style.alpha(style.muted, 0.18)

    // The card is the page's warm spot, so it gets the accent as a hairline of
    // light along its top edge rather than as a tint over the whole surface —
    // which would sit behind the Arabic and eat the contrast the text needs.
    Rectangle {
        anchors.top: parent.top
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.topMargin: surface.style.hairline
        width: parent.width * 0.38
        height: Math.max(1, surface.style.hairline)
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: surface.style.alpha(surface.style.accent, 0.0)
            }
            GradientStop {
                position: 0.5
                color: surface.style.alpha(surface.style.accent, 0.55)
            }
            GradientStop {
                position: 1.0
                color: surface.style.alpha(surface.style.accent, 0.0)
            }
        }
    }

    Text {
        id: maskLine
        textFormat: Text.PlainText

        anchors.centerIn: parent
        visible: surface.masked
        text: surface.plain ? "·  ".repeat(surface.plain.split(/\s+/).length).trim() : ""
        color: surface.style.alpha(surface.style.muted, 0.5)
        font.family: surface.style.arabicFamily
        font.pixelSize: surface.style.type(30)
    }

    Flow {
        id: flow

        // A SHORT AYAH IS CENTRED; A WRAPPING ONE IS NOT. The Flow has to be
        // the full measure or it cannot decide where to break, so an ayah that
        // fits on one line lands hard against the right edge of a card twice
        // its width, with the whole left half empty. Nudging the Flow left by
        // half its own slack puts that one line in the middle, and leaves a
        // wrapped ayah exactly where it was, since a wrapped line IS the width.
        //
        // `implicitWidth`, and NOT `childrenRect.width`, which is the obvious
        // choice and is ALWAYS exactly `width` here: the Repeater is itself a
        // zero-sized child of the Flow sitting at x=0, so the union of the
        // children's rects always reaches the left edge and the nudge is
        // always zero. A Positioner's implicit size comes from the items it
        // actually laid out, so it excludes the Repeater.
        //
        // Not a binding loop either: this reads the layout to place the Flow,
        // and the layout depends only on the Flow's `width`, which is fixed.
        //
        // Explicit x/y rather than `anchors.centerIn` plus a
        // horizontalCenterOffset — that combination silently ignores the
        // offset.
        x: Math.round(surface.style.ui(26) + (flow.implicitWidth - flow.width) / 2)
        y: Math.round((parent.height - height) / 2)
        width: parent.width - surface.style.ui(52)
        visible: !surface.masked
        layoutDirection: Qt.RightToLeft
        spacing: surface.style.ui(12)

        Repeater {
            model: surface.wordModel

            delegate: Label {
                required property var modelData

                readonly property bool aligned: surface.verdict !== null
                readonly property string op: aligned ? String(modelData.op) : "plain"
                // An `extra` word was said but is not in the ayah, so it has no
                // reference text to show — render what was heard instead.
                readonly property string shown: aligned ? (modelData.reference || modelData.heard) : (surface.tajweed ? surface.style.wordHtml(modelData.segments) : String(modelData))

                text: shown
                textFormat: surface.tajweed ? Text.RichText : Text.PlainText
                color: aligned ? surface.style.wordColor(op) : surface.style.fg
                font.family: surface.style.arabicFamily
                font.pixelSize: surface.style.type(30)
                // 1.15, DOWN FROM 1.7, and the 1.7 was measuring the wrong
                // thing. It was set to stop the Uthmani marks colliding with
                // the line above — but "the line above" is a Flow row whose
                // height is this Label's height, and Noto Naskh Arabic already
                // declares a line box of roughly TWICE its em to make room for
                // exactly those marks. Multiplying that by 1.7 put 3.4 em
                // between wrapped lines of Al-Baqarah, which reads as two
                // separate ayat. The marks never needed the help.
                lineHeight: 1.15
                opacity: op === "extra" ? 0.55 : 1

                ToolTip.visible: hover.hovered && aligned && op !== "ok"
                ToolTip.text: {
                    if (op === "missed")
                        return "not heard";
                    if (op === "extra")
                        return "heard, but not in this ayah";
                    return "heard: " + modelData.heard;
                }

                HoverHandler {
                    id: hover
                }
            }
        }
    }
}
