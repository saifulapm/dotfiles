import QtQuick
import QtQuick.Controls
import "../components"

// The day's adhkar, from Hisn al-Muslim, with the book's reference under each.
//
// NOTHING ON THIS SCREEN IS WRITTEN BY THIS PROJECT, and the layout says so
// rather than merely being true: every dua carries the footnote the book prints
// beneath it — "Al-Bukhari 1/181, Muslim 1/419" — in the same card, always, and
// the header names the book and the author. The rule the hub is built around is
// that generated text never stands alone as religious content, and the way to
// keep a rule like that is to make it structural: `deen dua list` reads a file
// that two independent copies of the page had to agree on at install, and this
// screen draws exactly what it answers.
//
// It opens on the morning-and-evening chapter, which is what "daily adhkar"
// means for someone rebuilding a practice, and the other 131 chapters are one
// press away in the same sheet the reader browses surahs with.
FocusScope {
    id: screen

    required property var style
    // {book, author, url, checked_against, duas, with_count_or_audio}
    required property var source
    // [{n, en, ar}] — the 132 chapters.
    required property var chapters
    // [{id, chapter, ar, tr, en, ref, count?, audio?}] — all 268 duas.
    required property var duas
    required property int chapter
    required property string loadError

    // The dua currently sounding, as the `dua:<id>` reference the player uses.
    required property string playing
    // Whether that is one dua or the whole chapter reciting itself.
    required property bool playingSet

    signal chapterStepped(int delta)
    signal chapterPicked(int n)
    signal play(string reference)
    signal playFrom(string reference)
    signal playChapter
    signal stopPlayback

    readonly property var meta: (screen.chapters || []).find(c => c.n === screen.chapter) || null
    readonly property var rows: (screen.duas || []).filter(d => d.chapter === screen.chapter)

    // The picker needs to say how long each chapter is, and the answer is in
    // the duas rather than in the chapter row — counted once here rather than
    // 132 times inside a delegate.
    readonly property var chapterRows: {
        const counts = {};
        for (const d of (screen.duas || []))
            counts[d.chapter] = (counts[d.chapter] || 0) + 1;
        return (screen.chapters || []).map(c => ({
                    n: c.n,
                    en: c.en,
                    ar: c.ar,
                    count: counts[c.n] || 0
                }));
    }

    // The window owns Escape, so it has to be told when a sheet is in front of
    // the page for Escape to mean instead. Same contract as the reader.
    readonly property bool sheetOpen: picker.open

    function closeSheet() {
        picker.open = false;
    }

    // The page follows the recitation, for the reason the reader does: a
    // highlight moving down a list you are not looking at is the same as no
    // highlight. Animated, and it stands down while you are dragging.
    onPlayingChanged: screen.followPlaying()

    function followPlaying() {
        if (screen.playing === "" || list.dragging || list.flicking)
            return;
        const index = screen.rows.findIndex(d => ("dua:" + d.id) === screen.playing);
        if (index < 0)
            return;
        const from = list.contentY;
        list.positionViewAtIndex(index, ListView.Center);
        const to = list.contentY;
        if (screen.style.slow <= 0 || Math.abs(to - from) < 1)
            return;
        list.contentY = from;
        follow.to = to;
        follow.restart();
    }

    NumberAnimation {
        id: follow

        target: list
        property: "contentY"
        duration: screen.style.slow
        easing.type: screen.style.easing
    }

    Column {
        id: header

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: screen.style.ui(20)
        width: Math.min(parent.width - screen.style.pagePad * 2, screen.style.measure)
        spacing: screen.style.ui(14)

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
                    enabled: screen.chapter > 1
                    Accessible.name: "Previous chapter"
                    onClicked: screen.chapterStepped(-1)
                }

                GlassButton {
                    style: screen.style
                    iconText: "▶"
                    enabled: screen.chapter < (screen.chapters || []).length
                    Accessible.name: "Next chapter"
                    onClicked: screen.chapterStepped(1)
                }

                // The title is the browse button here too — 132 chapters is
                // further than ▶ can reasonably carry anyone.
                GlassButton {
                    style: screen.style
                    iconText: "󰍜"  // md-menu
                    text: screen.meta ? (screen.meta.n + " · " + screen.meta.en.toUpperCase()) : "CHAPTERS"
                    Accessible.name: "Browse chapters"
                    onClicked: picker.open = true
                }

                // Adhkar are said as a set, not one at a time, so the set is
                // the primary action: press it in the morning and read along.
                GlassButton {
                    style: screen.style
                    primary: true
                    iconText: screen.playingSet ? "󰓛" : "󰐊"  // md-stop / md-play
                    text: screen.playingSet ? "Stop" : "Play"
                    enabled: screen.rows.some(d => d.audio !== undefined)
                    Accessible.name: screen.playingSet ? "Stop the recitation" : "Recite the whole chapter"
                    onClicked: screen.playingSet ? screen.stopPlayback() : screen.playChapter()
                }
            }

            Text {
                id: arabicName
                textFormat: Text.PlainText

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: screen.meta ? screen.meta.ar : ""
                color: screen.style.alpha(screen.style.fg, 0.85)
                font.family: screen.style.arabicFamily
                font.pixelSize: screen.style.type(20)
            }
        }

        // The book on the left, the three chapters a day actually needs on the
        // right. Naming the source in the chrome rather than in a tooltip is
        // the point: it is not a credit, it is the reason to trust the page.
        Item {
            width: parent.width
            height: Math.max(facts.height, quick.height)

            Flow {
                id: facts

                anchors.left: parent.left
                anchors.right: quick.left
                anchors.rightMargin: screen.style.ui(12)
                anchors.verticalCenter: parent.verticalCenter
                spacing: screen.style.ui(6)

                MetaChip {
                    style: screen.style
                    visible: screen.rows.length > 0
                    text: screen.rows.length === 1 ? "1 dua" : (screen.rows.length + " duas")
                }

                MetaChip {
                    style: screen.style
                    visible: screen.source !== null
                    text: screen.source ? screen.source.book : ""
                }

                MetaChip {
                    style: screen.style
                    visible: screen.source !== null
                    text: screen.source ? screen.source.author : ""
                }
            }

            Row {
                id: quick

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                spacing: screen.style.ui(5)

                Repeater {
                    model: [
                        {
                            n: 27,
                            label: "MORNING & EVENING"
                        },
                        {
                            n: 28,
                            label: "SLEEP"
                        },
                        {
                            n: 1,
                            label: "WAKING"
                        }
                    ]

                    delegate: GlassButton {
                        required property var modelData

                        style: screen.style
                        text: modelData.label
                        compact: true
                        primary: screen.chapter === modelData.n
                        onClicked: screen.chapterPicked(modelData.n)
                    }
                }
            }
        }

        Rectangle {
            width: parent.width
            height: screen.style.hairline
            color: screen.style.alpha(screen.style.muted, 0.18)
        }
    }

    ListView {
        id: list

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.topMargin: screen.style.ui(16)
        anchors.bottomMargin: screen.style.pagePad
        width: header.width
        clip: true
        spacing: screen.style.ui(6)
        // Clamped for the reason the reader's is: `height` is briefly negative
        // while the anchors resolve, and ListView rejects that rather than
        // ignoring it.
        cacheBuffer: Math.max(0, height)
        model: screen.rows

        ScrollBar.vertical: ScrollBar {}

        delegate: Item {
            id: row

            required property var modelData

            readonly property string reference: "dua:" + row.modelData.id
            readonly property bool sounding: screen.playing === row.reference
            readonly property bool hasAudio: row.modelData.audio !== undefined

            readonly property real contentWidth: width - badge.width - screen.style.ui(42)
            readonly property bool wide: contentWidth >= screen.style.ui(620)
            readonly property real arabicWidth: row.wide ? Math.round(row.contentWidth * 0.48) : row.contentWidth
            readonly property real proseWidth: row.wide ? row.contentWidth - row.arabicWidth - screen.style.ui(30) : row.contentWidth

            width: list.width - screen.style.ui(16)
            height: footnote.y + footnote.height + screen.style.ui(16)

            Rectangle {
                anchors.fill: parent
                radius: screen.style.radiusMd
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

            // The book's own number, and the play button when there is a
            // recitation matched to this dua. Eighteen of the 268 have none,
            // and those stay a number rather than a button that lies.
            Rectangle {
                id: badge

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: screen.style.ui(10)
                anchors.topMargin: screen.style.ui(14)
                width: Math.max(screen.style.ui(34), numberLabel.implicitWidth + screen.style.ui(14))
                height: screen.style.ui(28)
                radius: screen.style.radiusSm
                color: row.sounding ? screen.style.accent : badgeHover.hovered && row.hasAudio ? screen.style.alpha(screen.style.fg, 0.14) : screen.style.alpha(screen.style.fg, 0.06)
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
                    text: row.sounding ? "󰐊" : String(row.modelData.id)  // md-play
                    color: row.sounding ? screen.style.bg : screen.style.muted
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(11)
                    font.weight: Font.DemiBold
                }

                HoverHandler {
                    id: badgeHover
                    cursorShape: row.hasAudio ? Qt.PointingHandCursor : Qt.ArrowCursor
                }

                TapHandler {
                    enabled: row.hasAudio
                    onTapped: screen.playingSet ? screen.playFrom(row.reference) : screen.play(row.reference)
                }
            }

            // "×3" — the book says how many times, and a dua said once when it
            // is meant to be said three times is the commonest way to get an
            // adhkar wrong.
            Rectangle {
                anchors.horizontalCenter: badge.horizontalCenter
                anchors.top: badge.bottom
                anchors.topMargin: screen.style.ui(6)
                visible: (row.modelData.count || 1) > 1
                width: countLabel.implicitWidth + screen.style.ui(10)
                height: screen.style.ui(20)
                radius: screen.style.radiusSm
                color: screen.style.alpha(screen.style.accent, 0.14)

                Text {
                    id: countLabel
                    textFormat: Text.PlainText

                    anchors.centerIn: parent
                    text: "×" + (row.modelData.count || 1)
                    color: screen.style.accent
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(10)
                    font.weight: Font.DemiBold
                }
            }

            Text {
                id: arabic
                textFormat: Text.PlainText

                anchors.right: parent.right
                anchors.rightMargin: screen.style.ui(14)
                anchors.top: parent.top
                anchors.topMargin: screen.style.ui(12)
                width: row.arabicWidth
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
                text: row.modelData.ar
                color: screen.style.fg
                font.family: screen.style.arabicFamily
                font.pixelSize: screen.style.type(21)
                // 1.15 for the reason the reader's words are: Noto Naskh
                // already reserves about two ems of line box for the marks.
                lineHeight: 1.15
            }

            Column {
                id: prose

                anchors.left: badge.right
                anchors.leftMargin: screen.style.ui(14)
                anchors.top: row.wide ? parent.top : arabic.bottom
                anchors.topMargin: row.wide ? screen.style.ui(16) : screen.style.ui(10)
                width: row.proseWidth
                spacing: screen.style.ui(6)

                // The transliteration is the whole point for someone who cannot
                // yet read the line above it, so it leads and it is the one
                // that gets the brighter ink.
                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: row.modelData.tr !== ""
                    text: row.modelData.tr
                    color: screen.style.alpha(screen.style.fg, 0.9)
                    wrapMode: Text.WordWrap
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(12)
                    // Not italicised, though it wants to be: the theme's UI
                    // face draws an italic `l` as a script ell, and
                    // `Alhamdulillahi` is mostly ells.
                    font.letterSpacing: 0.3
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.modelData.en
                    color: screen.style.muted
                    wrapMode: Text.WordWrap
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(13)
                }
            }

            // THE FOOTNOTE, which is the reason this screen is allowed to
            // exist. It spans the card because it belongs to the whole dua and
            // not to one column of it, and it is never elided: a citation you
            // have to hover to finish reading is a citation being hidden.
            //
            // `y` rather than an anchor, because it sits under whichever of the
            // two columns is taller and anchors cannot say that.
            Text {
                id: footnote
                textFormat: Text.PlainText

                x: badge.x + badge.width + screen.style.ui(14)
                y: Math.max(prose.y + prose.height, arabic.y + arabic.height) + screen.style.ui(12)
                width: parent.width - x - screen.style.ui(14)
                text: row.modelData.ref
                color: screen.style.alpha(screen.style.muted, 0.78)
                wrapMode: Text.WordWrap
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(10)
            }
        }
    }

    EmptyState {
        anchors.centerIn: parent
        visible: screen.loadError !== ""
        style: screen.style
        glyph: "󱠧"
        title: "The duas are not installed"
        message: screen.loadError
    }

    DuaPicker {
        id: picker

        style: screen.style
        chapters: screen.chapterRows
        current: screen.chapter
        onPicked: n => screen.chapterPicked(n)
        onDismissed: picker.open = false
    }
}
