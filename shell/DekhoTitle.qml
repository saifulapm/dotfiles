import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
import "lib/dekho.mjs" as D
import "lib/dekho-title.mjs" as T

// Dekho's Title page: the image, overview, chips and people beside a series' seasons and episodes, the cursor on the episode next up.
FocusScope {
    id: page

    required property var dekho
    // The now-playing bar at its foot, for the state the checks read.
    property alias playingBar: nowBar

    readonly property var c: dekho.c
    readonly property var fonts: dekho.fonts
    readonly property var look: dekho.look
    readonly property string voice: dekho.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property bool caps: voice === "caps"
    readonly property var words: T.titleText(voice)
    readonly property string bodyFont: (bracket ? fonts.mono : fonts.ui) ?? ""

    // What Home opened, drawn at once; the backend's answer fills the rest in.
    property var entry: ({})
    property var detail: null
    // A season's number to its episodes, as each answer lands.
    property var bySeason: ({})
    property int season: 0
    property string zone: "episodes"
    property int row: 0
    property int crewCol: 0
    property int castCol: 0
    property string today: ""
    // Set once the poster's prefetch has answered, so the backdrop is asked for and drawn only for a title whose poster is not on disk, never before a poster that follows.
    property bool posterKnown: false
    // The title whose answers are awaited; an older title's answer is dropped.
    property string asked: ""
    // Set when a key hands over to a page still to come: a release list, a person, Browse.
    property var chose: null
    property var person: null
    property var filter: null
    // History's entry for this title while it is still being watched, else null; it adds Resume.
    property var seen: null
    property int button: 0
    readonly property var buttons: T.buttons(voice, seen, detail ? detail.trailer : null)

    readonly property var shown: detail || entry
    readonly property bool tv: shown.kind === "tv"
    readonly property var seasonNumbers: (detail && detail.seasons ? detail.seasons : []).map(s => s.number).filter(n => n > 0)
    readonly property var items: bySeason[season] || []
    readonly property int next: T.nextUp(items, today)
    // notableCrew keeps a person's id, name and role; the face comes from the title's own crew entry.
    readonly property var crew: {
        const all = detail && Array.isArray(detail.crew) ? detail.crew : [];
        return T.notableCrew(all).map(m => Object.assign({
                profile: (all.find(c => c.id === m.id) || {}).profile ?? null
            }, m));
    }
    readonly property var cast: detail && Array.isArray(detail.cast) ? detail.cast : []
    // The board shows three cast names; the cursor slides that window along the rest.
    readonly property int castStart: Math.max(0, Math.min(cast.length - 3, castCol - 2))
    readonly property var zones: ["buttons"].concat(tv ? ["seasons", "episodes"] : [], crew.length ? ["crew"] : [], cast.length ? ["cast"] : [])

    signal search
    // Enter chose an episode, or the movie: the release list opens over this page.
    signal release(var target)
    // Resume plays history's entry where it stopped, with no list.
    signal resume(var item)

    // The router keeps one Title page, so a title opened from a person's credits replaces this one; it keeps what was drawn and where the cursor was, to come back to.
    function snapshot() {
        return {
            entry: entry,
            detail: detail,
            bySeason: bySeason,
            season: season,
            zone: zone,
            row: row,
            crewCol: crewCol,
            castCol: castCol,
            posterKnown: posterKnown,
            today: today,
            seen: seen,
            button: button
        };
    }

    function restore(s) {
        asked = s.entry.kind + " " + s.entry.id;
        entry = s.entry;
        detail = s.detail;
        bySeason = s.bySeason;
        season = s.season;
        zone = s.zone;
        row = s.row;
        crewCol = s.crewCol;
        castCol = s.castCol;
        posterKnown = s.posterKnown;
        today = s.today;
        seen = s.seen;
        button = s.button;
    }

    function load(h) {
        entry = h;
        detail = null;
        bySeason = {};
        season = 0;
        // A movie opens on no person, so Enter chooses its release and tab reaches the people.
        zone = h.kind === "tv" ? "episodes" : "";
        row = 0;
        crewCol = 0;
        castCol = 0;
        posterKnown = false;
        seen = null;
        button = 0;
        chose = null;
        person = null;
        filter = null;
        today = Qt.formatDate(new Date(), "yyyy-MM-dd");
        const key = h.kind + " " + h.id;
        asked = key;
        dekho.api(["api", "title", "--id", String(h.id), "--kind", h.kind], answer => {
            if (page.asked !== key || !answer)
                return;
            page.detail = answer;
            page.dekho.prefetch("w342", [answer.poster], () => {
                if (page.asked !== key)
                    return;
                page.posterKnown = true;
                if (!page.dekho.picture("w342", answer.poster))
                    page.dekho.prefetch("w780", [answer.backdrop]);
            });
            page.dekho.prefetch("w185", page.crew.concat(page.cast).map(p => p.profile));
            page.loadSeasons(key, page.seasonNumbers);
        });
        refreshSeen();
    }

    // Resume shows from history, asked again when a play ends.
    function refreshSeen() {
        const key = asked;
        const h = entry;
        if (!h.id)
            return;
        dekho.api(["api", "history", "--limit", "20"], answer => {
            if (page.asked === key && answer)
                page.seen = T.watching(answer.items, h);
        });
    }

    // Every season at once, so the page can open on the one holding next up.
    function loadSeasons(key, numbers) {
        const got = {};
        numbers.forEach(n => {
            dekho.api(["api", "episodes", "--id", String(entry.id), "-s", String(n)], answer => {
                if (page.asked !== key)
                    return;
                got[n] = answer && Array.isArray(answer.items) ? answer.items : [];
                page.dekho.prefetch("w342", got[n].map(e => e.still));
                page.bySeason = Object.assign({}, page.bySeason, {
                    [n]: got[n]
                });
                if (Object.keys(got).length === numbers.length) {
                    page.season = T.startSeason(got, page.today);
                    page.row = Math.max(0, page.next);
                    episodeView.reveal(page.row);
                }
            });
        });
    }

    function moveSeason(by) {
        const at = seasonNumbers.indexOf(season);
        const to = seasonNumbers[Math.max(0, Math.min(seasonNumbers.length - 1, at + by))];
        if (to === undefined || to === season)
            return;
        season = to;
        row = Math.max(0, next);
        episodeView.reveal(row);
    }

    function moveRow(by) {
        zone = "episodes";
        row = Math.max(0, Math.min(items.length - 1, row + by));
        episodeView.reveal(row);
    }

    function moveCol(by) {
        if (zone === "crew")
            crewCol = Math.max(0, Math.min(crew.length - 1, crewCol + by));
        else
            castCol = Math.max(0, Math.min(cast.length - 1, castCol + by));
    }

    function choose() {
        if (zone === "buttons")
            press(buttons[button].id);
        else if (zone === "episodes" || (!tv && zone === ""))
            play();
        else if (zone === "crew" && crew[crewCol])
            openPerson(crew[crewCol]);
        else if (zone === "cast" && cast[castCol])
            openPerson(cast[castCol]);
        else if (zone === "seasons")
            zone = "episodes";
    }

    // Play opens the release list: a series' for the episode under the cursor, once it has aired.
    function play() {
        const ep = items[row];
        if (tv && ep && T.aired(ep, today)) {
            chose = {
                season: ep.season,
                episode: ep.episode
            };
            release({
                id: page.entry.id,
                kind: "tv",
                title: shown.title,
                season: ep.season,
                episode: ep.episode,
                name: ep.name,
                air_date: ep.air_date
            });
        } else if (!tv) {
            chose = {
                season: null,
                episode: null
            };
            release({
                id: page.entry.id,
                kind: shown.kind,
                title: shown.title
            });
        }
    }

    function resumeSeen() {
        if (!seen)
            return;
        chose = {
            resume: true
        };
        resume(Object.assign({}, seen, {
            title: shown.title
        }));
    }

    function press(id) {
        if (id === "play")
            play();
        else if (id === "resume")
            resumeSeen();
        else if (id === "trailer")
            playTrailer();
    }

    // t, and the Trailer button, play the title's trailer; a title without one has nothing to play.
    function playTrailer() {
        if (!detail || !detail.trailer)
            return;
        dekho.trailer({
            id: page.entry.id,
            kind: shown.kind,
            title: shown.title
        });
    }

    function openPerson(p) {
        person = p.id;
        dekho.open("person", {
            id: p.id,
            name: p.name
        });
    }

    // w marks the cursor's aired episode, or unmarks it; the mark redraws from the backend's answer.
    function toggleWatched() {
        const ep = items[row];
        if (zone !== "episodes" || !ep || !T.aired(ep, today))
            return;
        const key = asked;
        const s = season;
        const i = row;
        dekho.api(["api", "watched", "--id", String(entry.id), "-s", String(ep.season), "-e", String(ep.episode)].concat(ep.watched ? ["--unset"] : []), answer => {
            if (page.asked !== key || !answer || typeof answer.watched !== "boolean")
                return;
            const list = page.bySeason[s].slice();
            list[i] = Object.assign({}, list[i], {
                watched: answer.watched
            });
            page.bySeason = Object.assign({}, page.bySeason, {
                [s]: list
            });
            page.dekho.toast(answer.watched ? "Marked watched" : "Marked unwatched");
        });
    }

    function drawnList(repeater) {
        const out = [];
        for (let i = 0; i < repeater.count; i++)
            out.push(repeater.itemAt(i).drawn());
        return out;
    }

    function state() {
        const aired = drawnList(episodeRows).find(r => r.date !== "" && !r.dated);
        return {
            chose: chose,
            person: person,
            filter: filter,
            title: {
                tmdbId: entry.id ?? null,
                name: bigName.text,
                lines: bigName.lineCount,
                meta: metaText.text,
                side: sideText.text,
                chips: drawnList(chipRow),
                overview: {
                    text: overviewText.text,
                    lines: overviewText.lineCount,
                    truncated: overviewText.truncated,
                    maxLines: overviewText.maximumLineCount
                },
                buttons: drawnList(buttonRow),
                keys: drawnList(keyRow),
                crew: drawnList(crewRow),
                cast: drawnList(castRow),
                more: moreText.text,
                tabs: drawnList(tabRow),
                count: countText.text,
                zone: zone,
                season: season,
                cursor: items[row] ? items[row].episode : null,
                episodes: drawnList(episodeRows),
                episodesShown: episodeView.visible && episodeView.height > 0,
                layout: {
                    header: headRule.y,
                    blockTop: sideColumn.mapToItem(page, 0, 0).y,
                    nameTop: bigName.mapToItem(page, 0, 0).y
                },
                slot: (posterPicture.shown ? posterPicture : backdropPicture).drawn(),
                look: {
                    ink: String(c.ink),
                    muted: String(c.muted),
                    datedFont: aired ? aired.font : "",
                    datedItalic: aired ? aired.italic : false,
                    tabRadius: tabRow.count ? tabRow.itemAt(0).radius : -1,
                    hatch: hatch.visible,
                    cross: cross.visible,
                    icon: frameIcon.visible
                }
            }
        };
    }

    Item {
        id: keys
        anchors.fill: parent
        focus: true

        Keys.onPressed: event => {
            const k = event.key;
            const t = event.text;
            if (t === "/")
                page.search();
            else if (k === Qt.Key_Escape)
                page.dekho.back();
            else if (k === Qt.Key_Tab) {
                const z = page.zones;
                if (z.length)
                    page.zone = z[(z.indexOf(page.zone) + 1) % z.length];
            } else if (t === "j" || k === Qt.Key_Down)
                page.moveRow(1);
            else if (t === "k" || k === Qt.Key_Up)
                page.moveRow(-1);
            else if ((t === "l" || k === Qt.Key_Right) && page.zone === "buttons")
                page.button = Math.min(page.buttons.length - 1, page.button + 1);
            else if ((t === "h" || k === Qt.Key_Left) && page.zone === "buttons")
                page.button = Math.max(0, page.button - 1);
            else if (t === "l" || k === Qt.Key_Right)
                page.zone === "crew" || page.zone === "cast" ? page.moveCol(1) : page.moveSeason(1);
            else if (t === "h" || k === Qt.Key_Left)
                page.zone === "crew" || page.zone === "cast" ? page.moveCol(-1) : page.moveSeason(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                page.choose();
            else if (t === "r")
                page.resumeSeen();
            else if (t === "t")
                page.playTrailer();
            else if (t === "w")
                page.toggleWatched();
            else if (t === "f") {
                page.filter = {
                    kind: page.shown.kind,
                    genre: (page.shown.genres || [])[0] ?? null,
                    language: page.shown.language || null
                };
                // Browse filters a language by its code and names it from its own table.
                page.dekho.open("browse", Object.assign({
                    language_code: page.shown.language_code || null,
                    from: page.shown.title
                }, page.filter));
            } else
                return;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // The header as Home draws it, with the title's name where Home writes its own.
        RowLayout {
            Layout.fillWidth: true
            Layout.preferredHeight: plain ? 52 : -1
            Layout.leftMargin: plain ? 18 : 14
            Layout.rightMargin: plain ? 18 : 14
            Layout.topMargin: plain ? 0 : 12
            Layout.bottomMargin: plain ? 0 : 12
            spacing: plain ? 12 : 10

            Rectangle {
                implicitWidth: labelText.implicitWidth + (plain ? 18 : 0)
                implicitHeight: labelText.implicitHeight + (plain ? 6 : 0)
                radius: 8
                color: plain ? look.label.fill : "transparent"

                Text {
                    id: labelText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: words.label
                    color: plain ? c.accent ?? "blue" : c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: plain ? 12 : 10
                    font.weight: plain ? Font.Medium : Font.Normal
                    font.letterSpacing: plain ? 0 : 1.4
                }
            }
            Text {
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: D.title(page.shown.title)
                color: c.ink ?? "black"
                font.family: (caps ? fonts.display : page.bodyFont) ?? ""
                font.pixelSize: caps ? 18 : plain ? 14 : 12
                font.weight: caps ? Font.Normal : Font.Bold
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Rectangle {
                implicitWidth: pageText.implicitWidth + (plain ? 18 : 0)
                implicitHeight: pageText.implicitHeight + (plain ? 6 : 0)
                radius: 8
                color: plain ? look.tile.fill : "transparent"

                Text {
                    id: pageText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: words.page
                    color: c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: bracket ? 10 : 11
                    font.weight: plain ? Font.Medium : Font.Normal
                    font.letterSpacing: bracket ? 1.4 : 0
                }
            }
        }

        Rule {
            id: headRule
            Layout.fillWidth: true
            dashed: bracket
            color: caps ? c.ink ?? "black" : c.line ?? "gray"
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            Layout.leftMargin: 24
            Layout.rightMargin: 24
            Layout.topMargin: 16
            Layout.bottomMargin: 16
            spacing: 28

            ColumnLayout {
                id: sideColumn
                Layout.preferredWidth: 220
                Layout.minimumWidth: 220
                Layout.maximumWidth: 220
                Layout.alignment: Qt.AlignTop
                spacing: 12

                // The picture's place: the poster once it is on disk, else the backdrop, else each board's empty image, Paper's hatch, Artboard's grey tile and picture icon, Blueprint's crossed box.
                Rectangle {
                    id: placeholder
                    Layout.fillWidth: true
                    Layout.preferredHeight: 300
                    radius: plain ? 14 : 0
                    color: plain ? "#E9ECF1" : "transparent"
                    border.width: plain ? 0 : 1
                    border.color: (bracket ? c.accent : c.muted) ?? "gray"
                    clip: true

                    Shape {
                        id: hatch
                        anchors.fill: parent
                        visible: caps
                        preferredRendererType: Shape.GeometryRenderer

                        ShapePath {
                            strokeColor: page.c.line ?? "gray"
                            strokeWidth: 1
                            fillColor: "transparent"
                            PathSvg {
                                path: {
                                    let p = "";
                                    for (let x = 6; x < 520; x += 6)
                                        p += "M" + x + " 0L" + (x - 300) + " 300";
                                    return p;
                                }
                            }
                        }
                    }
                    Shape {
                        id: cross
                        anchors.fill: parent
                        visible: bracket
                        preferredRendererType: Shape.GeometryRenderer

                        ShapePath {
                            strokeColor: page.c.line ?? "gray"
                            strokeWidth: 1
                            fillColor: "transparent"
                            PathSvg {
                                path: "M0 0L220 300M220 0L0 300"
                            }
                        }
                    }
                    FilesIcon {
                        id: frameIcon
                        anchors.centerIn: parent
                        visible: plain
                        box: 40
                        size: 40
                        stroke: 1.5
                        path: "M6 1H34A5 5 0 0 1 39 6V24A5 5 0 0 1 34 29H6A5 5 0 0 1 1 24V6A5 5 0 0 1 6 1ZM5 25L14 15L21 22L26 17L35 25M31 9A3 3 0 1 1 25 9A3 3 0 1 1 31 9"
                        color: page.c.muted ?? "gray"
                    }
                    // The backdrop loads only once the poster is known not to be on disk, so the two never decode at once and a poster never follows a backdrop.
                    DekhoPicture {
                        id: backdropPicture
                        anchors.fill: parent
                        dekho: page.dekho
                        size: "w780"
                        path: !page.detail || !page.posterKnown || page.dekho.picture("w342", page.detail.poster) ? null : page.detail.backdrop
                        radius: placeholder.radius
                    }
                    DekhoPicture {
                        id: posterPicture
                        anchors.fill: parent
                        dekho: page.dekho
                        size: "w342"
                        path: page.detail ? page.detail.poster : null
                        radius: placeholder.radius
                    }
                }
                Text {
                    id: sideText
                    Layout.fillWidth: true
                    textFormat: Text.PlainText
                    text: D.title(T.sideText(voice, page.shown))
                    color: c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: bracket ? 10 : 11
                    font.letterSpacing: bracket ? 1.4 : 0
                    elide: Text.ElideRight
                    maximumLineCount: 1
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                spacing: plain ? 8 : 10

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Text {
                        id: bigName
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: D.title(page.shown.title)
                        color: c.ink ?? "black"
                        font.family: (caps ? fonts.display : page.bodyFont) ?? ""
                        font.pixelSize: caps ? 38 : plain ? 28 : 27
                        font.weight: caps ? Font.Normal : Font.Bold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        id: metaText
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: page.detail ? D.title(T.metaText(voice, page.detail)) : ""
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        font.letterSpacing: bracket ? 0.7 : 0
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }

                // Play, Resume while history holds the title, Trailer when it has one: buttons as the chips are drawn, the focused one as the release list draws its cursor.
                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Repeater {
                        id: buttonRow
                        model: page.buttons

                        Rectangle {
                            required property var modelData
                            required property int index
                            readonly property bool focused: page.zone === "buttons" && page.button === index
                            readonly property bool inverse: focused && !page.plain
                            function drawn() {
                                return {
                                    kind: modelData.id,
                                    text: buttonText.text,
                                    lines: buttonText.lineCount,
                                    focused: focused,
                                    radius: radius,
                                    fill: String(color)
                                };
                            }
                            implicitWidth: buttonText.implicitWidth + 24
                            implicitHeight: buttonText.implicitHeight + (page.plain ? 10 : 8)
                            radius: page.plain ? 8 : 0
                            color: focused ? (page.plain ? page.look.label.fill : page.bracket ? page.c.accent : page.c.ink) ?? "black" : page.plain ? page.look.tile.fill : "transparent"
                            border.width: focused && page.plain ? 1.5 : page.plain ? 0 : 1
                            border.color: (page.plain ? page.c.accent : page.bracket ? page.c.line : page.c.ink) ?? "gray"

                            Text {
                                id: buttonText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: D.title(modelData.text)
                                color: (parent.inverse ? page.c.surface : page.c.ink) ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: page.plain ? 13 : 12
                                font.weight: Font.Medium
                                font.letterSpacing: page.bracket ? 0.7 : 0
                                maximumLineCount: 1
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 6

                    Repeater {
                        id: chipRow
                        model: page.detail ? T.chips(page.detail) : []

                        Rectangle {
                            required property var modelData
                            function drawn() {
                                return {
                                    text: chipText.text,
                                    lines: chipText.lineCount
                                };
                            }
                            implicitWidth: chipText.implicitWidth + 20
                            implicitHeight: chipText.implicitHeight + (page.plain ? 6 : 4)
                            radius: page.plain ? 8 : 0
                            color: page.plain ? page.look.tile.fill : "transparent"
                            border.width: page.plain ? 0 : 1
                            border.color: (page.bracket ? page.c.line : page.c.muted) ?? "gray"

                            Text {
                                id: chipText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: D.title(modelData)
                                color: page.c.ink ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: page.plain ? 12 : 11
                                maximumLineCount: 1
                            }
                        }
                    }
                    Text {
                        Layout.leftMargin: 6
                        visible: chipRow.count > 0
                        textFormat: Text.PlainText
                        text: words.filters
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: bracket ? 10 : 11
                        font.letterSpacing: bracket ? 1.4 : 0
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                }

                // The overview wraps within the board's three lines and is elided past them, so the episodes keep their place.
                Text {
                    id: overviewText
                    Layout.fillWidth: true
                    Layout.maximumWidth: 640
                    textFormat: Text.PlainText
                    text: D.title(page.shown.overview)
                    color: c.ink ?? "black"
                    font.family: page.bodyFont
                    font.pixelSize: plain ? 14 : 13
                    lineHeight: 1.55
                    wrapMode: Text.Wrap
                    maximumLineCount: 3
                    elide: Text.ElideRight
                }

                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: plain ? 6 : 8

                    RowLayout {
                        Layout.fillWidth: true
                        visible: crewRow.count > 0
                        spacing: 6

                        Text {
                            Layout.preferredWidth: 48
                            textFormat: Text.PlainText
                            text: words.crew
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: plain ? 11 : 10
                            font.letterSpacing: plain ? 0 : 1.4
                        }
                        Repeater {
                            id: crewRow
                            model: page.crew

                            PersonChip {
                                name: modelData.name
                                role: modelData.role
                                focused: page.zone === "crew" && page.crewCol === index
                            }
                        }
                        Item {
                            Layout.fillWidth: true
                        }
                    }
                    RowLayout {
                        Layout.fillWidth: true
                        visible: castRow.count > 0
                        spacing: 6

                        Text {
                            Layout.preferredWidth: 48
                            textFormat: Text.PlainText
                            text: words.cast
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: plain ? 11 : 10
                            font.letterSpacing: plain ? 0 : 1.4
                        }
                        Repeater {
                            id: castRow
                            model: page.cast.slice(page.castStart, page.castStart + 3)

                            PersonChip {
                                name: modelData.name
                                role: modelData.character
                                focused: page.zone === "cast" && page.castCol === page.castStart + index
                            }
                        }
                        Text {
                            id: moreText
                            Layout.fillWidth: true
                            textFormat: Text.PlainText
                            text: words.more(page.cast.length - 3)
                            color: c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: bracket ? 10 : 11
                            font.letterSpacing: bracket ? 1.4 : 0
                            elide: Text.ElideRight
                            maximumLineCount: 1
                        }
                    }
                }

                // The seasons as tabs and the season's watched count.
                RowLayout {
                    Layout.fillWidth: true
                    Layout.topMargin: plain ? 2 : 4
                    visible: page.tv
                    spacing: 8

                    Repeater {
                        id: tabRow
                        model: page.seasonNumbers

                        Rectangle {
                            id: tab
                            required property var modelData
                            readonly property bool current: modelData === page.season
                            function drawn() {
                                return {
                                    text: tabText.text,
                                    current: current
                                };
                            }
                            implicitWidth: tabText.implicitWidth + (current && page.bracket ? 28 : 24)
                            implicitHeight: tabText.implicitHeight + (current && page.bracket ? 12 : 10)
                            radius: page.plain ? 10 : 0
                            color: page.plain ? (current ? page.look.label.fill : page.look.tile.fill) : current ? (page.bracket ? page.c.accent : page.c.ink) ?? "black" : "transparent"
                            border.width: page.plain || current ? 0 : 1
                            border.color: (page.bracket ? page.c.line : page.c.ink) ?? "black"

                            // The seasons' zone rings the current tab in the accent.
                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -3
                                visible: tab.current && page.zone === "seasons"
                                radius: tab.radius + 3
                                color: "transparent"
                                border.width: 1.5
                                border.color: page.c.accent ?? "red"
                            }
                            Text {
                                id: tabText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: "S" + tab.modelData
                                color: (tab.current ? (page.plain ? "#2638C9" : page.c.surface) : page.c.muted) ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: tab.current && page.caps ? 10 : tab.current && page.bracket ? 11 : 12
                                font.weight: tab.current && !page.caps ? (page.plain ? Font.Medium : Font.Bold) : Font.Normal
                                font.letterSpacing: tab.current && !page.plain ? 1.4 : page.bracket ? 0.7 : 0
                            }
                        }
                    }
                    Item {
                        Layout.fillWidth: true
                    }
                    Text {
                        id: countText
                        textFormat: Text.PlainText
                        text: page.items.length ? T.watchedText(voice, page.items) : ""
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: bracket ? 10 : 11
                        font.letterSpacing: bracket ? 1.4 : 0
                    }
                }

                // The season's episodes, scrolled without motion to keep the cursor's row in view.
                Flickable {
                    id: episodeView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    visible: page.tv
                    contentHeight: episodeColumn.implicitHeight
                    interactive: false
                    clip: true

                    function reveal(i) {
                        const r = episodeRows.itemAt(i);
                        if (!r)
                            return;
                        if (r.y < contentY)
                            contentY = r.y;
                        else if (r.y + r.height > contentY + height)
                            contentY = r.y + r.height - height;
                    }

                    Column {
                        id: episodeColumn
                        width: episodeView.width

                        Repeater {
                            id: episodeRows
                            model: page.items

                            EpisodeRow {
                                width: episodeColumn.width
                            }
                        }
                    }
                }

                // A film has no episodes to take the height; without a filler the page's layout spreads the spare height over the header and the keys too.
                Item {
                    Layout.fillHeight: true
                    visible: !page.tv
                }
            }
        }

        Rule {
            Layout.fillWidth: true
            dashed: bracket
            color: caps ? c.ink ?? "black" : c.line ?? "gray"
        }

        // While a film plays, the now-playing bar takes the keys' place.
        DekhoBar {
            id: nowBar
            Layout.fillWidth: true
            dekho: page.dekho
        }

        // The keys, as Home strips them.
        Flow {
            Layout.fillWidth: true
            visible: page.dekho.nowPlaying === null
            Layout.leftMargin: plain ? 14 : 16
            Layout.rightMargin: plain ? 14 : 16
            Layout.topMargin: plain ? 10 : 11
            Layout.bottomMargin: plain ? 10 : 11
            spacing: plain ? 8 : 16

            Repeater {
                id: keyRow
                model: page.look.keys(page.words.keys)

                Rectangle {
                    required property var modelData
                    function drawn() {
                        return [modelData.key, modelData.word];
                    }
                    implicitWidth: keyPair.implicitWidth + (page.plain ? 14 : 0)
                    implicitHeight: keyPair.implicitHeight + (page.plain ? 6 : 0)
                    radius: 6
                    color: page.plain ? page.look.tile.fill : "transparent"

                    Row {
                        id: keyPair
                        anchors.centerIn: parent
                        spacing: page.bracket ? 8 : 6

                        Text {
                            textFormat: Text.PlainText
                            text: modelData.key
                            color: (page.bracket ? page.c.accent : page.c.ink) ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: page.caps ? 10 : 11
                            font.weight: page.plain ? Font.Medium : Font.Bold
                            font.letterSpacing: page.caps ? 1 : page.bracket ? 1.5 : 0
                        }
                        Text {
                            textFormat: Text.PlainText
                            text: modelData.word
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: page.caps ? 10 : 11
                            font.letterSpacing: page.caps ? 1 : page.bracket ? 1.5 : 0
                        }
                    }
                }
            }
        }
    }

    // A one-pixel rule, solid, or dashed as Blueprint draws its rules.
    component Rule: Item {
        property bool dashed: false
        property color color: "black"
        implicitHeight: 1

        Rectangle {
            anchors.fill: parent
            visible: !parent.dashed
            color: parent.color
        }
        Dashed {
            anchors.fill: parent
            visible: parent.dashed
            color: parent.color
        }
    }

    // A person as a button: a face's place, the name underlined, the job or part beside it.
    component PersonChip: Rectangle {
        id: chip

        required property var modelData
        required property int index
        property string name: ""
        property string role: ""
        property bool focused: false

        function drawn() {
            return {
                name: nameText.text,
                role: roleText.text,
                lines: nameText.lineCount,
                focused: focused,
                face: face.drawn()
            };
        }

        implicitWidth: chipBody.implicitWidth + 14
        implicitHeight: 26
        radius: page.plain ? 13 : 0
        color: page.plain ? "#F6F7F9" : "transparent"
        border.width: focused ? 1.5 : page.plain ? 0 : 1
        border.color: (focused ? page.c.accent : page.bracket ? page.c.line : "#B9AE99") ?? "gray"

        Row {
            id: chipBody
            anchors.left: parent.left
            anchors.leftMargin: 4
            anchors.verticalCenter: parent.verticalCenter
            spacing: 7

            Rectangle {
                width: 20
                height: 20
                radius: page.plain ? 10 : 0
                color: page.plain ? "#E9ECF1" : page.bracket ? page.c.surface ?? "black" : "transparent"
                border.width: page.plain ? 0 : 1
                border.color: (page.bracket ? page.c.line : page.c.muted) ?? "gray"
                clip: true

                Shape {
                    anchors.fill: parent
                    visible: page.caps
                    preferredRendererType: Shape.GeometryRenderer

                    ShapePath {
                        strokeColor: page.c.line ?? "gray"
                        strokeWidth: 1
                        fillColor: "transparent"
                        PathSvg {
                            path: "M6 0L0 6M12 0L0 12M18 0L0 18M24 0L4 20M30 0L10 20M36 0L16 20"
                        }
                    }
                }
                DekhoPicture {
                    id: face
                    anchors.fill: parent
                    dekho: page.dekho
                    size: "w185"
                    path: chip.modelData.profile
                    radius: parent.radius
                }
            }
            Text {
                id: nameText
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: D.title(chip.name)
                color: page.c.ink ?? "black"
                font.family: page.bodyFont
                font.pixelSize: 12
                font.weight: Font.Medium
                font.underline: true
                elide: Text.ElideRight
                maximumLineCount: 1
                width: Math.min(implicitWidth, 160)
            }
            Text {
                id: roleText
                anchors.verticalCenter: parent.verticalCenter
                textFormat: Text.PlainText
                text: page.bracket ? D.title(chip.role).toUpperCase() : D.title(chip.role)
                color: page.c.muted ?? "gray"
                font.family: page.bodyFont
                font.pixelSize: page.bracket ? 10 : 11
                font.letterSpacing: page.bracket ? 1.4 : 0
                elide: Text.ElideRight
                maximumLineCount: 1
                width: Math.min(implicitWidth, 140)
            }
        }
    }

    // One episode: its watched mark, number, name, the next-up tag, length and air date; one still to air is dimmed.
    component EpisodeRow: Rectangle {
        id: ep

        required property var modelData
        required property int index
        readonly property bool cursor: page.row === index
        readonly property bool due: T.aired(modelData, page.today)
        readonly property bool up: page.next === index
        readonly property bool done: !!modelData.watched
        // The cursor's row inverts in Paper and Blueprint; Artboard tints it and rings it in its accent.
        readonly property bool inverse: cursor && !page.plain
        readonly property color fore: inverse ? page.c.surface ?? "white" : page.c.ink ?? "black"
        readonly property color soft: inverse ? (page.caps ? page.c.line : page.c.surface) ?? "white" : page.c.muted ?? "gray"

        function drawn() {
            return {
                episode: modelData.episode,
                name: nameText.text,
                lines: nameText.lineCount,
                tag: tag.visible ? tagText.text : "",
                date: dateText.text,
                dated: !due,
                font: dateText.font.family,
                italic: dateText.font.italic,
                watched: tick.visible,
                color: String(nameText.color),
                cursor: cursor,
                still: still.drawn()
            };
        }

        height: 30
        radius: page.plain ? 10 : 0
        color: cursor ? (page.plain ? page.look.label.fill : page.bracket ? page.c.accent : page.c.ink) ?? "black" : "transparent"
        border.width: cursor && page.plain ? 1.5 : 0
        border.color: page.c.accent ?? "blue"

        RowLayout {
            anchors.fill: parent
            anchors.leftMargin: 12
            anchors.rightMargin: 12
            spacing: 12

            // The mark: filled with a tick when watched, an outline when not, dashed when it has not aired.
            Item {
                Layout.preferredWidth: 22
                Layout.preferredHeight: 18

                Rectangle {
                    id: tick
                    width: 18
                    height: 18
                    visible: ep.done
                    radius: page.plain ? 9 : 0
                    color: (page.plain ? page.c.accent : page.bracket ? (ep.inverse ? page.c.surface : page.c.accent) : ep.inverse ? page.c.surface : page.c.ink) ?? "black"

                    FilesIcon {
                        anchors.centerIn: parent
                        size: page.plain ? 9 : 10
                        box: page.plain ? 9 : 16
                        stroke: page.plain ? 1.5 : 2.4
                        path: page.plain ? "M1.5 4.6L3.5 6.6L7.5 2.4" : "M3.5 8.5L6.5 11.5L12.5 4.5"
                        color: (page.plain ? "white" : ep.inverse ? (page.bracket ? page.c.accent : page.c.ink) : page.c.surface) ?? "white"
                    }
                }
                Rectangle {
                    width: 18
                    height: 18
                    visible: !ep.done && ep.due
                    radius: page.plain ? 9 : 0
                    color: "transparent"
                    border.width: page.bracket ? 1 : 1.5
                    border.color: (page.plain ? page.c.line : ep.fore) ?? "gray"
                }
                Dashed {
                    width: 18
                    height: 18
                    visible: !ep.done && !ep.due && !page.plain
                    frame: true
                    color: ep.soft
                }
                // Artboard's mark is a circle, so its dashed one is too.
                Shape {
                    width: 18
                    height: 18
                    visible: !ep.done && !ep.due && page.plain
                    preferredRendererType: Shape.GeometryRenderer

                    ShapePath {
                        strokeColor: page.c.line ?? "gray"
                        strokeWidth: 1.5
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [2, 2]
                        fillColor: "transparent"
                        PathAngleArc {
                            centerX: 9
                            centerY: 9
                            radiusX: 8.25
                            radiusY: 8.25
                            sweepAngle: 360
                        }
                    }
                }
            }
            // The still's place, marked as each board marks an empty picture: Paper's hatch, Artboard's grey tile, Blueprint's crossed box.
            Rectangle {
                id: stillPlace
                Layout.preferredWidth: 40
                Layout.preferredHeight: 22
                radius: page.plain ? 4 : 0
                color: page.plain ? "#E9ECF1" : "transparent"
                border.width: page.plain ? 0 : 1
                border.color: (page.bracket ? page.c.line : page.c.muted) ?? "gray"
                clip: true

                Shape {
                    anchors.fill: parent
                    visible: !page.plain
                    preferredRendererType: Shape.GeometryRenderer

                    ShapePath {
                        strokeColor: page.c.line ?? "gray"
                        strokeWidth: 1
                        fillColor: "transparent"
                        PathSvg {
                            path: page.bracket ? "M0 0L40 22M40 0L0 22" : "M6 0L0 6M12 0L0 12M18 0L0 18M24 0L2 22M30 0L8 22M36 0L14 22M42 0L20 22M48 0L26 22M54 0L32 22M60 0L38 22"
                        }
                    }
                }
                DekhoPicture {
                    id: still
                    anchors.fill: parent
                    dekho: page.dekho
                    size: "w342"
                    path: ep.modelData.still
                    radius: stillPlace.radius
                }
            }
            Text {
                Layout.preferredWidth: 28
                textFormat: Text.PlainText
                text: "E" + ep.modelData.episode
                color: ep.inverse && page.bracket ? ep.fore : ep.soft
                font.family: page.bodyFont
                font.pixelSize: 12
                font.letterSpacing: page.bracket ? 0.7 : 0
            }
            Text {
                id: nameText
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: D.title(ep.modelData.name)
                color: !ep.due ? page.c.muted ?? "gray" : ep.cursor && page.plain ? "#2638C9" : ep.fore
                font.family: page.bodyFont
                font.pixelSize: page.plain ? 14 : 13
                font.weight: ep.cursor ? (page.bracket ? Font.Bold : Font.Medium) : Font.Normal
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Rectangle {
                id: tag
                visible: ep.up
                implicitWidth: tagText.implicitWidth + (page.bracket ? 0 : page.plain ? 16 : 12)
                implicitHeight: tagText.implicitHeight + (page.bracket ? 0 : page.plain ? 4 : 2)
                radius: page.plain ? 8 : 0
                color: page.bracket ? "transparent" : (page.plain ? page.c.ink : ep.inverse ? page.c.surface : page.c.ink) ?? "black"

                Text {
                    id: tagText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: words.nextUp
                    color: (page.bracket ? ep.fore : page.plain ? "white" : ep.inverse ? page.c.ink : page.c.surface) ?? "white"
                    font.family: page.bodyFont
                    font.pixelSize: page.plain ? 11 : 10
                    font.weight: page.caps ? Font.Normal : page.plain ? Font.Medium : Font.Bold
                    font.letterSpacing: page.plain ? 0 : 1.4
                }
            }
            Text {
                Layout.preferredWidth: 70
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: T.episodeLength(voice, ep.modelData.runtime)
                color: ep.inverse && page.bracket ? ep.fore : ep.soft
                font.family: page.bodyFont
                font.pixelSize: 12
                font.letterSpacing: page.bracket ? 0.7 : 0
            }
            // Paper sets an aired date in its italic serif; a date to come stays in the body face.
            Text {
                id: dateText
                Layout.preferredWidth: 96
                horizontalAlignment: Text.AlignRight
                textFormat: Text.PlainText
                text: T.dateText(voice, ep.modelData.air_date, page.today)
                color: ep.inverse && page.bracket ? ep.fore : ep.soft
                font.family: (page.caps && ep.due ? page.fonts.display : page.bodyFont) ?? ""
                font.italic: page.caps && ep.due
                font.pixelSize: page.caps && ep.due ? 17 : 12
                font.letterSpacing: page.bracket ? 0.7 : 0
            }
        }
    }
}
