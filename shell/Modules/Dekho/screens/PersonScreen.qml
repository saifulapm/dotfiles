import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import "../components"
import "../DekhoModel.js" as Model

// A person, in TitleScreen's shape: the same hero band, the same back button,
// the same left column of one portrait and a few facts — and their filmography
// as a full PosterGrid rather than as a shelf, because "what else have they
// done" is a hundred cards and a shelf would answer it six at a time.
//
// The grid is a SIBLING of the left column, not something inside it, so the two
// scroll independently and there is no nested Flickable to argue about which
// one a wheel notch belongs to.
Item {
    id: screen

    required property var style

    property var person: null
    property bool loading: false
    property string error: ""
    // The two caches this page draws from: the credits' posters in w342 and the
    // portrait in w185, each a directory plus the set of files known to be in
    // it. See Dekho.qml's art-path section for why it is a set.
    property string posterDir: ""
    property var posterDone: ({})
    property string faceDir: ""
    property var faceDone: ({})

    function artPath(dir, done, path) {
        if (!path || !dir)
            return "";
        return done[path] === true ? dir + "/" + String(path).replace(/^\/+/, "") : "";
    }

    // Where the filmography cursor is, so the nav stack can put it back.
    property alias filmographyIndex: filmography.currentIndex

    signal titlePicked(var item)
    signal browseRequested
    signal dismissed

    readonly property var credits: person && person.credits ? person.credits : []
    readonly property string photoPath: artPath(faceDir, faceDone, person ? person.profile : "")
    readonly property int columnWidth: Math.min(style.ui(330), width * 0.28)

    function focusGrid() {
        filmography.focusGrid();
    }

    // FLAT, WHERE THE TITLE PAGE GETS omakade's HERO BAND — and the rule that
    // decides which is not taste, it is what the screen is made of.
    //
    // Everything on this page covers its own corners with a stroke painted in
    // the colour behind it: the portrait is a circle with FaceCard's ring, and
    // the filmography is a grid of PosterCards. Put an accent→blue wash behind
    // any of that and every one of those strokes becomes a visible dark notch —
    // measured on the first build, where the portrait had a black halo and each
    // poster in the top row had a dark L at every corner.
    //
    // So: a screen whose body is a grid is flat (this page and the library); a
    // screen whose body is a scrolling article gets the band (the title page,
    // where the only covered thing is far below it). A person has no backdrop
    // on TMDB anyway — the band here was never carrying art, only colour.
    Rectangle {
        anchors.fill: parent
        color: screen.style.bg
    }

    GlassButton {
        id: backButton

        anchors.top: parent.top
        anchors.left: parent.left
        anchors.margins: screen.style.ui(24)
        z: 2
        style: screen.style
        text: "BACK"
        iconText: "←"
        compact: true
        onClicked: screen.dismissed()
    }

    RowLayout {
        anchors.fill: parent
        anchors.topMargin: screen.style.ui(80)
        anchors.leftMargin: Math.max(screen.style.ui(28), parent.width * 0.055)
        anchors.rightMargin: Math.max(screen.style.ui(28), parent.width * 0.055)
        anchors.bottomMargin: screen.style.ui(22)
        spacing: Math.max(screen.style.ui(28), width * 0.045)

        ColumnLayout {
            Layout.preferredWidth: screen.columnWidth
            Layout.maximumWidth: screen.columnWidth
            Layout.alignment: Qt.AlignTop
            spacing: screen.style.ui(10)

            // The portrait, round, with FaceCard's 0.22 overhang cover — see
            // that file's header for why a circle does not take PosterCard's r.
            // Only safe here because the left column sits on the page colour by
            // the time it is drawn: the hero's scrim has landed on `bg` well
            // above it.
            Rectangle {
                id: portrait

                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: Math.min(screen.columnWidth, screen.style.ui(240))
                Layout.preferredHeight: Layout.preferredWidth
                radius: width / 2
                color: screen.style.raised

                Image {
                    anchors.fill: parent
                    source: screen.photoPath ? "file://" + screen.photoPath.split("/").map(encodeURIComponent).join("/") : ""
                    asynchronous: true
                    fillMode: Image.PreserveAspectCrop
                    sourceSize.width: Math.ceil(width * Math.max(1, Screen.devicePixelRatio))
                    visible: status === Image.Ready
                }

                Text {
                    textFormat: Text.PlainText
                    anchors.centerIn: parent
                    visible: screen.photoPath === ""
                    text: screen.person ? Model.initials(screen.person.name) : "?"
                    color: screen.style.muted
                    font.family: screen.style.fontFamily
                    font.pixelSize: Math.round(portrait.width * 0.3)
                    font.weight: Font.DemiBold
                }

                Rectangle {
                    readonly property int overhang: Math.max(1, Math.round(portrait.width * 0.22))

                    anchors.fill: parent
                    anchors.margins: -overhang
                    radius: width / 2
                    color: "transparent"
                    border.width: overhang + screen.style.hairline
                    border.color: screen.style.bg
                }

                Rectangle {
                    anchors.fill: parent
                    color: "transparent"
                    radius: parent.radius
                    border.width: screen.style.hairline
                    border.color: screen.style.alpha(screen.style.fg, 0.22)
                }
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                text: screen.person ? String(screen.person.name || "") : (screen.error !== "" ? "That person did not answer" : "Loading…")
                color: screen.style.brightFg
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(22)
                font.weight: Font.Bold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: text !== ""
                text: {
                    if (!screen.person)
                        return "";
                    const bits = [];
                    const life = Model.lifeLabel(screen.person);
                    if (life)
                        bits.push(life);
                    if (screen.person.known_for)
                        bits.push(String(screen.person.known_for));
                    return bits.join("  ·  ").toUpperCase();
                }
                color: screen.style.accent
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(10)
                font.weight: Font.DemiBold
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                visible: text !== ""
                text: screen.person && screen.person.place_of_birth ? String(screen.person.place_of_birth) : ""
                color: screen.style.muted
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(10)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: screen.style.ui(6)
                visible: screen.error !== ""
                text: screen.error
                color: screen.style.red
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(10)
                wrapMode: Text.Wrap
            }

            // A biography runs to a thousand words and this column is a column.
            // Capped and elided rather than given its own scroll area: the page
            // is here to answer "what else have they been in", and the grid
            // beside it is that answer.
            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.topMargin: screen.style.ui(6)
                text: screen.person ? String(screen.person.biography || "") : ""
                color: screen.style.fg
                opacity: 0.84
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(11)
                lineHeight: 1.45
                wrapMode: Text.Wrap
                maximumLineCount: 12
                elide: Text.ElideRight
            }

            GlassButton {
                Layout.fillWidth: true
                Layout.topMargin: screen.style.ui(6)
                visible: screen.person !== null
                style: screen.style
                compact: true
                text: "FILTER THE LIBRARY BY THEM"
                onClicked: screen.browseRequested()
            }

            Item {
                Layout.fillHeight: true
            }
        }

        ColumnLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: screen.style.ui(10)

            Text {
                textFormat: Text.PlainText
                text: "FILMOGRAPHY  ·  " + screen.credits.length
                color: screen.style.brightFg
                font.family: screen.style.fontFamily
                font.pixelSize: screen.style.type(14)
                font.weight: Font.Bold
                font.letterSpacing: 0.7
            }

            PosterGrid {
                id: filmography

                Layout.fillWidth: true
                Layout.fillHeight: true
                style: screen.style
                items: screen.credits
                pageColor: screen.style.bg
                posterDir: screen.posterDir
                posterDone: screen.posterDone
                emptyTitle: screen.loading ? "Asking TMDB" : "Nothing credited"
                emptyMessage: screen.loading ? "One `dekho api person` call, on its way." : "TMDB has no film or series credits for them."

                onActivated: index => screen.titlePicked(screen.credits[index])
            }
        }
    }
}
