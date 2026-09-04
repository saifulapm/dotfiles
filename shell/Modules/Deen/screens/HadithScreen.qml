import QtQuick
import QtQuick.Controls
import "../components"

// Search the hadith corpus — 36,512 narrations in ten collections, offline.
//
// A SEARCH SCREEN AND NOT A READER, deliberately. A browsable copy of the nine
// books is the argument that killed the Salat screen: it is a book rendered on
// a screen, and the printed one is better. What paper cannot do is answer "what
// was said about seeking forgiveness" in a fifth of a second, which is the only
// reason this room exists.
//
// Every card carries what makes it checkable: the collection, the number, the
// section it sits under, every grader's verdict UNDER THAT GRADER'S NAME, and a
// sunnah.com link. The graders disagree with each other — the same narration is
// Hasan Sahih to one and Isnaad Hasan to another — so collapsing them into a
// single word would be this shell taking a position it has no standing to take.
// Nothing on this screen is generated, ranked by a model, or summarised.
FocusScope {
    id: screen

    required property var style
    // {url, licence, numbering, verify, collections, hadiths}
    required property var source
    // [{slug, name, hadiths, bengali, graded, sections}]
    required property var collections
    // [{collection, name, section, url, hadith}]
    required property var hits
    required property int total
    required property string query
    // "" is every collection.
    required property string collection
    required property bool searching
    required property string loadError

    signal searched(string query)
    signal collectionPicked(string slug)
    signal opened(string url)

    // The search line is this screen's subject, so it takes the keyboard when
    // the room is entered — unlike the reader, where the page is the subject
    // and a focused text field would eat the space bar.
    function takeFocus() {
        search.forceActiveFocus();
    }

    function submit() {
        screen.searched(search.text.trim());
    }

    Column {
        id: header

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.top: parent.top
        anchors.topMargin: screen.style.ui(20)
        width: Math.min(parent.width - screen.style.pagePad * 2, screen.style.measure)
        spacing: screen.style.ui(12)

        SearchLine {
            id: search

            width: parent.width
            height: screen.style.ui(44)
            style: screen.style
            font.pixelSize: screen.style.type(14)
            placeholderText: "Search 36,000 narrations — type in English, Bangla or Arabic"
            onAccepted: screen.submit()
            onSteppedDown: list.forceActiveFocus()
        }

        // The collections, as a filter. A Flow rather than a Row because ten of
        // them plus "All" do not fit across a half-width window, and a Row does
        // not know that.
        Flow {
            width: parent.width
            spacing: screen.style.ui(5)

            GlassButton {
                style: screen.style
                text: "ALL"
                compact: true
                primary: screen.collection === ""
                onClicked: screen.collectionPicked("")
            }

            Repeater {
                model: screen.collections || []

                delegate: GlassButton {
                    required property var modelData

                    style: screen.style
                    // The names carry their own honorifics — "Sahih al Bukhari",
                    // "Sunan Abu Dawud" — which is four words of chrome per
                    // chip. The slug is what a citation says anyway.
                    text: modelData.slug.toUpperCase()
                    compact: true
                    primary: screen.collection === modelData.slug
                    Accessible.name: modelData.name
                    onClicked: screen.collectionPicked(modelData.slug)
                }
            }
        }

        // What was found, and where it all came from. The source line is not a
        // credit: it is the reason to believe the page.
        Item {
            width: parent.width
            height: Math.max(counts.height, provenance.height)
            visible: screen.loadError === ""

            Row {
                id: counts

                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                spacing: screen.style.ui(6)

                MetaChip {
                    style: screen.style
                    visible: screen.searching || screen.query !== ""
                    text: screen.searching ? "searching…" : screen.total === 0 ? "no matches" : screen.total === 1 ? "1 narration" : (screen.total + " narrations")
                }

                MetaChip {
                    style: screen.style
                    // Only when the list is short of the total, so it says
                    // something rather than repeating the chip beside it.
                    visible: !screen.searching && screen.hits.length > 0 && screen.total > screen.hits.length
                    text: "showing the first " + screen.hits.length
                }
            }

            Text {
                id: provenance
                textFormat: Text.PlainText

                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: screen.source ? (screen.source.hadiths + " narrations · " + screen.source.collections + " collections · numbering: " + screen.source.numbering) : ""
                color: screen.style.alpha(screen.style.muted, 0.75)
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(10)
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
        cacheBuffer: Math.max(0, height)
        model: screen.hits

        ScrollBar.vertical: ScrollBar {}

        delegate: Item {
            id: row

            required property var modelData

            readonly property var h: row.modelData.hadith
            readonly property real contentWidth: width - screen.style.ui(28)
            readonly property bool wide: contentWidth >= screen.style.ui(660)
            readonly property real arabicWidth: row.wide ? Math.round(row.contentWidth * 0.42) : row.contentWidth
            readonly property real proseWidth: row.wide ? row.contentWidth - row.arabicWidth - screen.style.ui(26) : row.contentWidth

            width: list.width - screen.style.ui(16)
            height: Math.max(prose.y + prose.height, arabic.y + arabic.height) + screen.style.ui(16)

            Rectangle {
                anchors.fill: parent
                radius: screen.style.radiusMd
                color: rowHover.hovered ? screen.style.alpha(screen.style.fg, 0.05) : screen.style.alpha(screen.style.fg, 0.025)

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

            Column {
                id: prose

                anchors.left: parent.left
                anchors.top: parent.top
                anchors.leftMargin: screen.style.ui(14)
                anchors.topMargin: screen.style.ui(12)
                width: row.proseWidth
                spacing: screen.style.ui(7)

                // The citation leads, because it is what makes the rest usable.
                Flow {
                    width: parent.width
                    spacing: screen.style.ui(5)

                    MetaChip {
                        style: screen.style
                        text: row.modelData.collection.toUpperCase() + " " + row.h.n
                        dotColor: screen.style.accent
                    }

                    MetaChip {
                        style: screen.style
                        visible: (row.modelData.section || "") !== ""
                        text: row.modelData.section || ""
                    }

                    // One chip per grader, never one chip for the hadith. In
                    // Bukhari and Muslim there are none at all, and that is not
                    // a gap: inclusion is the claim those two books make.
                    Repeater {
                        model: row.h.grades || []

                        delegate: MetaChip {
                            required property var modelData

                            style: screen.style
                            text: modelData.grade + " — " + modelData.by
                            dotColor: /^(sahih|hasan)/i.test(modelData.grade) ? screen.style.green : /daif|munkar|mawdu/i.test(modelData.grade) ? screen.style.yellow : screen.style.muted
                        }
                    }
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    text: row.h.en
                    color: screen.style.alpha(screen.style.fg, 0.92)
                    wrapMode: Text.WordWrap
                    font.family: screen.style.fontFamily
                    // A narration is a paragraph you read, not a caption you
                    // glance at — this and the Bangla under it are the screen.
                    font.pixelSize: screen.style.type(14)
                }

                Text {
                    textFormat: Text.PlainText
                    width: parent.width
                    visible: (row.h.bn || "") !== ""
                    text: row.h.bn || ""
                    color: screen.style.muted
                    wrapMode: Text.WordWrap
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(13)
                }

                // A citation you cannot check is an assertion. This is the
                // check, and it opens through app-run so the browser does not
                // die with the next shell restart.
                GlassButton {
                    style: screen.style
                    iconText: "󰖟"  // md-web
                    text: "sunnah.com"
                    compact: true
                    onClicked: screen.opened(row.modelData.url)
                }
            }

            Text {
                id: arabic
                textFormat: Text.PlainText

                anchors.right: parent.right
                anchors.top: parent.top
                anchors.rightMargin: screen.style.ui(14)
                anchors.topMargin: screen.style.ui(12)
                width: row.arabicWidth
                horizontalAlignment: Text.AlignRight
                wrapMode: Text.WordWrap
                text: row.h.ar
                color: screen.style.fg
                font.family: screen.style.arabicFamily
                font.pixelSize: screen.style.type(17)
                lineHeight: 1.15
            }
        }
    }

    // Three states that are not a list of results, and each says a different
    // thing: nothing typed yet, nothing found, nothing installed.
    EmptyState {
        anchors.centerIn: parent
        visible: screen.loadError === "" && !screen.searching && screen.query === "" && screen.hits.length === 0
        style: screen.style
        glyph: "⌕"
        title: "Search the nine books"
        message: "Type a phrase and press enter — English, Bangla, or Arabic without harakat. Everything is on this machine; nothing is sent anywhere."
    }

    EmptyState {
        anchors.centerIn: parent
        visible: screen.loadError === "" && !screen.searching && screen.query !== "" && screen.hits.length === 0
        style: screen.style
        glyph: "⌕"
        title: "Nothing matched"
        message: "This searches the words as you typed them, not their meanings. Try a shorter phrase, or another wording."
    }

    EmptyState {
        anchors.centerIn: parent
        visible: screen.loadError !== ""
        style: screen.style
        glyph: "󱠧"
        title: "The corpus is not installed"
        message: screen.loadError
    }
}
