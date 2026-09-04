import QtQuick
import QtQuick.Controls
import Quickshell.Io

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
    required property string loadError

    signal referenceChanged_(string ref)

    // "idle" | "recording" | "checking" | "done" | "error"
    property string state_: "idle"
    property var result: null
    property string error: ""

    readonly property bool busy: state_ === "recording" || state_ === "checking"

    // A result worth PAINTING, which is not the same as a result.
    //
    // When VAD hears no speech deen returns an empty transcription, and the
    // aligner — correctly — reports every word of the ayah as missed. Painting
    // that verdict puts the whole ayah in red under the words "nothing was
    // heard", which tells someone whose microphone was muted that they got
    // every word wrong. A recitation that did not happen has no verdict, so
    // the text stays plain and only the message speaks.
    readonly property var verdict: (result && String(result.heard).trim()) ? result : null

    // True while the reference field holds the keyboard, so the window's Space
    // shortcut can stand down — otherwise typing a space into "1:1" would start
    // a recording instead.
    readonly property bool editingReference: refField.activeFocus

    // A new ayah invalidates the last verdict — leaving it up would paint one
    // ayah's word colours over another's text.
    onAyahChanged: {
        screen.result = null;
        screen.error = "";
        if (screen.state_ !== "recording" && screen.state_ !== "checking")
            screen.state_ = "idle";
    }

    function start() {
        if (busy)
            return;
        screen.result = null;
        screen.error = "";
        screen.state_ = "recording";
        reciteProc.command = ["setpriv", "--pdeathsig", "TERM", "--", "deen", "recite", screen.reference];
        reciteProc.stdinEnabled = true;
        reciteProc.running = true;
    }

    function stop() {
        if (screen.state_ !== "recording")
            return;
        screen.state_ = "checking";
        // EOF on stdin is the stop. deen then transcribes, which is the second
        // or two this state covers.
        reciteProc.stdinEnabled = false;
    }

    function toggleRecording() {
        if (screen.state_ === "recording")
            stop();
        else if (!busy)
            start();
    }

    Process {
        id: reciteProc

        running: false
        stdout: StdioCollector {
            id: reciteOut
            waitForEnd: true
        }
        stderr: StdioCollector {
            id: reciteErr
            waitForEnd: true
        }

        onExited: exitCode => {
            let parsed = null;
            try {
                parsed = JSON.parse(String(reciteOut.text || ""));
            } catch (e) {
                parsed = null;
            }
            if (parsed && !parsed.error) {
                screen.result = parsed;
                screen.state_ = "done";
                return;
            }
            screen.state_ = "error";
            if (parsed && parsed.error)
                screen.error = String(parsed.error);
            else if (exitCode === 127 || exitCode === 126)
                screen.error = "deen is not installed — run `chezmoi apply` to build it";
            else
                screen.error = String(reciteErr.text || "").trim().split("\n").pop() || "recitation failed";
        }
    }

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
        y: Math.max(screen.style.pagePad, (parent.height - height) * 0.32)
        width: Math.min(parent.width - screen.style.pagePad * 2, screen.style.ui(900))
        spacing: screen.style.ui(18)

        // ------------------------------------------------------------- toolbar
        Row {
            spacing: screen.style.ui(10)
            width: parent.width

            Button {
                text: "◀"
                enabled: !screen.busy
                onClicked: screen.referenceChanged_("prev")
            }

            TextField {
                id: refField
                width: screen.style.ui(120)
                text: screen.reference
                enabled: !screen.busy
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(13)
                onAccepted: screen.referenceChanged_(text)
            }

            Button {
                text: "▶"
                enabled: !screen.busy
                onClicked: screen.referenceChanged_("next")
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: screen.ayah ? ("Surah " + screen.ayah.s + ", ayah " + screen.ayah.a) : ""
                color: screen.style.muted
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(12)
            }
        }

        // ---------------------------------------------------------- the ayah
        // Before a check this is the plain text; after one it is the aligned
        // words, coloured. The words come from the RESULT rather than from
        // splitting the ayah here, because deen drops tokens that normalise
        // away and its indices count the tokens it kept — splitting again in
        // QML would eventually disagree with it about which word is which.
        // The ayah is the hero, so it gets the one raised surface on the page.
        // A plain Rectangle, not a rounded clip: rounding a filled rect is
        // free, rounding its contents would cost a framebuffer.
        Rectangle {
            width: parent.width
            height: ayahFlow.height + screen.style.ui(44)
            visible: screen.ayah !== null
            color: screen.style.panel
            radius: screen.style.radiusLg
            border.width: screen.style.hairline
            border.color: screen.style.alpha(screen.style.muted, 0.18)

            Flow {
                id: ayahFlow

                anchors.centerIn: parent
                width: parent.width - screen.style.ui(44)
                layoutDirection: Qt.RightToLeft
                spacing: screen.style.ui(12)

                Repeater {
                    model: screen.verdict ? screen.verdict.words : (screen.ayah ? String(screen.ayah.ar).split(/\s+/) : [])

                    delegate: Label {
                        required property var modelData

                        readonly property bool aligned: screen.verdict !== null
                        readonly property string op: aligned ? String(modelData.op) : "plain"
                        // An `extra` word was said but is not in the ayah, so it has
                        // no reference text to show — render what was heard instead.
                        readonly property string shown: aligned ? (modelData.reference || modelData.heard) : String(modelData)

                        text: shown
                        color: aligned ? screen.style.wordColor(op) : screen.style.fg
                        font.family: screen.style.arabicFamily
                        font.pixelSize: screen.style.type(30)
                        // Uthmani text is dense with marks; the default leading
                        // collides them with the line above at this size.
                        lineHeight: 1.7
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

        // -------------------------------------------------------- translation
        Label {
            width: parent.width
            visible: screen.ayah !== null
            text: screen.ayah ? screen.ayah.bn : ""
            color: screen.style.muted
            wrapMode: Text.WordWrap
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(13)
        }

        Label {
            width: parent.width
            visible: screen.ayah !== null
            text: screen.ayah ? screen.ayah.en : ""
            color: screen.style.alpha(screen.style.muted, 0.75)
            wrapMode: Text.WordWrap
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(12)
        }

        // ------------------------------------------------------------- action
        Row {
            spacing: screen.style.ui(14)

            Button {
                id: recordButton
                enabled: screen.ayah !== null && screen.state_ !== "checking"
                text: screen.state_ === "recording" ? "Stop" : "Recite"
                onClicked: screen.toggleRecording()
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                color: screen.style.muted
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(12)
                text: {
                    switch (screen.state_) {
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
        Label {
            visible: screen.result !== null
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(15)
            color: screen.style.fg
            text: {
                if (!screen.result)
                    return "";
                // An empty transcription is silence, not a wrong recitation —
                // deen returns "" when VAD heard no speech, and saying "0 of 4
                // words" to someone whose microphone was muted sends them
                // looking for a mistake in their recitation.
                if (!String(screen.result.heard).trim())
                    return "Nothing was heard — check the microphone and try again";
                return screen.result.correct + " of " + screen.result.total + " words";
            }
        }

        Label {
            visible: text !== ""
            width: parent.width
            wrapMode: Text.WordWrap
            text: screen.error || screen.loadError
            color: screen.style.red
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(12)
        }

        // The honest footnote, and it stays on screen rather than living in a
        // README nobody opens. See docs/deen-2026-09-04.md §4b.
        Label {
            visible: screen.result !== null
            width: parent.width
            wrapMode: Text.WordWrap
            text: "This checks the words, not tajweed — articulation like ص/س or ض/د is not judged."
            color: screen.style.alpha(screen.style.muted, 0.7)
            font.family: screen.style.fontFamily
            font.pixelSize: screen.style.type(11)
        }
    }
}
