import QtQuick
import QtQuick.Controls
import "../components"

// Read a surah, and hear any word you cannot read.
//
// This is the screen for "I forgot how to read the Quran", so the one
// interaction that matters is: tap a word, hear that word. Everything else on
// the page is arrangement around that.
//
// EVERY WORD IS ONE Text, AND THAT IS LOAD-BEARING. Arabic letters change shape
// according to their neighbours, so a word split across several Items to colour
// its tajweed would render as disconnected letter forms — the exact failure the
// old `quran-verse.sh` had to hand-drive fribidi to avoid. Rich text colours
// INSIDE a single layout, so the shaping is Qt's and stays correct.
FocusScope {
    id: screen

    required property var style
    required property var surah      // {n, ar, en, tr, count, type}
    // The whole 114-row table, for the picker.
    required property var surahs
    required property var ayahs      // [{s,a,ar,bn,en}]
    required property var words      // [[{i,text,audio,segments}]] parallel to ayahs
    required property string loadError
    // Empty for Al-Fatiha, which opens with it as ayah 1, and for At-Tawbah,
    // which has none. deen decides that, not this file.
    required property string basmala

    signal surahStepped(int delta)
    signal surahPicked(int n)
    signal play(string reference)
    signal enrol(string surah)

    // The ayah currently sounding, so its row can say so. Cleared by the owner.
    property string playing: ""
    // The window owns Escape (a Shortcut outranks key delivery, which is how
    // Escape closes the hub from inside a text field), so it has to be told
    // when there is a sheet in front of the page for Escape to mean instead.
    readonly property bool sheetOpen: picker.open

    function closeSheet() {
        picker.open = false;
    }

    // HEADER AND LIST ARE ANCHORED SIBLINGS, NOT A COLUMN. A Column sizes
    // itself from its children, so a ListView inside one that took its height
    // from the Column would be defining the thing it depends on — Qt resolved
    // that by handing the list a negative height, which it reported as a
    // negative cache buffer rather than as the loop it was.
    Column {
        id: header

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: screen.style.ui(20)
        width: Math.min(parent.width - screen.style.pagePad * 2, screen.style.ui(980))
        spacing: screen.style.ui(14)

        // ------------------------------------------------------------ header
        // The surah announces itself the way the page of a mushaf does: its own
        // name, in Arabic, at the top.
        Item {
            width: parent.width
            height: Math.max(stepper.height, arabicName.height)

            Row {
                id: stepper

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: screen.style.ui(8)

                GlassButton {
                    style: screen.style
                    iconText: "◀"
                    enabled: screen.surah && screen.surah.n > 1
                    Accessible.name: "Previous surah"
                    onClicked: screen.surahStepped(-1)
                }

                GlassButton {
                    style: screen.style
                    iconText: "▶"
                    enabled: screen.surah && screen.surah.n < 114
                    Accessible.name: "Next surah"
                    onClicked: screen.surahStepped(1)
                }

                // THE TITLE IS THE BROWSE BUTTON. Before it the reader could
                // only be walked one surah at a time, which is 111 presses to
                // reach An-Nas — and the name was a Label, so there was nothing
                // on the page that looked like it would answer "take me to
                // Ar-Rahman". Making the name itself the control means there is
                // exactly one thing to find, and it is the thing already
                // telling you where you are.
                GlassButton {
                    style: screen.style
                    iconText: "󰍜"  // md-menu
                    text: screen.surah ? (screen.surah.n + " · " + screen.surah.en.toUpperCase()) : "SURAHS"
                    Accessible.name: "Browse surahs"
                    onClicked: picker.open = true
                }
            }

            Text {
                id: arabicName
                textFormat: Text.PlainText

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: screen.surah ? screen.surah.ar : ""
                color: screen.style.alpha(screen.style.fg, 0.85)
                font.family: screen.style.arabicFamily
                font.pixelSize: screen.style.type(20)
            }
        }

        // Facts on the left, the one action on the right. `+ Memorise` used to
        // sit in the middle of the title row looking like part of the name.
        Item {
            width: parent.width
            height: Math.max(facts.height, enrolButton.height)

            // A Flow, not a Row, and bounded on the right by the button. Seven
            // chips do not fit beside `+ Memorise` in a half-width window, and
            // a Row does not know that — it just kept laying them out
            // underneath it.
            Flow {
                id: facts

                anchors.left: parent.left
                anchors.right: enrolButton.left
                anchors.rightMargin: screen.style.ui(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: screen.style.ui(6)

                MetaChip {
                    style: screen.style
                    visible: screen.surah !== null
                    text: screen.surah ? screen.surah.tr : ""
                }

                MetaChip {
                    style: screen.style
                    visible: screen.surah !== null
                    text: screen.surah ? (screen.surah.count + " ayat") : ""
                }

                MetaChip {
                    style: screen.style
                    visible: screen.surah !== null
                    text: screen.surah ? screen.surah.type : ""
                }

                // Colour without a key is decoration. Four families, named in
                // the words someone relearning would use rather than in Arabic
                // terms they have not met yet.
                Repeater {
                    model: screen.style.tajweedLegend

                    delegate: MetaChip {
                        required property var modelData

                        style: screen.style
                        text: modelData.label
                        dotColor: screen.style.familyColor(modelData.family)
                    }
                }
            }

            GlassButton {
                id: enrolButton

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                style: screen.style
                iconText: "󰐕"  // md-plus
                text: "Memorise"
                compact: true
                enabled: screen.surah !== null
                onClicked: screen.enrol(String(screen.surah.n))
            }
        }

        Rectangle {
            width: parent.width
            height: screen.style.hairline
            color: screen.style.alpha(screen.style.muted, 0.18)
        }
    }

    // The Basmala is a heading, not an ayah — it carries no number and no
    // translation, and tapping it plays it like any other line would.
    Text {
        id: basmalaLine
        textFormat: Text.PlainText

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: header.bottom
        anchors.topMargin: screen.style.ui(18)
        width: header.width
        visible: screen.basmala !== ""
        text: screen.basmala
        horizontalAlignment: Text.AlignHCenter
        color: screen.style.alpha(screen.style.fg, basmalaHover.hovered ? 1.0 : 0.8)
        font.family: screen.style.arabicFamily
        font.pixelSize: screen.style.type(24)

        HoverHandler {
            id: basmalaHover
            cursorShape: Qt.PointingHandCursor
        }

        TapHandler {
            onTapped: screen.play("1:1")
        }
    }

    // ----------------------------------------------------------------- ayahs
    ListView {
        id: list

        anchors.horizontalCenter: parent.horizontalCenter
        // Anchored past the Basmala when there is one, and to the header when
        // there is not. A `height: visible ? implicitHeight : 0` on the line
        // itself was the obvious alternative and is a binding loop — a Label's
        // implicitHeight is derived from its geometry, so it cannot also
        // define it.
        anchors.top: screen.basmala !== "" ? basmalaLine.bottom : header.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: screen.style.ui(16)
        anchors.bottomMargin: screen.style.pagePad
        width: header.width
        clip: true
        spacing: screen.style.ui(6)
        // A surah is a fixed list that only changes when the surah does, so
        // caching a screen either side costs little and stops the scroll
        // re-laying out Arabic it just threw away. Clamped because `height`
        // is briefly negative while the anchors resolve, and ListView rejects
        // that rather than ignoring it.
        cacheBuffer: Math.max(0, height)

        model: screen.ayahs || []

        ScrollBar.vertical: ScrollBar {}

        // AN AYAH AND ITS MEANING SIT SIDE BY SIDE, which is the layout a
        // bilingual mushaf has always used and the answer to the hole the
        // stacked version left. Arabic is right-aligned and Bangla is
        // left-aligned, so stacking them in one 980 px column put the two lines
        // at opposite ends of the page with a thousand pixels of nothing
        // between them and no way to tell which translation belonged to which
        // ayah. In two columns that space becomes the gutter between them.
        //
        // It folds back to stacked below 620 px of content, because two columns
        // of two words each is worse than one column of four.
        delegate: Item {
            id: row

            required property int index
            required property var modelData

            readonly property var wordList: (screen.words && screen.words[index]) || []
            readonly property string reference: modelData.s + ":" + modelData.a
            readonly property bool sounding: screen.playing === row.reference

            readonly property real contentWidth: width - badge.width - screen.style.ui(42)
            readonly property bool wide: contentWidth >= screen.style.ui(620)
            readonly property real arabicWidth: row.wide ? Math.round(row.contentWidth * 0.56) : row.contentWidth
            readonly property real proseWidth: row.wide ? row.contentWidth - row.arabicWidth - screen.style.ui(30) : row.contentWidth

            width: list.width - screen.style.ui(16)
            // Stacked, the space below still has to beat the leading the
            // Arabic line box carries below its glyphs, or an ayah groups with
            // the NEXT one's number instead of with its own translation. Side
            // by side there is nothing to beat.
            height: (row.wide ? Math.max(arabicFlow.height, prose.height + screen.style.ui(10)) : arabicFlow.height + prose.height) + screen.style.ui(row.wide ? 30 : 40)

            Rectangle {
                anchors.fill: parent
                radius: screen.style.radiusMd
                // A resting tint, not transparent. Arabic is right-aligned and
                // its translation is not, so a short ayah leaves real empty
                // between the two columns whatever the split is — and the way
                // to stop that reading as a hole is to make it read as padding
                // INSIDE something. Each ayah is a block; hover and playback
                // then change a surface rather than conjure one.
                color: row.sounding ? screen.style.alpha(screen.style.accent, 0.09) : rowHover.hovered ? screen.style.alpha(screen.style.fg, 0.05) : screen.style.alpha(screen.style.fg, 0.025)

                Behavior on color {
                    ColorAnimation {
                        duration: screen.style.normal
                        easing.type: screen.style.easing
                    }
                }
            }

            HoverHandler {
                id: rowHover
            }

            // The ayah number is the play button for the whole ayah — it is
            // already the thing you point at to say "this one".
            Rectangle {
                id: badge

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: screen.style.ui(10)
                anchors.topMargin: screen.style.ui(14)
                width: Math.max(screen.style.ui(30), numberLabel.implicitWidth + screen.style.ui(14))
                height: screen.style.ui(28)
                radius: screen.style.radiusSm
                color: row.sounding ? screen.style.accent : badgeHover.hovered ? screen.style.alpha(screen.style.fg, 0.14) : screen.style.alpha(screen.style.fg, 0.06)
                border.width: screen.style.hairline
                border.color: row.sounding ? screen.style.accent : screen.style.alpha(screen.style.fg, 0.14)

                Behavior on color {
                    ColorAnimation {
                        duration: screen.style.normal
                        easing.type: screen.style.easing
                    }
                }

                Text {
                    id: numberLabel
                    textFormat: Text.PlainText

                    anchors.centerIn: parent
                    // A sounding ayah says so with a glyph rather than with a
                    // colour alone, which is the difference between "this one
                    // is playing" and "this one is selected".
                    text: row.sounding ? "󰐊" : String(row.modelData.a)  // md-play
                    color: row.sounding ? screen.style.bg : screen.style.muted
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(11)
                    font.weight: Font.DemiBold
                }

                HoverHandler {
                    id: badgeHover
                    cursorShape: Qt.PointingHandCursor
                }

                TapHandler {
                    onTapped: screen.play(row.reference)
                }
            }

            Flow {
                id: arabicFlow

                anchors.right: parent.right
                anchors.rightMargin: screen.style.ui(14)
                anchors.top: parent.top
                anchors.topMargin: screen.style.ui(12)
                width: row.arabicWidth
                layoutDirection: Qt.RightToLeft
                spacing: screen.style.ui(10)

                Repeater {
                    model: row.wordList

                    delegate: Label {
                        required property var modelData

                        text: screen.style.wordHtml(modelData.segments)
                        textFormat: Text.RichText
                        color: screen.style.fg
                        font.family: screen.style.arabicFamily
                        font.pixelSize: screen.style.type(26)
                        // See AyahSurface for why this is 1.15 and not the 1.7
                        // it was: Noto Naskh already reserves ~2 em of line box
                        // for the marks, so 1.7 on top of it put 3.4 em between
                        // the wrapped lines of an ayah.
                        lineHeight: 1.15
                        // A word under the pointer is one you are about to
                        // ask about, so it says it is askable.
                        opacity: wordHover.hovered ? 0.65 : 1

                        HoverHandler {
                            id: wordHover
                            cursorShape: Qt.PointingHandCursor
                        }

                        TapHandler {
                            onTapped: screen.play(row.reference + ":" + modelData.i)
                        }
                    }
                }
            }

            Column {
                id: prose

                anchors.left: badge.right
                anchors.leftMargin: screen.style.ui(14)
                anchors.top: row.wide ? parent.top : arabicFlow.bottom
                // The Arabic's line box is taller than its glyphs, so its first
                // line sits low inside it; matching that offset is what makes
                // the two columns start on the same optical line rather than
                // the same geometric one.
                anchors.topMargin: row.wide ? screen.style.ui(18) : 0
                width: row.proseWidth
                spacing: screen.style.ui(6)

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.modelData.bn
                    color: screen.style.muted
                    wrapMode: Text.WordWrap
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(13)
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.modelData.en
                    color: screen.style.alpha(screen.style.muted, 0.7)
                    wrapMode: Text.WordWrap
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(12)
                }
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        visible: screen.loadError !== ""
        style: screen.style
        glyph: "󱠧"
        title: "The text is not available"
        message: screen.loadError
    }

    SurahPicker {
        id: picker

        style: screen.style
        surahs: screen.surahs
        current: screen.surah ? screen.surah.n : 1
        onPicked: n => screen.surahPicked(n)
        onDismissed: picker.open = false
    }
}
