import QtQuick
import QtQuick.Layouts
import QtQuick.Window
import "../components"
import "../components/FocusNav.js" as FocusNav
import "../DekhoModel.js" as Model

// omakade's qml/screens/GameDetails.qml, band for band, in this module's
// vocabulary. Their order is kept because the order IS the design — the eye
// goes title, what it is, where else to read about it, what it is about, how to
// start it, and only then to the numbers:
//
//   PROTONDB / PCGAMINGWIKI      →  TMDB / IMDB / HOMEPAGE
//   LAUNCH WITH (installations)  →  SEASON chips
//   PLAY / FAVORITE / MANAGE     →  ▶ PLAY or ▶ RESUME S02E05, ▶ TRAILER
//   ORGANIZE (status/tags)       →  GENRES, as buttons that filter the library
//   3-up fact tiles              →  RUNTIME / RATING / STATUS / SEASONS / …
//   achievement progress meter   →  how far into it you are
//   the 2-column achievement list→  THE EPISODE LIST
//   (omakade has no equivalent)  →  CAST and MORE LIKE THIS, in its card language
//
// A Flickable rather than omakade's ScrollView: this module owes its pages a
// wheel notch of its own (doc §11 — "scrolling feels too slow"), and a
// ScrollView would bring back the scrollbar this design does not want.
Item {
    id: screen

    required property var style

    // The `dekho api title` payload, or null while it is in flight.
    property var title: null
    property var episodes: []
    property int season: 1
    property bool loadingEpisodes: false
    // The history row for this title, if there is one — what makes PLAY read
    // RESUME.
    property var resume: null
    property string error: ""

    // Three caches, one per TMDB size, each a directory plus the set of files
    // known to be in it. Posters, episode stills and the "more like this" shelf
    // all live in w342 and share one pair; faces are w185 and the backdrop is
    // w780. See Dekho.qml's art-path section for why this is a set and not a
    // per-batch "ready" flag.
    property string posterDir: ""
    property var posterDone: ({})
    property string faceDir: ""
    property var faceDone: ({})
    property string backdropDir: ""
    property var backdropDone: ({})

    function artPath(dir, done, path) {
        if (!path || !dir)
            return "";
        return done[path] === true ? dir + "/" + String(path).replace(/^\/+/, "") : "";
    }

    signal played(int season, int episode, bool fromResume)
    signal trailerRequested
    signal seasonPicked(int number)
    signal personPicked(var person)
    signal genrePicked(string genre)
    signal titlePicked(var item)
    signal dismissed

    readonly property bool isSeries: title !== null && title.kind === "tv"
    readonly property var seasons: title && title.seasons ? title.seasons : []
    readonly property var castList: title && title.cast ? title.cast : []
    readonly property var similarList: title && title.similar ? title.similar : []
    readonly property var genreList: title && title.genres ? title.genres : []
    readonly property var crewList: title ? Model.leadCrew(title.crew) : []

    // A film you are forty minutes into resumes; a series resumes at the
    // episode history recorded, which is the NEXT one when you finished the
    // last (dekho advances the entry itself).
    readonly property bool canResume: resume !== null && !(resume.finished && !screen.isSeries) && Model.progressOf(resume) > 0.01
    readonly property string playLabel: {
        if (!screen.title)
            return "PLAY";
        if (screen.canResume && screen.isSeries)
            return "RESUME " + Model.episodeCode(screen.resume.season, screen.resume.episode);
        if (screen.canResume)
            return "RESUME · " + Model.remainingLabel(screen.resume.position, screen.resume.duration).toUpperCase();
        return screen.isSeries ? "PLAY S01E01" : "PLAY";
    }

    readonly property string backdropPath: artPath(backdropDir, backdropDone, title ? title.backdrop : "")
    readonly property string posterPath: artPath(posterDir, posterDone, title ? title.poster : "")

    // omakade's own band heights, which is what makes the hero a band rather
    // than a page: 58% of the window or 500 px, whichever is less.
    readonly property int heroHeight: Math.min(height * 0.58, style.ui(500))

    // Built in DekhoModel.js, not here — see `titleFacts` for the qmlformat
    // crash that decides where a loop like this is allowed to live.
    readonly property var facts: Model.titleFacts(title)

    function focusPrimary() {
        if (playButton.visible && playButton.enabled)
            playButton.forceActiveFocus();
        else
            backButton.forceActiveFocus();
    }

    // PLAY DOES NOT EXIST YET when this screen arrives — `title` is null until
    // the `dekho api title` call answers, so the module's focusCurrentScreen()
    // finds only the BACK button and leaves the keyboard there. Focusing again
    // when the payload lands is the fix, and the guard is what stops it being a
    // focus thief: if anything has moved in the meantime, BACK no longer has it
    // and this does nothing.
    onTitleChanged: {
        if (screen.title && screen.visible && backButton.activeFocus)
            Qt.callLater(screen.focusPrimary);
    }

    // Tabbing off the bottom of a page this long has to move the page. omakade
    // hangs the same call off the window's activeFocusItemChanged; here the
    // screen only listens while it is the one on screen.
    function revealFocused(item) {
        if (item && FocusNav.isWithin(item, screen))
            FocusNav.revealInFlickable(page, item, screen.style.ui(16));
    }

    Connections {
        target: screen.Window.window
        enabled: screen.visible && target !== null

        function onActiveFocusItemChanged() {
            Qt.callLater(function () {
                screen.revealFocused(screen.Window.window.activeFocusItem);
            });
        }
    }

    Rectangle {
        anchors.fill: parent
        color: screen.style.bg
    }

    // The hero band, in omakade's three layers: a horizontal accent→blue wash
    // at 0.42, the backdrop over it at 0.48, and a vertical scrim that lands on
    // the page colour so the band has no bottom edge. No poster corner sits in
    // any of it — the left column's poster is drawn below the fold of the
    // scrim's landing — so this is one of the two places the discs can show.
    AmbientBackground {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: screen.heroHeight
        style: screen.style
        pageWidth: screen.width
        pageHeight: screen.height
    }

    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: screen.heroHeight
        opacity: 0.42
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: screen.style.accent
            }
            GradientStop {
                position: 1.0
                color: screen.style.blue
            }
        }
    }

    Image {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: screen.heroHeight
        source: screen.backdropPath ? "file://" + screen.backdropPath.split("/").map(encodeURIComponent).join("/") : ""
        asynchronous: true
        fillMode: Image.PreserveAspectCrop
        // w780 is the largest non-original TMDB size; decoded at most at the
        // width it is drawn at (doc §10 — `original` would make a navigation
        // step cost a 3–8 MB download).
        sourceSize.width: Math.min(width, 1600)
        opacity: status === Image.Ready ? 0.48 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: screen.style.slow
                easing.type: screen.style.easing
            }
        }
    }

    // omakade runs this to 62% where the band is 58%, so the art's own bottom
    // edge is covered by a scrim that has not finished. Here it ends ON the
    // band and reaches the page colour exactly there, because the page plate
    // inside the Flickable starts at the same line and any daylight between
    // them would be a visible seam straight across the page.
    Rectangle {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        height: screen.heroHeight
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: "transparent"
            }
            GradientStop {
                position: 1.0
                color: screen.style.bg
            }
        }
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

    Flickable {
        id: page

        // FULL WIDTH, with the page margin moved onto `body`. omakade insets the
        // scroll area itself, which is tidier and makes the fix below
        // impossible: the plate that covers the hero has to be as wide as the
        // hero, and a plate inside an inset viewport leaves the art showing down
        // both margins.
        readonly property real pad: Math.max(screen.style.ui(28), screen.width * 0.055)
        // Where the page turns opaque, in content coordinates: the line the
        // hero band ends on when nothing has been scrolled yet.
        readonly property real plateTop: Math.max(0, screen.heroHeight - y)

        anchors.fill: parent
        anchors.topMargin: screen.style.ui(80)
        anchors.bottomMargin: screen.style.ui(22)
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        contentWidth: width
        contentHeight: body.implicitHeight

        // A notch is the whole viewport. doc §11 settled this page on a
        // quarter, which was right when it was a hero and three shelves and is
        // not now that it carries a season of episodes, a cast shelf and a
        // similar shelf — "scrolling very slow" was the verdict here too.
        //
        // An explicit animation rather than a Behavior on contentY, which would
        // fight every flick (doc §11).
        NumberAnimation {
            id: pageScroll

            target: page
            property: "contentY"
            duration: screen.style.normal
            easing.type: screen.style.easing
        }

        WheelHandler {
            target: null
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            blocking: true

            onWheel: event => {
                const step = page.height * 1.0;
                const notches = event.pixelDelta.y !== 0 ? event.pixelDelta.y / step : event.angleDelta.y / 120;
                const max = Math.max(0, page.contentHeight - page.height);
                // Accumulated against the animation's TARGET, so spinning the
                // wheel does not throw away the distance an in-flight step has
                // not covered yet.
                const base = pageScroll.running ? pageScroll.to : page.contentY;
                const to = Math.max(0, Math.min(max, base - notches * step));
                if (Math.abs(to - page.contentY) >= 1) {
                    pageScroll.stop();
                    pageScroll.from = page.contentY;
                    pageScroll.to = to;
                    pageScroll.start();
                }
                event.accepted = true;
            }
        }

        // THE PAGE COVERS THE ART, the art does not scroll over the page.
        //
        // Everything below the hero is a translucent card — omakade's fact
        // tiles and episode rows are `alpha(foreground, 0.035)` fills, which is
        // what makes them read as glass on a flat page. Scroll them up into a
        // backdrop and they read as nothing at all: the first build put a
        // season of Breaking Bad over a bright still and the overviews vanished.
        //
        // So the art stays where it is and this opaque plate slides up over it,
        // which is doc §13's rule for the hub arrived at from the other side —
        // "a full-page plate that the opaque page progressively covers".
        Rectangle {
            y: page.plateTop
            width: page.contentWidth
            height: Math.max(page.height, body.implicitHeight - page.plateTop)
            color: screen.style.bg
        }

        // The plate's leading edge, dissolved over a FIXED depth rather than
        // left as a line. Scrolled halfway, a bare plate cuts the backdrop off
        // straight across the window — doc §13 hit exactly this on the hub's
        // collapsing hero and its answer is this one: "the art always dissolves
        // over the same distance, so the band's bottom edge is never an edge."
        Rectangle {
            y: page.plateTop - screen.style.ui(80)
            width: page.contentWidth
            height: screen.style.ui(80)
            gradient: Gradient {
                GradientStop {
                    position: 0.0
                    color: screen.style.alpha(screen.style.bg, 0.0)
                }
                GradientStop {
                    position: 1.0
                    color: screen.style.bg
                }
            }
        }

        RowLayout {
            id: body

            x: page.pad
            width: page.width - 2 * page.pad
            spacing: Math.max(screen.style.ui(28), width * 0.045)

            // ------------------------------------------------- the left column
            ColumnLayout {
                Layout.preferredWidth: Math.min(screen.style.ui(330), screen.width * 0.28)
                Layout.alignment: Qt.AlignTop
                spacing: screen.style.ui(8)

                // The one poster on this page that KEEPS omakade's clip. It
                // sits on the hero's gradient, where the corner cover cannot
                // work (it would paint four page-coloured notches over live
                // art), so it takes omakade's own trade instead: an
                // axis-aligned scissor and the square image corners doc §10
                // measured as invisible at this radius.
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: width * 1.5
                    radius: screen.style.radiusMd
                    clip: true
                    border.color: screen.style.alpha(screen.style.fg, 0.22)
                    gradient: Gradient {
                        orientation: Gradient.Horizontal
                        GradientStop {
                            position: 0.0
                            color: screen.style.accent
                        }
                        GradientStop {
                            position: 1.0
                            color: screen.style.blue
                        }
                    }

                    Image {
                        id: coverArtwork

                        anchors.fill: parent
                        source: screen.posterPath ? "file://" + screen.posterPath.split("/").map(encodeURIComponent).join("/") : ""
                        asynchronous: true
                        fillMode: Image.PreserveAspectCrop
                        sourceSize.width: Math.ceil(width * Math.max(1, Screen.devicePixelRatio))
                        sourceSize.height: Math.ceil(height * Math.max(1, Screen.devicePixelRatio))
                        opacity: status === Image.Ready ? 1 : 0
                    }

                    Rectangle {
                        visible: coverArtwork.status !== Image.Ready
                        width: parent.width * 0.95
                        height: width
                        radius: width / 2
                        x: parent.width * 0.44
                        y: -height * 0.18
                        color: screen.style.alpha(screen.style.brightFg, 0.10)
                    }

                    Text {
                        visible: coverArtwork.status !== Image.Ready
                        anchors.centerIn: parent
                        text: screen.title ? String(screen.title.title || "◇").substring(0, 1).toUpperCase() : "◇"
                        color: screen.style.alpha(screen.style.brightFg, 0.9)
                        font.family: screen.style.fontFamily
                        font.pixelSize: Math.max(screen.style.type(74), parent.width * 0.34)
                    }

                    Rectangle {
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.bottom: parent.bottom
                        height: parent.height * 0.34
                        gradient: Gradient {
                            GradientStop {
                                position: 0.0
                                color: "transparent"
                            }
                            GradientStop {
                                position: 1.0
                                color: screen.style.alpha(screen.style.bg, 0.84)
                            }
                        }
                    }
                }

                GlassButton {
                    Layout.fillWidth: true
                    visible: screen.title !== null && String(screen.title.trailer || "") !== ""
                    style: screen.style
                    compact: true
                    text: "TRAILER"
                    iconText: "▶"
                    onClicked: screen.trailerRequested()
                }

                // The crew a poster credits, under the poster where a poster
                // credits them. Faces would be a second shelf for four people;
                // buttons open the same person page a cast face does.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: screen.style.ui(8)
                    visible: screen.crewList.length > 0
                    spacing: screen.style.ui(7)

                    Text {
                        text: "CREW"
                        color: screen.style.muted
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(9)
                        font.weight: Font.DemiBold
                    }

                    Repeater {
                        model: screen.crewList

                        GlassButton {
                            required property var modelData

                            Layout.fillWidth: true
                            style: screen.style
                            compact: true
                            text: modelData.name.toUpperCase() + " · " + modelData.job.toUpperCase()
                            onClicked: screen.personPicked(modelData)
                        }
                    }
                }
            }

            // ------------------------------------------------ the right column
            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignTop
                spacing: screen.style.ui(16)

                Text {
                    Layout.fillWidth: true
                    text: screen.title ? (screen.title.title || "Unknown title") : (screen.error !== "" ? "That title did not answer" : "Loading…")
                    color: screen.style.brightFg
                    font.family: screen.style.fontFamily
                    font.pixelSize: Math.max(screen.style.type(28), Math.min(screen.style.type(54), screen.width * 0.045))
                    font.weight: Font.Bold
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    spacing: screen.style.ui(10)

                    Text {
                        text: screen.title ? Model.kindLabel(screen.title.kind).toUpperCase() : ""
                        color: screen.style.accent
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(11)
                        font.weight: Font.DemiBold
                    }
                    Text {
                        visible: screen.title !== null && screen.title.year
                        text: "·"
                        color: screen.style.alpha(screen.style.fg, 0.4)
                    }
                    // NOT `muted`, which is what omakade uses and what every
                    // other secondary line in this module uses. This one row
                    // sits ON the hero art rather than on the page, and muted
                    // over a bright backdrop is a year you cannot read — it was
                    // invisible on the first build's Spider-Man backdrop.
                    Text {
                        text: screen.title && screen.title.year ? String(screen.title.year) : ""
                        color: screen.style.fg
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(11)
                    }
                }

                Text {
                    Layout.fillWidth: true
                    visible: screen.error !== ""
                    text: screen.error
                    color: screen.style.red
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(11)
                    wrapMode: Text.Wrap
                }

                RowLayout {
                    spacing: screen.style.ui(8)
                    visible: screen.title !== null

                    GlassButton {
                        style: screen.style
                        compact: true
                        text: "TMDB"
                        onClicked: Qt.openUrlExternally("https://www.themoviedb.org/" + (screen.isSeries ? "tv/" : "movie/") + screen.title.id)
                    }
                    GlassButton {
                        visible: screen.title !== null && String(screen.title.imdb_id || "") !== ""
                        style: screen.style
                        compact: true
                        text: "IMDB"
                        onClicked: Qt.openUrlExternally("https://www.imdb.com/title/" + screen.title.imdb_id)
                    }
                    GlassButton {
                        visible: screen.title !== null && String(screen.title.homepage || "") !== ""
                        style: screen.style
                        compact: true
                        text: "HOMEPAGE"
                        onClicked: Qt.openUrlExternally(String(screen.title.homepage))
                    }
                }

                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: screen.style.ui(720)
                    visible: text !== ""
                    text: screen.title && screen.title.tagline ? String(screen.title.tagline) : ""
                    color: screen.style.fg
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(15)
                    font.italic: true
                    wrapMode: Text.Wrap
                }

                Text {
                    Layout.fillWidth: true
                    Layout.maximumWidth: screen.style.ui(720)
                    text: screen.title ? String(screen.title.overview || "") : ""
                    color: screen.style.fg
                    opacity: 0.84
                    font.family: screen.style.fontFamily
                    font.pixelSize: screen.style.type(13)
                    lineHeight: 1.45
                    wrapMode: Text.Wrap
                }

                // omakade's LAUNCH WITH, which is the same control: pick which
                // of several things the buttons below will act on.
                ColumnLayout {
                    Layout.fillWidth: true
                    visible: screen.seasons.length > 0
                    spacing: screen.style.ui(7)

                    Text {
                        text: "SEASON"
                        color: screen.style.muted
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(9)
                        font.weight: Font.DemiBold
                    }
                    Flow {
                        Layout.fillWidth: true
                        spacing: screen.style.ui(8)

                        Repeater {
                            model: screen.seasons

                            GlassButton {
                                required property var modelData

                                style: screen.style
                                compact: true
                                text: "S" + Model.pad2(modelData.number) + (modelData.episodes ? " · " + modelData.episodes + " EP" : "")
                                selected: screen.season === modelData.number
                                onClicked: screen.seasonPicked(modelData.number)
                            }
                        }
                    }
                }

                RowLayout {
                    spacing: screen.style.ui(10)

                    GlassButton {
                        id: playButton

                        visible: screen.title !== null
                        style: screen.style
                        text: screen.playLabel
                        iconText: "▶"
                        primary: true
                        onClicked: {
                            if (screen.canResume)
                                screen.played(screen.isSeries ? screen.resume.season : 0, screen.isSeries ? screen.resume.episode : 0, true);
                            else if (screen.isSeries)
                                screen.played(1, 1, false);
                            else
                                screen.played(0, 0, false);
                        }
                    }
                }

                // omakade's ORGANIZE row, and the one place doc §9's objection
                // does not apply: on a title page the kind is not ambiguous, so
                // a genre is a control rather than a comma-joined tail.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: screen.style.ui(8)
                    visible: screen.genreList.length > 0
                    spacing: screen.style.ui(9)

                    Text {
                        text: "GENRES"
                        color: screen.style.brightFg
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(11)
                        font.weight: Font.Bold
                        font.letterSpacing: 0.6
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: screen.style.ui(6)

                        Repeater {
                            model: screen.genreList

                            GlassButton {
                                required property string modelData

                                style: screen.style
                                compact: true
                                text: modelData.toUpperCase()
                                onClicked: screen.genrePicked(modelData)
                            }
                        }
                    }
                }

                GridLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: screen.style.ui(12)
                    columns: screen.width < screen.style.ui(1050) ? 1 : 3
                    columnSpacing: screen.style.ui(10)
                    rowSpacing: screen.style.ui(10)

                    Repeater {
                        model: screen.facts

                        StatTile {
                            required property var modelData

                            Layout.fillWidth: true
                            Layout.minimumWidth: screen.style.ui(150)
                            style: screen.style
                            label: modelData.label
                            value: modelData.value
                        }
                    }
                }

                MeterRow {
                    Layout.fillWidth: true
                    Layout.topMargin: screen.style.ui(12)
                    visible: screen.canResume
                    style: screen.style
                    // Gated on canResume, not on isSeries: `visible` does not
                    // stop a binding evaluating, so reading resume.season on a
                    // title with no history row threw every time one was opened.
                    label: screen.canResume && screen.isSeries ? "WATCHING " + Model.episodeCode(screen.resume.season, screen.resume.episode) : "WATCHED"
                    value: screen.canResume ? Model.progressOf(screen.resume) : 0
                }

                // WHERE OMAKADE PUTS ITS ACHIEVEMENTS. Two columns of small
                // cards with an icon, a name, a line of description and an
                // accent meta line — which is exactly the shape an episode
                // wants, with a 16:9 still where the icon was.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: screen.style.ui(18)
                    spacing: screen.style.ui(10)
                    visible: screen.isSeries

                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "EPISODES"
                            color: screen.style.brightFg
                            font.family: screen.style.fontFamily
                            font.pixelSize: screen.style.type(14)
                            font.weight: Font.Bold
                            font.letterSpacing: 0.7
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                        Text {
                            text: screen.loadingEpisodes ? "LOADING" : "SEASON " + Model.pad2(screen.season) + "  ·  " + screen.episodes.length
                            color: screen.style.accent
                            font.family: screen.style.fontFamily
                            font.pixelSize: screen.style.type(11)
                            font.weight: Font.DemiBold
                        }
                    }

                    GridLayout {
                        Layout.fillWidth: true
                        columns: screen.width < screen.style.ui(1160) ? 1 : 2
                        columnSpacing: screen.style.ui(10)
                        rowSpacing: screen.style.ui(10)

                        Repeater {
                            model: screen.episodes

                            Rectangle {
                                id: episodeCard

                                required property var modelData

                                readonly property bool isResumePoint: screen.resume !== null && screen.resume.season === episodeCard.modelData.season && screen.resume.episode === episodeCard.modelData.episode

                                Layout.fillWidth: true
                                Layout.minimumWidth: screen.style.ui(260)
                                Layout.preferredHeight: screen.style.ui(112)
                                radius: screen.style.radiusMd
                                color: screen.style.alpha(screen.style.fg, episodeFocus.activeFocus ? 0.09 : episodeCard.isResumePoint ? 0.075 : 0.035)
                                border.width: episodeFocus.activeFocus ? screen.style.ui(2) : screen.style.hairline
                                border.color: episodeFocus.activeFocus ? screen.style.accent : episodeCard.isResumePoint ? screen.style.alpha(screen.style.accent, 0.34) : screen.style.alpha(screen.style.fg, 0.10)

                                Behavior on color {
                                    ColorAnimation {
                                        duration: screen.style.normal
                                        easing.type: screen.style.easing
                                    }
                                }

                                FocusScope {
                                    id: episodeFocus

                                    anchors.fill: parent
                                    activeFocusOnTab: true
                                    Accessible.name: Model.episodeCode(episodeCard.modelData.season, episodeCard.modelData.episode) + " " + (episodeCard.modelData.name || "")
                                    Accessible.role: Accessible.Button

                                    Keys.onReturnPressed: event => {
                                        screen.played(episodeCard.modelData.season, episodeCard.modelData.episode, false);
                                        event.accepted = true;
                                    }
                                    Keys.onEnterPressed: event => {
                                        screen.played(episodeCard.modelData.season, episodeCard.modelData.episode, false);
                                        event.accepted = true;
                                    }
                                    Keys.onSpacePressed: event => {
                                        screen.played(episodeCard.modelData.season, episodeCard.modelData.episode, false);
                                        event.accepted = true;
                                    }

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.margins: screen.style.ui(11)
                                        spacing: screen.style.ui(12)

                                        // The still, 16:9. omakade's icon slot,
                                        // at the aspect an episode has. Clipped
                                        // like the hero poster and for the same
                                        // reason: it does not sit on a flat page.
                                        Rectangle {
                                            Layout.preferredWidth: screen.style.ui(154)
                                            Layout.preferredHeight: Math.round(screen.style.ui(154) * 9 / 16)
                                            radius: screen.style.radiusSm
                                            color: screen.style.alpha(screen.style.bg, 0.54)
                                            border.color: screen.style.alpha(screen.style.fg, 0.12)
                                            clip: true

                                            Image {
                                                anchors.fill: parent
                                                source: {
                                                    const p = screen.artPath(screen.posterDir, screen.posterDone, episodeCard.modelData.still);
                                                    return p ? "file://" + p.split("/").map(encodeURIComponent).join("/") : "";
                                                }
                                                asynchronous: true
                                                fillMode: Image.PreserveAspectCrop
                                                sourceSize.width: Math.ceil(width * Math.max(1, Screen.devicePixelRatio))
                                            }
                                        }

                                        ColumnLayout {
                                            Layout.fillWidth: true
                                            spacing: screen.style.ui(3)

                                            Text {
                                                Layout.fillWidth: true
                                                text: episodeCard.modelData.name || Model.episodeCode(episodeCard.modelData.season, episodeCard.modelData.episode)
                                                color: screen.style.brightFg
                                                font.family: screen.style.fontFamily
                                                font.pixelSize: screen.style.type(11)
                                                font.weight: Font.DemiBold
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                Layout.fillWidth: true
                                                text: String(episodeCard.modelData.overview || "")
                                                color: screen.style.muted
                                                font.family: screen.style.fontFamily
                                                font.pixelSize: screen.style.type(9)
                                                wrapMode: Text.Wrap
                                                maximumLineCount: 2
                                                elide: Text.ElideRight
                                            }
                                            Text {
                                                text: Model.episodeCode(episodeCard.modelData.season, episodeCard.modelData.episode) + (Model.durationLabel(episodeCard.modelData.runtime) ? "  ·  " + Model.durationLabel(episodeCard.modelData.runtime).toUpperCase() : "") + (episodeCard.modelData.air_date ? "  ·  AIRED " + Model.dateLabel(episodeCard.modelData.air_date).toUpperCase() : "")
                                                color: episodeCard.isResumePoint ? screen.style.accent : screen.style.alpha(screen.style.fg, 0.45)
                                                font.family: screen.style.fontFamily
                                                font.pixelSize: screen.style.type(8)
                                                font.weight: Font.DemiBold
                                            }
                                        }
                                    }

                                    MouseArea {
                                        anchors.fill: parent
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            episodeFocus.forceActiveFocus();
                                            screen.played(episodeCard.modelData.season, episodeCard.modelData.episode, false);
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                // CAST and MORE LIKE THIS. omakade has no equivalent band, so
                // they are built out of its own card language rather than out
                // of anything new: FaceCard is GameCard's focus model on a
                // circle, and the similar shelf is PosterCard at two thirds.
                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: screen.style.ui(18)
                    spacing: screen.style.ui(10)
                    visible: screen.castList.length > 0

                    Text {
                        text: "CAST"
                        color: screen.style.brightFg
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(14)
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: screen.style.ui(10)

                        Repeater {
                            model: screen.castList

                            FaceCard {
                                required property var modelData

                                width: screen.style.ui(150)
                                style: screen.style
                                pageColor: screen.style.bg
                                name: modelData.name || ""
                                character: modelData.character || ""
                                photoPath: screen.artPath(screen.faceDir, screen.faceDone, modelData.profile)
                                onActivated: screen.personPicked(modelData)
                            }
                        }
                    }
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: screen.style.ui(18)
                    Layout.bottomMargin: screen.style.ui(24)
                    spacing: screen.style.ui(10)
                    visible: screen.similarList.length > 0

                    Text {
                        text: "MORE LIKE THIS"
                        color: screen.style.brightFg
                        font.family: screen.style.fontFamily
                        font.pixelSize: screen.style.type(14)
                        font.weight: Font.Bold
                        font.letterSpacing: 0.7
                    }

                    Flow {
                        Layout.fillWidth: true
                        spacing: screen.style.ui(10)

                        Repeater {
                            model: screen.similarList

                            PosterCard {
                                required property var modelData

                                width: screen.style.ui(150)
                                height: Math.round(width * 1.5) + screen.style.ui(64)
                                style: screen.style
                                pageColor: screen.style.bg
                                title: modelData.title || ""
                                subtitle: modelData.year ? String(modelData.year) : ""
                                detail: Model.kindLabel(modelData.kind)
                                progress: 0
                                coverPath: screen.artPath(screen.posterDir, screen.posterDone, modelData.poster)
                                onActivated: screen.titlePicked(modelData)
                            }
                        }
                    }
                }
            }
        }
    }
}
