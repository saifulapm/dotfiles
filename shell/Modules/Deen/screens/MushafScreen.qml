import QtQuick
import QtQuick.Controls

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
    required property var ayahs      // [{s,a,ar,bn,en}]
    required property var words      // [[{i,text,audio,segments}]] parallel to ayahs
    required property string loadError
    // Empty for Al-Fatiha, which opens with it as ayah 1, and for At-Tawbah,
    // which has none. deen decides that, not this file.
    required property string basmala

    signal surahStepped(int delta)
    signal play(string reference)

    // The ayah currently sounding, so its row can say so. Cleared by the owner.
    property string playing: ""

    function wordHtml(segments) {
        let out = "";
        for (let i = 0; i < segments.length; i++) {
            const seg = segments[i];
            out += seg.r ? ('<font color="' + screen.style.tajweedColor(seg.r) + '">' + seg.t + "</font>") : seg.t;
        }
        return out;
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
        anchors.topMargin: screen.style.pagePad
        width: Math.min(parent.width - screen.style.pagePad * 2, screen.style.ui(900))
        spacing: screen.style.ui(14)

        // ------------------------------------------------------------ header
        Row {
            spacing: screen.style.ui(10)
            width: parent.width

            Button {
                text: "◀"
                enabled: screen.surah && screen.surah.n > 1
                onClicked: screen.surahStepped(-1)
            }

            Button {
                text: "▶"
                enabled: screen.surah && screen.surah.n < 114
                onClicked: screen.surahStepped(1)
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: screen.surah ? (screen.surah.n + ". " + screen.surah.en + " — " + screen.surah.tr) : ""
                color: screen.style.fg
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(14)
            }

            Label {
                anchors.verticalCenter: parent.verticalCenter
                text: screen.surah ? (screen.surah.count + " ayat · " + screen.surah.type) : ""
                color: screen.style.muted
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(11)
            }
        }

        // ------------------------------------------------------------ legend
        // Colour without a key is decoration. Four families, named in the words
        // someone relearning would use rather than in Arabic terms they have
        // not met yet.
        Row {
            spacing: screen.style.ui(16)

            Repeater {
                model: screen.style.tajweedLegend

                delegate: Row {
                    required property var modelData
                    spacing: screen.style.ui(5)

                    Rectangle {
                        anchors.verticalCenter: parent.verticalCenter
                        width: screen.style.ui(9)
                        height: width
                        radius: width / 2
                        color: screen.style.familyColor(modelData.family)
                    }

                    Label {
                        text: modelData.label
                        color: screen.style.muted
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(10)
                    }
                }
            }
        }
    }

    // The Basmala is a heading, not an ayah — it carries no number and no
    // translation, and tapping it plays it like any other line would.
    Label {
        id: basmalaLine

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: header.bottom
        anchors.topMargin: screen.style.ui(14)
        width: header.width
        visible: screen.basmala !== ""
        text: screen.basmala
        horizontalAlignment: Text.AlignHCenter
        color: screen.style.alpha(screen.style.fg, 0.8)
        font.family: screen.style.arabicFamily
        font.pixelSize: screen.style.type(22)

        HoverHandler {
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
        anchors.topMargin: screen.style.ui(14)
        anchors.bottomMargin: screen.style.pagePad
        width: header.width
        clip: true
        spacing: screen.style.ui(16)
        // A surah is a fixed list that only changes when the surah does, so
        // caching a screen either side costs little and stops the scroll
        // re-laying out Arabic it just threw away. Clamped because `height`
        // is briefly negative while the anchors resolve, and ListView rejects
        // that rather than ignoring it.
        cacheBuffer: Math.max(0, height)

        model: screen.ayahs || []

        ScrollBar.vertical: ScrollBar {}

        delegate: Column {
            id: row

            required property int index
            required property var modelData

            readonly property var wordList: (screen.words && screen.words[index]) || []
            readonly property string reference: modelData.s + ":" + modelData.a

            width: list.width - screen.style.ui(16)
            spacing: screen.style.ui(6)

            Row {
                spacing: screen.style.ui(8)

                // The ayah number is the play button for the whole ayah —
                // it is already the thing you point at to say "this one".
                Rectangle {
                    width: Math.max(screen.style.ui(24), numberLabel.implicitWidth + screen.style.ui(10))
                    height: screen.style.ui(22)
                    radius: screen.style.radiusSm
                    color: screen.playing === row.reference ? screen.style.accent : screen.style.raised

                    Label {
                        id: numberLabel
                        anchors.centerIn: parent
                        text: row.modelData.a
                        color: screen.playing === row.reference ? screen.style.bg : screen.style.muted
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(11)
                    }

                    TapHandler {
                        onTapped: screen.play(row.reference)
                    }

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                    }
                }
            }

            Flow {
                width: parent.width
                layoutDirection: Qt.RightToLeft
                spacing: screen.style.ui(10)

                Repeater {
                    model: row.wordList

                    delegate: Label {
                        required property var modelData

                        text: screen.wordHtml(modelData.segments)
                        textFormat: Text.RichText
                        color: screen.style.fg
                        font.family: screen.style.arabicFamily
                        font.pixelSize: screen.style.type(26)
                        lineHeight: 1.7
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

            Label {
                width: parent.width
                text: row.modelData.bn
                color: screen.style.muted
                wrapMode: Text.WordWrap
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(12)
            }
        }
    }

    Label {
        anchors.centerIn: parent
        visible: screen.loadError !== ""
        text: screen.loadError
        color: screen.style.red
        font.family: screen.style.fontFamily
        font.pixelSize: screen.style.type(13)
    }
}
