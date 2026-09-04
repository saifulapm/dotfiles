import QtQuick
import QtQuick.Controls
import "../components"

// Recite an ayah; be told which words were right.
//
// The whole screen is a front end for `deen recite`, which records, transcribes
// against a Quran-tuned whisper model and aligns the result word by word. This
// file starts that process, ends it, and paints what comes back.
//
// STOPPING A RECORDING IS A CLOSED PIPE, NOT A SIGNAL. `deen recite` records
// until its stdin reaches EOF, so Stop is `stdinEnabled = false` — no PID
// bookkeeping, no kill, and no way to leave the microphone open by losing track
// of a child. The ceiling in deen (--max-seconds) is the backstop if this
// screen dies mid-recitation.
FocusScope {
    id: screen

    required property var style
    required property string reference
    // Fetched by Deen.qml, like every other request in this module — the root
    // owns the data and the screens present it, which is the split Dekho draws
    // and the reason none of its screens instantiate a request of their own.
    required property var ayah
    // The word list beside it, carrying the tajweed spans. Same call, so it
    // costs nothing to draw.
    required property var words
    // The surah's row out of the 114, for a name instead of a number.
    required property var surah
    required property string loadError
    // One recitation attempt, owned by the root for the same reason (a screen
    // cannot see a type in the directory above it).
    required property var reciter

    signal referenceChanged_(string ref)

    readonly property var result: reciter.result
    readonly property var verdict: reciter.verdict
    readonly property bool busy: reciter.busy
    readonly property string error: reciter.error

    // True while the reference field holds the keyboard, so the window's Space
    // shortcut can stand down — otherwise typing a space into "1:1" would start
    // a recording instead.
    readonly property bool editingReference: refField.activeFocus

    function toggleRecording() {
        reciter.toggle();
    }

    function stop() {
        reciter.stop();
    }

    // A new ayah invalidates the last verdict — leaving it up would paint one
    // ayah's word colours over another's text.
    onAyahChanged: reciter.reset()

    // ------------------------------------------------------------------ layout
    //
    // ONE COLUMN, CENTRED, WITH A CEILING ON ITS WIDTH. The first version
    // anchored to the whole window, which on this desk left the ayah pinned to
    // the right edge, the translations to the left, and two thirds of the
    // screen empty between them — a form, not a page you read. A measure of
    // ~900 px is where Arabic at this size stops needing eye movement per word.
    Column {
        id: page

        anchors.horizontalCenter: parent.horizontalCenter
        // Sits above centre: the block grows downward as a verdict and its
        // footnote appear, and a truly centred column would shift the ayah
        // every time it did.
        y: Math.max(screen.style.pagePad, (parent.height - height) * 0.3)
        width: Math.min(parent.width - screen.style.pagePad * 2, screen.style.ui(900))
        spacing: screen.style.ui(20)

        // ------------------------------------------------------------- toolbar
        // The stepper and the field are one cluster on the left; the ayah's
        // name is the caption on the right, because the name is what tells you
        // where you are and the numbers are what you use to move.
        Item {
            width: parent.width
            height: refField.height

            Row {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: screen.style.ui(8)

                GlassButton {
                    style: screen.style
                    iconText: "◀"
                    compact: true
                    enabled: !screen.busy
                    Accessible.name: "Previous ayah"
                    onClicked: screen.referenceChanged_("prev")
                }

                RefField {
                    id: refField

                    width: screen.style.ui(128)
                    height: screen.style.ui(34)
                    style: screen.style
                    text: screen.reference
                    enabled: !screen.busy
                    onAccepted: screen.referenceChanged_(text)
                    onEscaped: screen.forceActiveFocus()
                }

                GlassButton {
                    style: screen.style
                    iconText: "▶"
                    compact: true
                    enabled: !screen.busy
                    Accessible.name: "Next ayah"
                    onClicked: screen.referenceChanged_("next")
                }
            }

            Column {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: screen.style.ui(2)

                Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    text: screen.surah ? screen.surah.en.toUpperCase() : ""
                    color: screen.style.brightFg
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(12)
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.1
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.right: parent.right
                    text: {
                        if (!screen.ayah)
                            return "";
                        const total = screen.surah ? (" of " + screen.surah.count) : "";
                        return "AYAH " + screen.ayah.a + total;
                    }
                    color: screen.style.muted
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(9)
                    font.letterSpacing: 0.7
                }
            }
        }

        // ---------------------------------------------------------- the ayah
        // The hero, and the one raised surface on the page. Tajweed coloured
        // until a recitation is scored, then coloured by the verdict — see
        // AyahSurface for why those two never share the text.
        AyahSurface {
            width: parent.width
            visible: screen.ayah !== null
            style: screen.style
            verdict: screen.verdict
            words: screen.words
            plain: screen.ayah ? String(screen.ayah.ar) : ""
        }

        // -------------------------------------------------------- translation
        // Two languages, each under its own name in small caps. Unlabelled they
        // were two grey paragraphs of different lengths and it was not obvious
        // that the second was the same sentence again.
        Column {
            width: parent.width
            visible: screen.ayah !== null
            spacing: screen.style.ui(14)

            Repeater {
                // Sized against the ayah above them rather than against the
                // rest of the shell — the argument this screen made first and
                // `Style.prose` now makes for every screen: a translation set at
                // the bar's 11 or 12 px under Arabic at 30 reads as a footnote
                // to it, and the whole reason both languages are on the page is
                // that the user cannot yet read the first one. The two are the
                // same size now, which is what was asked for; the Bangla had
                // been a point larger.
                model: [
                    {
                        tag: "বাংলা",
                        key: "bn",
                        dim: 1.0
                    },
                    {
                        tag: "ENGLISH",
                        key: "en",
                        dim: 0.75
                    }
                ]

                delegate: Column {
                    required property var modelData

                    width: parent.width
                    spacing: screen.style.ui(4)

                    Text {
                        textFormat: Text.PlainText
                        text: modelData.tag
                        color: screen.style.alpha(screen.style.muted, 0.6)
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(8)
                        font.weight: Font.DemiBold
                        font.letterSpacing: 1.2
                    }

                    Text {
                        textFormat: Text.PlainText
                        width: parent.width
                        text: screen.ayah ? screen.ayah[modelData.key] : ""
                        color: screen.style.alpha(screen.style.muted, modelData.dim)
                        wrapMode: Text.WordWrap
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.prose
                    }
                }
            }
        }

        // ------------------------------------------------------------- action
        Row {
            spacing: screen.style.ui(14)

            GlassButton {
                style: screen.style
                primary: true
                enabled: screen.ayah !== null && screen.reciter.state_ !== "checking"
                iconText: screen.reciter.state_ === "recording" ? "󰓛" : "󰍬"  // md-stop / md-microphone
                text: screen.reciter.state_ === "recording" ? "Stop" : "Recite"
                onClicked: screen.toggleRecording()
            }

            // The one thing on the page that has to be visible from across the
            // room: whether the microphone is open. A label saying "Listening"
            // is a label; a pulse is a state.
            Rectangle {
                anchors.verticalCenter: parent.verticalCenter
                visible: screen.reciter.state_ === "recording"
                width: screen.style.ui(10)
                height: width
                radius: width / 2
                color: screen.style.red

                SequentialAnimation on opacity {
                    running: screen.reciter.state_ === "recording"
                    loops: Animation.Infinite
                    NumberAnimation {
                        to: 0.25
                        duration: screen.style.slow
                        easing.type: screen.style.easing
                    }
                    NumberAnimation {
                        to: 1.0
                        duration: screen.style.slow
                        easing.type: screen.style.easing
                    }
                }
            }

            Text {
                textFormat: Text.PlainText
                anchors.verticalCenter: parent.verticalCenter
                color: screen.style.muted
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(11)
                text: {
                    switch (screen.reciter.state_) {
                    case "recording":
                        return "Listening — press Stop, or Space, when you have finished";
                    case "checking":
                        return "Checking…";
                    case "error":
                        return "";
                    default:
                        return screen.result ? "" : "Press Recite, say the ayah, then press Stop";
                    }
                }
            }
        }

        // ------------------------------------------------------------- result
        // A fraction of something, drawn as one. The fill carries the verdict,
        // so a poor recitation reads as poor before the number is read — and it
        // uses the SAME three colours the words above it are painted in, which
        // is what makes the bar and the ayah one statement instead of two.
        MeterRow {
            width: parent.width
            visible: screen.verdict !== null
            style: screen.style
            label: "Words correct"
            value: screen.result && screen.result.total > 0 ? screen.result.correct / screen.result.total : 0
            valueText: screen.result ? (screen.result.correct + " of " + screen.result.total + " · " + Math.round(value * 100) + "%") : ""
            fillColor: value >= 0.9 ? screen.style.green : value >= 0.6 ? screen.style.yellow : screen.style.red
        }

        // A recitation that did not happen has no meter and no word colours —
        // only this. Telling someone whose microphone was muted that they got
        // every word of the Fatiha wrong is the one failure mode that matters.
        Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: screen.reciter.heardNothing
            wrapMode: Text.WordWrap
            text: "Nothing was heard — check the microphone and try again"
            color: screen.style.yellow
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(12)
        }

        Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: screen.error || screen.loadError
            color: screen.style.red
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(11)
        }

        // The honest footnote, and it stays on screen rather than living in a
        // README nobody opens. See docs/deen-2026-09-04.md §4b.
        Text {
            textFormat: Text.PlainText
            visible: screen.result !== null
            width: parent.width
            wrapMode: Text.WordWrap
            text: "This checks the words, not tajweed — articulation like ص/س or ض/د is not judged."
            color: screen.style.alpha(screen.style.muted, 0.7)
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(10)
        }
    }
}
