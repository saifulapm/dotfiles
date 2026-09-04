import QtQuick
import QtQuick.Controls
import "../components"

// Memorisation: recite what is due, from memory.
//
// The whole point is that THE TEXT IS HIDDEN until you have recited. A review
// where you can see the answer measures nothing, and the reason to build this
// on top of the Recite screen rather than beside it is that the grade comes
// from the recitation instead of from asking you whether you knew it — which
// is the question people answer generously.
//
// The suggested grade is a suggestion. The checker is wrong about one word in
// thirty and you are not, so all four buttons stay live and the one it
// proposes is merely the default.
FocusScope {
    id: screen

    required property var style
    required property var queue        // [{reference, card, ayah}]
    // The 114-row table, so a card can name its surah. `hifz due` answers with
    // numbers only, and "Surah 1, ayah 1" is not what you call the ayah you are
    // trying to remember.
    required property var surahs
    required property int totalDue
    required property int enrolled
    required property string loadError
    required property var reciter

    signal graded(string reference, string grade, real accuracy)
    signal enrol(string reference)

    property int position: 0

    readonly property var current: (queue && position < queue.length) ? queue[position] : null
    readonly property var verdict: reciter.verdict
    readonly property bool revealed: reciter.state_ === "done" || reciter.state_ === "error"

    // The four grades, each in the colour the meter would paint the recitation
    // that earned it — so the filled key and the bar above it agree.
    readonly property var grades: [
        {
            id: "again",
            label: "Again",
            tone: style.red
        },
        {
            id: "hard",
            label: "Hard",
            tone: style.yellow
        },
        {
            id: "good",
            label: "Good",
            tone: style.accent
        },
        {
            id: "easy",
            label: "Easy",
            tone: style.green
        }
    ]

    // Wire the reciter to whatever card is up, so Space always means "recite
    // this one".
    onCurrentChanged: {
        reciter.reset();
        reciter.reference = current ? current.reference : "";
    }

    function toggleRecording() {
        reciter.toggle();
    }

    function grade(name) {
        if (!current)
            return;
        const accuracy = (reciter.result && reciter.result.accuracy !== undefined) ? reciter.result.accuracy : -1;
        screen.graded(current.reference, name, accuracy);
        screen.position += 1;
        reciter.reset();
    }

    // Give up on this one and see it: not a failure mode to hide, it is how
    // you learn an ayah you have never got right.
    function reveal() {
        if (!reciter.busy)
            reciter.state_ = "done";
    }

    Column {
        id: page

        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(screen.style.pagePad, (parent.height - height) * 0.26)
        width: Math.min(parent.width - screen.style.pagePad * 2, screen.style.ui(900))
        spacing: screen.style.ui(20)
        visible: screen.current !== null

        // ------------------------------------------------------------- header
        // Which ayah on the left, what this card has been through on the right.
        // The card's own history used to be invisible, and it is the answer to
        // the question you ask when an ayah keeps coming back.
        Item {
            width: parent.width
            height: Math.max(whichBlock.height, historyRow.height)

            Column {
                id: whichBlock

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: screen.style.ui(2)

                Text {
                    textFormat: Text.PlainText
                    text: "FROM MEMORY"
                    color: screen.style.alpha(screen.style.muted, 0.7)
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(8)
                    font.weight: Font.DemiBold
                    font.letterSpacing: 1.2
                }

                Text {
                    textFormat: Text.PlainText
                    text: {
                        if (!screen.current)
                            return "";
                        const row = (screen.surahs || []).find(x => x.n === screen.current.ayah.s);
                        const name = row ? row.en : ("Surah " + screen.current.ayah.s);
                        return name + " · ayah " + screen.current.ayah.a;
                    }
                    color: screen.style.brightFg
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(16)
                    font.weight: Font.DemiBold
                }
            }

            Row {
                id: historyRow

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: screen.style.ui(6)

                MetaChip {
                    style: screen.style
                    visible: screen.current && screen.current.card.reps === 0
                    text: "new"
                    dotColor: screen.style.accent
                }

                MetaChip {
                    style: screen.style
                    visible: screen.current && screen.current.card.reps > 0
                    text: screen.current ? (screen.current.card.reps + (screen.current.card.reps === 1 ? " review" : " reviews")) : ""
                }

                MetaChip {
                    style: screen.style
                    visible: screen.current && screen.current.card.interval >= 1
                    text: screen.current ? ("every " + Math.round(screen.current.card.interval) + "d") : ""
                }

                MetaChip {
                    style: screen.style
                    visible: screen.current && screen.current.card.lapses > 0
                    text: screen.current ? (screen.current.card.lapses + " lapsed") : ""
                    dotColor: screen.style.yellow
                }
            }
        }

        // How much of today is behind you. "Eleven left" is a number you have to
        // hold; a bar that fills is one you can see from where you are sitting.
        MeterRow {
            width: parent.width
            visible: screen.totalDue > 0
            style: screen.style
            label: "Reviewed today"
            value: screen.totalDue > 0 ? screen.position / screen.totalDue : 0
            valueText: screen.position + " of " + screen.totalDue
        }

        // --------------------------------------------------------- the prompt
        AyahSurface {
            width: parent.width
            style: screen.style
            verdict: screen.verdict
            plain: screen.current ? String(screen.current.ayah.ar) : ""
            masked: !screen.revealed
        }

        Text {
            textFormat: Text.PlainText
            width: parent.width
            visible: screen.revealed
            text: screen.current ? screen.current.ayah.bn : ""
            color: screen.style.muted
            wrapMode: Text.WordWrap
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.prose
        }

        // ------------------------------------------------------------- action
        Row {
            spacing: screen.style.ui(12)
            visible: !screen.revealed

            GlassButton {
                style: screen.style
                primary: true
                enabled: screen.reciter.state_ !== "checking"
                iconText: screen.reciter.state_ === "recording" ? "󰓛" : "󰍬"  // md-stop / md-microphone
                text: screen.reciter.state_ === "recording" ? "Stop" : "Recite from memory"
                onClicked: screen.toggleRecording()
            }

            GlassButton {
                style: screen.style
                text: "Show me"
                enabled: !screen.reciter.busy
                onClicked: screen.reveal()
            }

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
                text: screen.reciter.state_ === "recording" ? "Listening — press Stop, or Space, when you have finished" : (screen.reciter.state_ === "checking" ? "Checking…" : "")
            }
        }

        // -------------------------------------------------------------- grade
        Column {
            width: parent.width
            spacing: screen.style.ui(12)
            visible: screen.revealed

            MeterRow {
                width: parent.width
                visible: screen.verdict !== null
                style: screen.style
                label: "Words correct"
                value: screen.reciter.result && screen.reciter.result.total > 0 ? screen.reciter.result.correct / screen.reciter.result.total : 0
                valueText: screen.reciter.result ? (screen.reciter.result.correct + " of " + screen.reciter.result.total + " · " + Math.round(value * 100) + "%") : ""
                fillColor: value >= 0.9 ? screen.style.green : value >= 0.6 ? screen.style.yellow : screen.style.red
            }

            Text {
                textFormat: Text.PlainText
                width: parent.width
                wrapMode: Text.WordWrap
                color: screen.reciter.heardNothing ? screen.style.yellow : screen.style.muted
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(11)
                text: {
                    if (screen.reciter.heardNothing)
                        return "Nothing was heard — check the microphone, or grade it yourself";
                    if (!screen.reciter.result)
                        return "How did that go?";
                    return "";
                }
            }

            Row {
                spacing: screen.style.ui(8)

                Repeater {
                    model: screen.grades

                    delegate: GlassButton {
                        required property var modelData
                        // The suggestion is the filled one, in its own colour,
                        // so the key that is proposed says how it went as well
                        // as what to press. The rest stay live because the
                        // checker is wrong sometimes and you are the one who
                        // knows whether you knew it.
                        readonly property bool suggested: screen.reciter.result && screen.reciter.result.suggested_grade === modelData.id

                        style: screen.style
                        text: modelData.label
                        tone: modelData.tone
                        primary: suggested
                        onClicked: screen.grade(modelData.id)
                    }
                }
            }
        }

        Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: screen.reciter.error || screen.loadError
            color: screen.style.red
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(11)
        }
    }

    // -------------------------------------------------------- nothing to do
    // Two different empty pages. "Nothing enrolled" is a page with work on it —
    // four surahs to add, the ones salat actually needs, in the order it is
    // reasonable to learn them. "Nothing due" is a page with none, and saying
    // so in the same layout as an error would read as one.
    Column {
        anchors.centerIn: parent
        visible: screen.current === null
        spacing: screen.style.ui(24)

        EmptyState {
            anchors.horizontalCenter: parent.horizontalCenter
            style: screen.style
            glyph: screen.enrolled === 0 ? "󱠧" : "󰄬"  // md-mosque / md-check
            title: screen.enrolled === 0 ? "Nothing to review yet" : "Nothing due — come back later"
            message: screen.enrolled === 0 ? "Start with what salat needs: Al-Fatiha, then the short surahs at the end." : screen.enrolled + " ayat enrolled. Reviews come back on their own schedule."
        }

        Row {
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: screen.style.ui(8)
            visible: screen.enrolled === 0

            Repeater {
                model: [
                    {
                        n: "1",
                        label: "Al-Fatiha"
                    },
                    {
                        n: "112",
                        label: "Al-Ikhlas"
                    },
                    {
                        n: "113",
                        label: "Al-Falaq"
                    },
                    {
                        n: "114",
                        label: "An-Nas"
                    }
                ]

                delegate: GlassButton {
                    required property var modelData

                    style: screen.style
                    iconText: "󰐕"  // md-plus
                    text: modelData.label
                    compact: true
                    onClicked: screen.enrol(modelData.n)
                }
            }
        }

        StatTile {
            anchors.horizontalCenter: parent.horizontalCenter
            width: screen.style.ui(240)
            visible: screen.enrolled > 0
            style: screen.style
            label: "ENROLLED"
            value: screen.enrolled + (screen.enrolled === 1 ? " ayah" : " ayat")
            valueColor: screen.style.green
        }

        Text {
            textFormat: Text.PlainText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            width: screen.style.ui(560)
            horizontalAlignment: Text.AlignHCenter
            wrapMode: Text.WordWrap
            text: screen.loadError
            color: screen.style.red
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(11)
        }
    }
}
