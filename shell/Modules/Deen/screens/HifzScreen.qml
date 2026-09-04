import QtQuick
import QtQuick.Controls

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
        anchors.horizontalCenter: parent.horizontalCenter
        y: Math.max(screen.style.pagePad, (parent.height - height) * 0.28)
        width: Math.min(parent.width - screen.style.pagePad * 2, screen.style.ui(900))
        spacing: screen.style.ui(18)

        // ------------------------------------------------------------- header
        Row {
            spacing: screen.style.ui(12)

            Label {
                text: screen.current ? ("Surah " + screen.current.ayah.s + ", ayah " + screen.current.ayah.a) : ""
                color: screen.style.fg
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(15)
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: screen.totalDue > 0 ? ((screen.totalDue - screen.position) + " left today") : ""
                color: screen.style.muted
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(11)
            }
        }

        // --------------------------------------------------------- the prompt
        Rectangle {
            width: parent.width
            height: promptFlow.height + screen.style.ui(44)
            visible: screen.current !== null
            color: screen.style.panel
            radius: screen.style.radiusLg
            border.width: screen.style.hairline
            border.color: screen.style.alpha(screen.style.muted, 0.18)

            // Hidden until recited. A dash per word rather than a blank box:
            // knowing how many words are coming is part of recalling an ayah,
            // and a blank tells you nothing about whether you have finished.
            Label {
                anchors.centerIn: parent
                visible: !screen.revealed
                text: screen.current ? "·  ".repeat(String(screen.current.ayah.ar).split(/\s+/).length).trim() : ""
                color: screen.style.alpha(screen.style.muted, 0.5)
                font.family: screen.style.arabicFamily
                font.pixelSize: screen.style.type(30)
            }

            Flow {
                id: promptFlow

                anchors.centerIn: parent
                width: parent.width - screen.style.ui(44)
                visible: screen.revealed
                layoutDirection: Qt.RightToLeft
                spacing: screen.style.ui(12)

                Repeater {
                    model: screen.verdict ? screen.verdict.words : (screen.current ? String(screen.current.ayah.ar).split(/\s+/) : [])

                    delegate: Label {
                        required property var modelData

                        readonly property bool aligned: screen.verdict !== null
                        readonly property string op: aligned ? String(modelData.op) : "plain"

                        text: aligned ? (modelData.reference || modelData.heard) : String(modelData)
                        color: aligned ? screen.style.wordColor(op) : screen.style.fg
                        font.family: screen.style.arabicFamily
                        font.pixelSize: screen.style.type(30)
                        lineHeight: 1.7
                        opacity: op === "extra" ? 0.55 : 1
                    }
                }
            }
        }

        Label {
            width: parent.width
            visible: screen.revealed && screen.current !== null
            text: screen.current ? screen.current.ayah.bn : ""
            color: screen.style.muted
            wrapMode: Text.WordWrap
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(12)
        }

        // ------------------------------------------------------------- action
        Row {
            spacing: screen.style.ui(12)
            visible: screen.current !== null && !screen.revealed

            Button {
                enabled: screen.reciter.state_ !== "checking"
                text: screen.reciter.state_ === "recording" ? "Stop" : "Recite from memory"
                onClicked: screen.toggleRecording()
            }

            Button {
                flat: true
                text: "Show me"
                enabled: !screen.reciter.busy
                onClicked: screen.reveal()
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                color: screen.style.muted
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(12)
                text: screen.reciter.state_ === "recording" ? "Listening…" : (screen.reciter.state_ === "checking" ? "Checking…" : "")
            }
        }

        // -------------------------------------------------------------- grade
        Column {
            spacing: screen.style.ui(8)
            visible: screen.revealed && screen.current !== null

            Label {
                color: screen.style.fg
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(13)
                text: {
                    if (!screen.reciter.result)
                        return "How did that go?";
                    if (screen.reciter.heardNothing)
                        return "Nothing was heard — check the microphone, or grade it yourself";
                    return screen.reciter.result.correct + " of " + screen.reciter.result.total + " words";
                }
            }

            Row {
                spacing: screen.style.ui(8)

                Repeater {
                    model: [
                        {
                            id: "again",
                            label: "Again"
                        },
                        {
                            id: "hard",
                            label: "Hard"
                        },
                        {
                            id: "good",
                            label: "Good"
                        },
                        {
                            id: "easy",
                            label: "Easy"
                        }
                    ]

                    delegate: Button {
                        required property var modelData
                        // The suggestion is the raised one; the rest stay live
                        // because the checker is wrong sometimes and you are
                        // the one who knows whether you knew it.
                        readonly property bool suggested: screen.reciter.result && screen.reciter.result.suggested_grade === modelData.id

                        text: modelData.label
                        flat: !suggested
                        onClicked: screen.grade(modelData.id)
                    }
                }
            }
        }

        // -------------------------------------------------------- empty state
        Column {
            spacing: screen.style.ui(10)
            visible: screen.current === null

            Label {
                text: screen.enrolled === 0 ? "Nothing to review yet" : "Nothing due — come back later"
                color: screen.style.fg
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(15)
            }

            Label {
                width: screen.style.ui(560)
                wrapMode: Text.WordWrap
                color: screen.style.muted
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(12)
                text: screen.enrolled === 0 ? "Start with what salat needs: Al-Fatiha, then the short surahs at the end. Open Read and add one." : screen.enrolled + " ayat enrolled. Reviews come back on their own schedule."
            }

            Row {
                spacing: screen.style.ui(8)
                visible: screen.enrolled === 0

                Repeater {
                    // The ayat a person actually needs to pray, in the order it
                    // is reasonable to learn them.
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

                    delegate: Button {
                        required property var modelData
                        text: "+ " + modelData.label
                        onClicked: screen.enrol(modelData.n)
                    }
                }
            }
        }

        Label {
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: screen.reciter.error || screen.loadError
            color: screen.style.red
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(12)
        }
    }
}
