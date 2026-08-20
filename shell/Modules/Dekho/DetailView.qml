import QtQuick
import "../../components"
import "DekhoModel.js" as Model

// One title, opened from a poster: the backdrop and the two things you came to
// do at the top, and everything you might then want to know below it —
// who is in it, what it is, which episode, and what else is like it.
// Everything arrives as properties; the hub owns the fetching, the navigation
// and the playback call.
//
// WHY IT SCROLLS, AND WHY IT SCROLLS THE WAY IT DOES. The first version was
// one screen: backdrop, overview, Play, episodes. A cast shelf, a facts block
// and a "More like this" rail do not fit on one screen at this type scale and
// should not try to. So the page is a Flickable over a PINNED backdrop: the
// hero's text scrolls up and away while the art stays, and an opaque sheet
// slides up over it. That is not decoration — the sheet being opaque and the
// page colour is what lets FaceTile round a face to a circle without a
// framebuffer per face (see its header), which is the difference between a
// cast shelf that costs one rectangle node per person and one that costs a
// render pass.
Item {
    id: detail

    required property var theme
    // The hub's module-local type scale (Dekho.qml `fonts`).
    required property var fonts
    property int edgePad: theme.space(10)
    // The hub's poster width — the shelves here are sized off it so a detail
    // page on a laptop panel and one on the desk are proportionate, not the
    // same page with different margins.
    property int posterWidth: theme.space(38)
    // The `dekho api title` object, or null while it is being fetched.
    property var title: null
    // `dekho api episodes` for `season`, and the season being shown.
    property var episodes: []
    property int season: 1
    property bool loadingEpisodes: false
    // The history entry for this title, when there is one — what turns
    // "Play" into "Resume S02E05".
    property var resume: null
    property string backdropDir: ""
    property string stillsDir: ""
    property bool stillsReady: false
    // Cast profiles at w185 and the similar-titles posters at w342: two more
    // prefetch calls, each landing independently of the other and of the
    // backdrop, so each guards on ITS OWN directory (doc §6).
    property string castDir: ""
    property bool castReady: false
    property string similarDir: ""
    property bool similarReady: false
    property string error: ""

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
    readonly property var crewList: title ? Model.leadCrew(title.crew) : []
    readonly property var similarList: title && title.similar ? title.similar : []
    readonly property var genreList: title && title.genres ? title.genres : []
    readonly property var factList: Model.factPairs(title)
    // Interleaved rather than split down the middle: with an odd number of
    // facts a split leaves the right column a row short of the left and the
    // block reads as broken.
    readonly property var factsLeft: factList.filter((f, i) => i % 2 === 0)
    readonly property var factsRight: factList.filter((f, i) => i % 2 === 1)
    readonly property string tagline: title && title.tagline ? String(title.tagline) : ""
    // The button appears only when dekho actually found a trailer. A Trailer
    // control that answers "no trailer" is worse than no control.
    readonly property bool hasTrailer: title !== null && String(title.trailer || "") !== ""

    // Guards on the DIRECTORY, not only on a ready flag. The poster, the
    // backdrop, the stills, the faces and the similar posters are five
    // different `dekho api prefetch` calls at three different sizes, landing
    // independently: with only a ready flag, one that arrived first builds
    // another's path against an empty directory and Qt goes looking for
    // `file:///x.jpg` at the filesystem root. Seen in the log before the first
    // two of these were guarded; the third size (w185) is the same trap.
    readonly property string backdropPath: backdropDir && title && title.backdrop ? backdropDir + "/" + String(title.backdrop).replace(/^\/+/, "") : ""

    // 16:9 episode stills, sized off the body type so they scale with the
    // screen the way everything else here does.
    readonly property int stillWidth: Math.round(fonts.heroBody * 9)
    readonly property int stillHeight: Math.round(stillWidth * 9 / 16)
    // Faces are capped near w185's own 185 px however wide the posters are:
    // past that the cache's profile is being upscaled, and a shelf of soft
    // faces is what a bigger number would buy. space(46) is 184 at the default
    // token, so the cap moves with a theme's density rather than being a
    // pixel constant.
    readonly property int faceWidth: Math.max(theme.space(24), Math.min(Math.round(posterWidth * 0.5), theme.space(46)))
    readonly property int similarWidth: Math.round(posterWidth * 0.62)
    // The hero keeps the shape the first design had — the top half of the
    // screen is the film — but a series gives up a little of it so the first
    // episode rows are visible without scrolling.
    readonly property int heroHeight: Math.round(height * (isSeries ? 0.52 : 0.58))

    // What the primary button does. A movie you are 40 minutes into resumes; a
    // series resumes at the episode history recorded, which is the next one
    // when you finished the last (dekho advances the entry itself).
    readonly property bool canResume: resume !== null && !(resume.finished && detail.isSeries === false) && Model.progressOf(resume) > 0.01
    readonly property string playLabel: {
        if (!title)
            return "Play";
        if (canResume && detail.isSeries)
            return "Resume " + Model.episodeCode(resume.season, resume.episode);
        if (canResume)
            return "Resume · " + Model.remainingLabel(resume.position, resume.duration);
        return detail.isSeries ? "Play S01E01" : "Play";
    }

    readonly property var actions: {
        const a = [
            {
                key: "play",
                glyph: "󰐊",
                label: detail.playLabel
            }
        ];
        if (detail.hasTrailer)
            a.push({
                key: "trailer",
                glyph: "󰎁",
                label: "Trailer"
            });
        return a;
    }

    // ------------------------------------------------------------ the cursor
    // One cursor over a page of bands. `sections` is the visible bands in
    // VISUAL ORDER, which is what makes Up and Down mean "the band above" and
    // "the band below" without a lookup table: Up and Down step between bands,
    // Left and Right walk the band you are in. The episode list is the one
    // vertical band, so there Up and Down walk the rows first and step out at
    // the ends — the tvOS rule, and the only one that does not strand a
    // twenty-row list behind a single keypress.
    //
    // Owned here rather than bound from the hub: the movers assign these, and
    // an assignment destroys an incoming binding.
    //
    // THE CURSOR IS A KEY, NOT AN INDEX. `sections` grows as the title's data
    // arrives — a page opens with only "actions" and gains "genres" ahead of it
    // the moment the genres land — so an index would silently mean a different
    // band a second after it was set, and the keyboard would be sitting on a
    // genre chip you never moved to. Seen live: the cursor jumped off Play
    // whenever the title answered slowly.
    property string section: "actions"
    property int cursor: 0
    readonly property int sectionIndex: Math.max(0, sections.indexOf(section))

    readonly property var sections: {
        const s = [];
        if (detail.genreList.length > 0)
            s.push("genres");
        s.push("actions");
        if (detail.isSeries && detail.seasons.length > 1)
            s.push("seasons");
        if (detail.isSeries)
            s.push("episodes");
        if (detail.castList.length > 0)
            s.push("cast");
        if (detail.crewList.length > 0)
            s.push("crew");
        if (detail.similarList.length > 0)
            s.push("similar");
        return s;
    }

    function sectionCount(key) {
        switch (key) {
        case "genres":
            return genreList.length;
        case "actions":
            return actions.length;
        case "seasons":
            return seasons.length;
        case "episodes":
            return episodes.length;
        case "cast":
            return castList.length;
        case "crew":
            return crewList.length;
        case "similar":
            return similarList.length;
        }
        return 0;
    }

    function isOn(key, index) {
        return section === key && cursor === index;
    }

    // The keyboard lands on Play, whatever else is on the page. Called by the
    // hub when it navigates here — NOT from onTitleChanged, which also fires
    // when a slow title finally answers and would then yank the cursor and the
    // scroll out from under whoever had already started moving.
    function resetCursor() {
        section = "actions";
        cursor = 0;
        scrollAnim.stop();
        page.contentY = 0;
    }

    // A new season is a new list; leaving the cursor on row 14 of a list that
    // now has six would silently point at nothing.
    onEpisodesChanged: {
        if (section === "episodes")
            cursor = 0;
    }

    // Follow the pointer, not the scroll (FilePicker's guard, shared by every
    // cursor in this module): a row or a card sliding under a stationary mouse
    // re-fires hover with the same scene position and must not steal the
    // cursor.
    property real hoverSceneX: -1
    property real hoverSceneY: -1

    function pointerMoved(sx, sy) {
        if (sx === hoverSceneX && sy === hoverSceneY)
            return false;
        hoverSceneX = sx;
        hoverSceneY = sy;
        return true;
    }

    // Hover moves the cursor but never scrolls: a page that jumped under a
    // stationary mouse because a shelf came into view would be unusable.
    function hoverTo(key, index, sx, sy) {
        if (!pointerMoved(sx, sy))
            return;
        if (sections.indexOf(key) < 0)
            return;
        section = key;
        cursor = index;
    }

    function moveSection(delta) {
        const next = sectionIndex + delta;
        if (next < 0 || next >= sections.length)
            return;
        section = sections[next];
        // Arriving at the episode list from below lands on its last row, so
        // Up and Down are each other's inverse across the whole page.
        cursor = delta < 0 && section === "episodes" ? Math.max(0, episodes.length - 1) : 0;
        revealCursor();
    }

    function stepVertical(delta) {
        if (section === "episodes") {
            const next = cursor + delta;
            if (next >= 0 && next < episodes.length) {
                cursor = next;
                revealCursor();
                return;
            }
        }
        moveSection(delta);
    }

    // Tab's mover. Unlike stepVertical it does not care what KIND of band it
    // is in — the episode list is walked one row at a time exactly like a cast
    // shelf is walked one face at a time — and unlike stepHorizontal it does
    // not stop at a band's edge. Landing on the far end of the band you arrive
    // at is what makes Tab and Shift+Tab exact inverses across a boundary.
    function stepLinear(delta) {
        const next = cursor + delta;
        if (next >= 0 && next < sectionCount(section)) {
            cursor = next;
            revealCursor();
            return;
        }
        const nextSection = sectionIndex + delta;
        if (nextSection < 0 || nextSection >= sections.length)
            return;
        section = sections[nextSection];
        cursor = delta < 0 ? Math.max(0, sectionCount(section) - 1) : 0;
        revealCursor();
    }

    function stepHorizontal(delta) {
        // The episode list has no horizontal axis; swallowing the key beats
        // letting it fall through to the hub and do something else.
        if (section === "episodes")
            return;
        cursor = Model.clampIndex(cursor + delta, sectionCount(section));
        revealCursor();
    }

    function activateCursor() {
        switch (section) {
        case "genres":
            if (cursor < genreList.length)
                detail.genrePicked(String(genreList[cursor]));
            return;
        case "actions":
            if (actions[cursor] && actions[cursor].key === "trailer")
                detail.trailerRequested();
            else
                playPrimary();
            return;
        case "seasons":
            if (seasons[cursor])
                detail.seasonPicked(seasons[cursor].number);
            return;
        case "episodes":
            if (episodes[cursor])
                detail.played(episodes[cursor].season, episodes[cursor].episode, false);
            return;
        case "cast":
            if (castList[cursor])
                detail.personPicked(castList[cursor]);
            return;
        case "crew":
            if (crewList[cursor])
                detail.personPicked(crewList[cursor]);
            return;
        case "similar":
            if (similarList[cursor])
                detail.titlePicked(similarList[cursor]);
            return;
        }
    }

    function playPrimary() {
        if (!title)
            return;
        if (canResume)
            detail.played(detail.isSeries ? resume.season : 0, detail.isSeries ? resume.episode : 0, true);
        else if (detail.isSeries)
            detail.played(1, 1, false);
        else
            detail.played(0, 0, false);
    }

    function handleKey(event) {
        // Tab flattens the page: it walks the band it is in and steps into the
        // next band at that band's end, so Play → Trailer → a genre chip → a
        // season → an episode → a face → a similar title is one order. The
        // arrows keep meaning "the thing above / to the left", which on a page
        // whose bands appear as their data lands is not the same journey.
        const tab = Model.tabDelta(event);
        if (tab !== 0) {
            stepLinear(tab);
            return true;
        }
        switch (event.key) {
        case Qt.Key_Up:
            stepVertical(-1);
            return true;
        case Qt.Key_Down:
            stepVertical(1);
            return true;
        case Qt.Key_Left:
            stepHorizontal(-1);
            return true;
        case Qt.Key_Right:
            stepHorizontal(1);
            return true;
        // The band-at-a-time escape hatch. Down walks the episode list row by
        // row, which is right when you are choosing an episode and wrong when
        // the cast shelf is thirteen keypresses below a season of Breaking
        // Bad — measured on exactly that page.
        case Qt.Key_PageDown:
            moveSection(1);
            return true;
        case Qt.Key_PageUp:
            moveSection(-1);
            return true;
        case Qt.Key_Home:
            resetCursor();
            return true;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            activateCursor();
            return true;
        }
        return false;
    }

    // --------------------------------------------------------------- scroll
    // Keyboard scrolling is an explicit animation rather than a Behavior on
    // contentY: a Behavior would also fight every flick and wheel event, which
    // is the classic way a scroll view starts feeling like syrup.
    NumberAnimation {
        id: scrollAnim

        target: page
        property: "contentY"
        duration: detail.theme.motion.standard
        easing.type: detail.theme.motion.easing
    }

    function scrollTo(y) {
        const max = Math.max(0, page.contentHeight - page.height);
        const to = Math.max(0, Math.min(max, y));
        if (Math.abs(to - page.contentY) < 1)
            return;
        scrollAnim.stop();
        scrollAnim.from = page.contentY;
        scrollAnim.to = to;
        scrollAnim.start();
    }

    // Flickable's built-in wheel step is a fixed pixel amount tuned for a
    // desktop scroll area, and on a page whose viewport is 1963 px of shelves
    // it takes more than a dozen notches to reach the bottom — the user's
    // verdict on the first build was "scrolling feels too slow". A notch here
    // is a quarter of the viewport, and it accumulates against the animation's
    // TARGET rather than its current position, so spinning the wheel does not
    // lose the distance the in-flight animation has not covered yet.
    function wheelScroll(delta) {
        const base = scrollAnim.running ? scrollAnim.to : page.contentY;
        scrollTo(base - delta);
    }

    function revealItem(item) {
        if (!item || !item.visible)
            return;
        const pad = detail.theme.space(8);
        const y = item.mapToItem(page.contentItem, 0, 0).y;
        const h = item.height;
        if (y - pad < page.contentY)
            scrollTo(y - pad);
        else if (y + h + pad > page.contentY + page.height)
            scrollTo(y + h + pad - page.height);
    }

    function revealCursor() {
        switch (section) {
        case "genres":
        case "actions":
            // Both live in the hero, which is the top of the page.
            scrollTo(0);
            return;
        case "seasons":
            revealItem(seasonBand);
            return;
        case "episodes":
            revealItem(episodeRepeater.itemAt(cursor));
            return;
        case "cast":
            castStrip.positionViewAtIndex(cursor, ListView.Contain);
            revealItem(castBand);
            return;
        case "crew":
            revealItem(factsBand);
            return;
        case "similar":
            similarRail.ensureVisible(cursor);
            revealItem(similarRail);
            return;
        }
    }

    // ---------------------------------------------------------- the backdrop
    // The page colour under everything, so the area below a short sheet is the
    // hub's surface and not whatever the window happens to clear to.
    Rectangle {
        anchors.fill: parent
        color: detail.theme.surface0
    }

    // PINNED to the hero band rather than filling the view: the sheet below
    // slides over it, so a backdrop the height of the screen would be paying
    // to decode pixels that are covered the moment anyone scrolls. Not clipped
    // (same reasoning as PosterTile); the scrims carry the text, one gradient
    // node each where a blur would be a framebuffer.
    Image {
        id: backdrop

        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: detail.heroHeight
        source: detail.backdropPath ? "file://" + detail.backdropPath.split("/").map(encodeURIComponent).join("/") : ""
        fillMode: Image.PreserveAspectCrop
        sourceSize.width: Math.min(width, 1600)
        asynchronous: true
        opacity: status === Image.Ready ? 0.62 : 0

        Behavior on opacity {
            NumberAnimation {
                duration: detail.theme.motion.slow
                easing.type: detail.theme.motion.easing
            }
        }
    }

    // Side ramp under the title block; bottom ramp landing ON the page colour
    // so the art dissolves into the sheet with no seam at rest.
    Rectangle {
        anchors.fill: backdrop
        gradient: Gradient {
            orientation: Gradient.Horizontal
            GradientStop {
                position: 0.0
                color: detail.theme.alpha(detail.theme.surface0, 0.88)
            }
            GradientStop {
                position: 0.62
                color: detail.theme.alpha(detail.theme.surface0, 0.2)
            }
            GradientStop {
                position: 1.0
                color: detail.theme.alpha(detail.theme.surface0, 0.0)
            }
        }
    }

    Rectangle {
        anchors.fill: backdrop
        gradient: Gradient {
            GradientStop {
                position: 0.0
                color: detail.theme.alpha(detail.theme.surface0, 0.42)
            }
            GradientStop {
                position: 0.35
                color: detail.theme.alpha(detail.theme.surface0, 0.0)
            }
            GradientStop {
                position: 0.78
                color: detail.theme.alpha(detail.theme.surface0, 0.6)
            }
            GradientStop {
                position: 1.0
                color: detail.theme.surface0
            }
        }
    }

    // ------------------------------------------------------------- the page
    Flickable {
        id: page

        anchors.fill: parent
        contentWidth: width
        contentHeight: sheet.y + sheet.height
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        // The bands are a handful of items and the shelves inside them are
        // ListViews that virtualize on their own; there is nothing here for a
        // cache buffer to help with.
        pixelAligned: true

        // The wheel is ours, not Flickable's — see wheelScroll(). Declared
        // inside the Flickable so it only claims wheel events over the page,
        // and it accepts them, so Flickable's own (much smaller) step never
        // runs as well.
        WheelHandler {
            acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
            onWheel: event => detail.wheelScroll(event.angleDelta.y / 120 * detail.height * 0.25)
        }

        // ------------------------------------------------------------- hero
        Item {
            id: heroBlock

            width: page.width
            height: detail.heroHeight

            Column {
                id: info

                anchors.left: parent.left
                anchors.bottom: parent.bottom
                anchors.leftMargin: detail.edgePad
                anchors.bottomMargin: detail.theme.space(7)
                width: Math.round(parent.width * 0.52)
                spacing: detail.theme.space(3)

                StyledText {
                    width: parent.width
                    theme: detail.theme
                    font.pixelSize: detail.fonts.hero
                    font.weight: Font.Bold
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: detail.title ? detail.title.title : "…"
                }

                // The tagline is the poster's line, not the synopsis — it
                // belongs against the title where a poster puts it, and it is
                // the one place in this module that is not the UI voice, so it
                // gets the italic that says so.
                StyledText {
                    width: parent.width
                    visible: detail.tagline !== ""
                    theme: detail.theme
                    font.pixelSize: detail.fonts.tagline
                    font.italic: true
                    color: detail.theme.alpha(detail.theme.textPrimary, 0.72)
                    wrapMode: Text.Wrap
                    maximumLineCount: 2
                    elide: Text.ElideRight
                    text: detail.tagline
                }

                // 2008 · Series · ★ 8.9 · 47m
                StyledText {
                    width: parent.width
                    visible: detail.title !== null
                    theme: detail.theme
                    font.pixelSize: detail.fonts.heroMeta
                    font.weight: Font.DemiBold
                    color: detail.theme.accent
                    elide: Text.ElideRight
                    text: {
                        if (!detail.title)
                            return "";
                        const bits = [Model.metaLine(detail.title)];
                        const d = Model.durationLabel(detail.title.runtime);
                        if (d)
                            bits.push(d);
                        return bits.filter(b => b !== "").join("  ·  ");
                    }
                }

                StyledText {
                    width: parent.width
                    visible: detail.error !== ""
                    theme: detail.theme
                    font.pixelSize: detail.fonts.meta
                    color: detail.theme.error
                    wrapMode: Text.Wrap
                    text: detail.error
                }

                StyledText {
                    width: parent.width
                    visible: detail.title !== null && detail.title.overview
                    theme: detail.theme
                    font.pixelSize: detail.fonts.heroBody
                    color: detail.theme.alpha(detail.theme.textPrimary, 0.85)
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                    text: detail.title ? detail.title.overview : ""
                }

                // The genres, as controls. They were a comma-joined tail on
                // the meta line, which is exactly the kind of text that looks
                // like it should be clickable and is not — now each one is a
                // chip that opens Browse filtered to it and this kind.
                Flow {
                    width: parent.width
                    visible: detail.genreList.length > 0
                    spacing: detail.theme.space(2)

                    Repeater {
                        model: detail.genreList

                        ActionChip {
                            required property var modelData
                            required property int index

                            theme: detail.theme
                            fonts: detail.fonts
                            label: String(modelData)
                            current: detail.isOn("genres", index)

                            onActivated: detail.genrePicked(String(modelData))
                            onEntered: (sx, sy) => detail.hoverTo("genres", index, sx, sy)
                        }
                    }
                }

                // ------------------------------------------------- the buttons
                // Play is the one loud element on the page — this is the button
                // the whole hub exists to reach. Trailer sits beside it as an
                // outline, because it is the smaller errand and two filled
                // pills would make neither of them primary.
                Item {
                    width: 1
                    height: detail.theme.space(2)
                }

                Row {
                    id: actionRow

                    spacing: detail.theme.space(3)

                    Repeater {
                        model: detail.actions

                        Rectangle {
                            id: pill

                            required property var modelData
                            required property int index

                            readonly property bool isPlay: pill.modelData.key === "play"
                            readonly property bool primed: detail.isOn("actions", pill.index)
                            readonly property color inkColor: pill.isPlay && pill.primed ? detail.theme.textOnAccent : detail.theme.textPrimary

                            width: pillRow.implicitWidth + detail.theme.space(12)
                            height: Math.round(detail.fonts.heroMeta * 2.4)
                            radius: height / 2
                            opacity: detail.title !== null ? 1 : 0.4
                            color: pill.isPlay ? (pill.primed ? detail.theme.accent : detail.theme.alpha(detail.theme.accent, 0.25)) : detail.theme.alpha(detail.theme.surface2, pill.primed ? 0.95 : 0.6)
                            border.width: pill.isPlay ? 0 : detail.theme.borderWidth
                            border.color: pill.primed ? detail.theme.accent : detail.theme.alpha(detail.theme.surface3, 0.8)

                            Behavior on color {
                                ColorAnimation {
                                    duration: detail.theme.motion.standard
                                    easing.type: detail.theme.motion.easing
                                }
                            }

                            Row {
                                id: pillRow

                                anchors.centerIn: parent
                                spacing: detail.theme.space(3)

                                OpticalGlyph {
                                    anchors.verticalCenter: parent.verticalCenter
                                    text: pill.modelData.glyph
                                    color: pill.inkColor
                                    pixelSize: detail.fonts.heroMeta
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    theme: detail.theme
                                    font.pixelSize: detail.fonts.heroMeta
                                    font.weight: Font.Bold
                                    color: pill.inkColor
                                    text: pill.modelData.label
                                }
                            }

                            HoverHandler {
                                enabled: detail.title !== null
                                cursorShape: Qt.PointingHandCursor
                                onPointChanged: {
                                    if (hovered)
                                        detail.hoverTo("actions", pill.index, point.scenePosition.x, point.scenePosition.y);
                                }
                            }

                            TapHandler {
                                enabled: detail.title !== null
                                onTapped: {
                                    if (pill.isPlay)
                                        detail.playPrimary();
                                    else
                                        detail.trailerRequested();
                                }
                            }
                        }
                    }
                }

                // In the hero rather than pinned to the corner: it scrolls
                // away with the block it explains, and the bottom of this page
                // belongs to the shelves.
                StyledText {
                    visible: detail.title !== null
                    theme: detail.theme
                    font.pixelSize: detail.fonts.hint
                    mono: true
                    muted: true
                    text: "↵ choose    ↑↓ move    pgup/pgdn band    esc back"
                }
            }
        }

        // ------------------------------------------------------------ sheet
        // Opaque, and the page colour: the corner covers in PosterTile and
        // FaceTile are painted in it, so anything but a flat known colour here
        // shows as a halo around every card. Also what the hero art scrolls
        // under.
        Rectangle {
            id: sheet

            y: heroBlock.height
            width: page.width
            height: sheetColumn.implicitHeight + detail.theme.space(12)
            color: detail.theme.surface0

            Column {
                id: sheetColumn

                width: parent.width
                spacing: detail.theme.space(7)

                // --------------------------------------------------- seasons
                Item {
                    id: seasonBand

                    width: parent.width
                    height: visible ? seasonFlow.implicitHeight : 0
                    visible: detail.isSeries && detail.seasons.length > 1

                    Flow {
                        id: seasonFlow

                        x: detail.edgePad
                        width: parent.width - detail.edgePad * 2
                        spacing: detail.theme.space(2)

                        Repeater {
                            model: seasonBand.visible ? detail.seasons : []

                            ActionChip {
                                required property var modelData
                                required property int index

                                theme: detail.theme
                                fonts: detail.fonts
                                label: "S" + Model.pad2(modelData.number)
                                chosen: modelData.number === detail.season
                                current: detail.isOn("seasons", index)

                                onActivated: detail.seasonPicked(modelData.number)
                                onEntered: (sx, sy) => detail.hoverTo("seasons", index, sx, sy)
                            }
                        }
                    }
                }

                // -------------------------------------------------- episodes
                // A Repeater, not a ListView: this list is inside a Flickable
                // and a nested vertical ListView fights it for every wheel
                // event. A season is a couple of dozen rows and each still
                // decodes at ~160 px wide, which is a fraction of what one
                // rail of posters costs — the virtualization the hub's rails
                // need is not what this band needs.
                Column {
                    id: episodeBand

                    width: parent.width
                    spacing: detail.theme.space(2)
                    visible: detail.isSeries

                    StyledText {
                        x: detail.edgePad
                        theme: detail.theme
                        font.pixelSize: detail.fonts.railTitle
                        font.weight: Font.DemiBold
                        text: "Episodes" + (detail.loadingEpisodes ? "  ·  loading…" : "")
                    }

                    StyledText {
                        x: detail.edgePad
                        visible: !detail.loadingEpisodes && detail.episodes.length === 0
                        theme: detail.theme
                        font.pixelSize: detail.fonts.cardTitle
                        muted: true
                        text: "TMDB lists no episodes for this season"
                    }

                    Repeater {
                        id: episodeRepeater

                        model: episodeBand.visible ? detail.episodes : []

                        CursorSurface {
                            id: row

                            required property var modelData
                            required property int index

                            // Capped rather than full-bleed: a row is a reading
                            // line (code, name, a two-line synopsis, a runtime),
                            // and stretched across a 3266 px content width the
                            // runtime column sat a metre from the text it
                            // belongs to.
                            x: detail.edgePad
                            width: Math.min(parent.width - detail.edgePad * 2, Math.round(parent.width * 0.62))
                            height: detail.stillHeight + detail.theme.space(4)
                            theme: detail.theme
                            current: detail.isOn("episodes", row.index)
                            bordered: false

                            // The episode you would resume into, marked so the
                            // list agrees with what the button above offers.
                            readonly property bool isResumePoint: detail.resume !== null && detail.resume.season === row.modelData.season && detail.resume.episode === row.modelData.episode

                            Row {
                                anchors.fill: parent
                                anchors.leftMargin: detail.theme.space(2)
                                anchors.rightMargin: detail.theme.space(3)
                                spacing: detail.theme.space(4)

                                // radius 4, not the tiles' 10: a still is small
                                // enough that the corner nub left outside a
                                // stroke-along-the-path is the measured ~1 px
                                // (doc §5), so it needs neither the oversized
                                // cover nor a framebuffer.
                                Rectangle {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: detail.stillWidth
                                    height: detail.stillHeight
                                    radius: detail.theme.radius(0.5)
                                    color: detail.theme.surface2

                                    Image {
                                        anchors.fill: parent
                                        source: detail.stillsReady && detail.stillsDir && row.modelData.still ? "file://" + (detail.stillsDir + "/" + String(row.modelData.still).replace(/^\/+/, "")).split("/").map(encodeURIComponent).join("/") : ""
                                        fillMode: Image.PreserveAspectCrop
                                        sourceSize.width: parent.width
                                        asynchronous: true
                                        visible: status === Image.Ready
                                    }

                                    StyledText {
                                        anchors.centerIn: parent
                                        theme: detail.theme
                                        font.pixelSize: detail.fonts.meta
                                        mono: true
                                        muted: true
                                        visible: !(detail.stillsReady && row.modelData.still)
                                        text: Model.episodeCode(row.modelData.season, row.modelData.episode)
                                    }

                                    Rectangle {
                                        anchors.fill: parent
                                        color: "transparent"
                                        radius: parent.radius
                                        border.width: detail.theme.borderWidth
                                        border.color: detail.theme.alpha(detail.theme.surface3, 0.6)
                                    }
                                }

                                Column {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: parent.width - detail.stillWidth - detail.theme.space(28)
                                    spacing: detail.theme.space(1)

                                    StyledText {
                                        width: parent.width
                                        theme: detail.theme
                                        font.pixelSize: detail.fonts.cardTitle
                                        font.weight: Font.DemiBold
                                        elide: Text.ElideRight
                                        color: row.isResumePoint ? detail.theme.accent : detail.theme.textPrimary
                                        text: Model.episodeCode(row.modelData.season, row.modelData.episode) + (row.modelData.name ? "  ·  " + row.modelData.name : "")
                                    }

                                    StyledText {
                                        width: parent.width
                                        visible: text !== ""
                                        theme: detail.theme
                                        font.pixelSize: detail.fonts.meta
                                        muted: true
                                        wrapMode: Text.Wrap
                                        maximumLineCount: 2
                                        elide: Text.ElideRight
                                        text: row.modelData.overview || ""
                                    }
                                }

                                StyledText {
                                    anchors.verticalCenter: parent.verticalCenter
                                    width: detail.theme.space(18)
                                    horizontalAlignment: Text.AlignRight
                                    theme: detail.theme
                                    font.pixelSize: detail.fonts.meta
                                    mono: true
                                    muted: true
                                    text: Model.durationLabel(row.modelData.runtime)
                                }
                            }

                            HoverHandler {
                                cursorShape: Qt.PointingHandCursor
                                onPointChanged: {
                                    if (hovered)
                                        detail.hoverTo("episodes", row.index, point.scenePosition.x, point.scenePosition.y);
                                }
                            }

                            TapHandler {
                                onTapped: detail.played(row.modelData.season, row.modelData.episode, false)
                            }
                        }
                    }
                }

                // ------------------------------------------------------ cast
                Column {
                    id: castBand

                    width: parent.width
                    spacing: detail.theme.space(3)
                    visible: detail.castList.length > 0

                    StyledText {
                        x: detail.edgePad
                        theme: detail.theme
                        font.pixelSize: detail.fonts.railTitle
                        font.weight: Font.DemiBold
                        text: "Cast"
                    }

                    Item {
                        width: parent.width
                        height: detail.faceWidth + detail.theme.space(2) + detail.fonts.labelZone + detail.theme.space(2)

                        // Horizontal, so it virtualizes across the axis it is
                        // long in — a fifty-name cast list instantiates the
                        // eight faces on screen, not fifty.
                        ListView {
                            id: castStrip

                            anchors.fill: parent
                            orientation: ListView.Horizontal
                            spacing: detail.theme.space(4)
                            leftMargin: detail.edgePad
                            model: castBand.visible ? detail.castList : []
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds
                            cacheBuffer: detail.faceWidth * 3

                            delegate: FaceTile {
                                required property var modelData
                                required property int index

                                theme: detail.theme
                                fonts: detail.fonts
                                // The tile is wider than the face it holds —
                                // FaceTile splits the difference into label
                                // room, which is where a full name fits.
                                width: Math.round(detail.faceWidth * 1.35)
                                name: modelData.name || ""
                                character: modelData.character || ""
                                photoPath: detail.castReady && detail.castDir && modelData.profile ? detail.castDir + "/" + String(modelData.profile).replace(/^\/+/, "") : ""
                                current: detail.isOn("cast", index)
                                coverColor: detail.theme.surface0

                                onActivated: detail.personPicked(modelData)
                                onEntered: (sx, sy) => detail.hoverTo("cast", index, sx, sy)
                            }
                        }
                    }
                }

                // ------------------------------------------------ crew + facts
                Column {
                    id: factsBand

                    width: parent.width
                    spacing: detail.theme.space(4)
                    visible: detail.crewList.length > 0 || detail.factList.length > 0

                    StyledText {
                        x: detail.edgePad
                        theme: detail.theme
                        font.pixelSize: detail.fonts.railTitle
                        font.weight: Font.DemiBold
                        text: "About"
                    }

                    // Crew as chips rather than as another shelf of faces: a
                    // director and two writers is three more w185 downloads and
                    // three more decoded pixmaps for names that read perfectly
                    // well as text — and as chips they are obviously the same
                    // kind of control the genres above are.
                    Flow {
                        x: detail.edgePad
                        width: parent.width - detail.edgePad * 2
                        spacing: detail.theme.space(2)

                        Repeater {
                            model: factsBand.visible ? detail.crewList : []

                            ActionChip {
                                required property var modelData
                                required property int index

                                theme: detail.theme
                                fonts: detail.fonts
                                label: modelData.job + " · " + modelData.name
                                current: detail.isOn("crew", index)

                                onActivated: detail.personPicked(modelData)
                                onEntered: (sx, sy) => detail.hoverTo("crew", index, sx, sy)
                            }
                        }
                    }

                    // Two columns of pairs. One column down a 3266 px page put
                    // every value against the right bezel, a metre from its
                    // label — the same mistake the episode rows were capped to
                    // avoid.
                    Row {
                        id: factColumns

                        readonly property int columnWidth: Math.round((width - detail.theme.space(10)) / 2)

                        x: detail.edgePad
                        width: Math.min(parent.width - detail.edgePad * 2, Math.round(parent.width * 0.62))
                        spacing: detail.theme.space(10)

                        Column {
                            width: factColumns.columnWidth
                            spacing: detail.theme.space(2)

                            Repeater {
                                model: detail.factsLeft

                                InfoPair {
                                    required property var modelData

                                    theme: detail.theme
                                    pixelSize: detail.fonts.meta
                                    label: modelData.label
                                    value: modelData.value
                                }
                            }
                        }

                        Column {
                            width: factColumns.columnWidth
                            spacing: detail.theme.space(2)

                            Repeater {
                                model: detail.factsRight

                                InfoPair {
                                    required property var modelData

                                    theme: detail.theme
                                    pixelSize: detail.fonts.meta
                                    label: modelData.label
                                    value: modelData.value
                                }
                            }
                        }
                    }
                }

                // --------------------------------------------- more like this
                Rail {
                    id: similarRail

                    width: parent.width
                    theme: detail.theme
                    fonts: detail.fonts
                    edgePad: detail.edgePad
                    gutter: Math.max(detail.theme.space(4), Math.round(width * 0.008))
                    tileWidth: detail.similarWidth
                    title: "More like this"
                    items: detail.similarList
                    postersReady: detail.similarReady
                    posterDir: detail.similarDir
                    currentIndex: detail.section === "similar" ? detail.cursor : -1

                    onEntered: (i, sx, sy) => detail.hoverTo("similar", i, sx, sy)
                    onActivated: i => {
                        if (detail.similarList[i])
                            detail.titlePicked(detail.similarList[i]);
                    }
                }
            }
        }
    }

    // Over the page, not in it: a back control that scrolled away would be the
    // one thing on the screen you cannot reach by scrolling to it.
    GlyphButton {
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.topMargin: detail.theme.space(6)
        anchors.leftMargin: detail.edgePad
        width: detail.theme.space(11)
        height: detail.theme.space(10)
        theme: detail.theme
        glyph: "󰁍"
        glyphSize: detail.fonts.heroMeta
        hint: "Back (Esc)"
        onActivated: detail.dismissed()
    }
}
