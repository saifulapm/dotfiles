import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import QtQuick.Shapes
import "lib/dekho.mjs" as D
import "lib/dekho-person.mjs" as P

// Dekho's Person page: the portrait, years, birthplace and biography beside the credits split by role, the cursor walking them.
FocusScope {
    id: page

    required property var dekho

    readonly property var c: dekho.c
    readonly property var fonts: dekho.fonts
    readonly property var look: dekho.look
    readonly property string voice: dekho.voice
    readonly property bool plain: voice === "plain"
    readonly property bool bracket: voice === "bracket"
    readonly property bool caps: voice === "caps"
    readonly property var words: P.personText(voice)
    readonly property string bodyFont: (bracket ? fonts.mono : fonts.ui) ?? ""

    // The id and name Enter opened, drawn at once; the backend's answer fills the rest in.
    property var chosen: ({})
    property var detail: null
    property string image: ""
    // The credit the cursor is on, counted through every group.
    property int cursor: 0
    // Each load counts up; an older person's answer is dropped.
    property int asked: 0
    // The stack entry last loaded, so going back to this page keeps the cursor.
    property var loaded: null
    readonly property var current: dekho.stack[dekho.stack.length - 1]

    readonly property var shown: detail || chosen
    readonly property string name: D.title(shown.name)
    readonly property var info: detail || ({})
    readonly property var sets: P.groups(info.credits)
    readonly property var lines: P.lines(sets)
    readonly property var flat: lines.filter(l => !l.head)
    readonly property int group: flat[cursor] ? sets.findIndex(g => g.key === flat[cursor].key) : 0

    signal search

    onCurrentChanged: if (current.page === "person" && current.args !== loaded) {
        loaded = current.args;
        load(current.args);
    }

    function load(a) {
        chosen = a;
        detail = null;
        image = "";
        cursor = 0;
        creditView.contentY = 0;
        const n = ++asked;
        dekho.api(["api", "person", "--id", String(a.id)], answer => {
            if (page.asked !== n || !answer)
                return;
            page.detail = answer;
            page.dekho.prefetch("w342", P.groups(answer.credits).map(g => g.rows.map(r => r.poster)).reduce((all, posters) => all.concat(posters), []));
            if (answer.profile)
                page.dekho.api(["api", "prefetch", "--size", "w185", answer.profile], files => {
                    if (page.asked === n && files && files.files && files.files[answer.profile])
                        page.image = files.files[answer.profile];
                });
        });
    }

    function move(by) {
        cursor = Math.max(0, Math.min(flat.length - 1, cursor + by));
        reveal();
    }

    // Tab: the first credit of the next group, after the last the first.
    function nextRole() {
        if (sets.length < 2)
            return;
        const to = (group + 1) % sets.length;
        cursor = sets.slice(0, to).reduce((n, g) => n + g.count, 0);
        reveal();
    }

    function reveal() {
        const at = lines.findIndex(l => !l.head && l.index === cursor);
        const r = at < 0 ? null : creditLines.itemAt(at);
        if (!r)
            return;
        if (r.y < creditView.contentY)
            creditView.contentY = r.y;
        else if (r.y + r.height > creditView.contentY + creditView.height)
            creditView.contentY = r.y + r.height - creditView.height;
    }

    function choose() {
        if (flat[cursor])
            dekho.openTitle(flat[cursor].row);
    }

    function drawnList(repeater) {
        const out = [];
        for (let i = 0; i < repeater.count; i++)
            out.push(repeater.itemAt(i).drawn());
        return out;
    }

    function state() {
        return {
            personPage: {
                tmdbId: chosen.id ?? null,
                ready: detail !== null,
                name: bigName.text,
                nameLines: bigName.lineCount,
                headerName: headName.text,
                subline: sublineText.text,
                place: placeText.text,
                bio: {
                    text: bioText.text,
                    lines: bioText.lineCount,
                    truncated: bioText.truncated,
                    fits: bioText.contentHeight <= bioBox.height,
                    width: bioText.width,
                    panel: sidePanel.width
                },
                button: buttonKey.text + " " + buttonWord.text,
                creditsShown: creditView.visible && creditView.height > 0,
                count: countText.text,
                next: nextText.text,
                cursor: cursor,
                group: sets[group] ? sets[group].key : "",
                lines: drawnList(creditLines),
                portrait: {
                    image: picture.status === Image.Ready,
                    placeholder: placeholder.visible,
                    initials: initialsText.text,
                    width: portrait.width,
                    height: portrait.height
                },
                look: {
                    nameFont: bigName.font.family,
                    hatch: hatch.visible,
                    cross: cross.visible,
                    portraitRadius: placeholder.radius,
                    rowRadius: creditLines.count ? creditLines.itemAt(1).cardRadius : -1
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
            else if (k === Qt.Key_Tab)
                page.nextRole();
            else if (t === "j" || k === Qt.Key_Down)
                page.move(1);
            else if (t === "k" || k === Qt.Key_Up)
                page.move(-1);
            else if (k === Qt.Key_Return || k === Qt.Key_Enter)
                page.choose();
            else if (t === "f")
                page.dekho.open("browse", {
                    person: {
                        id: page.chosen.id,
                        name: page.shown.name
                    },
                    from: page.name
                });
            else
                return;
            event.accepted = true;
        }
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 0

        // The header as the Title page draws it, with the person's name where that one writes its title.
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
                id: headName
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: page.name
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
            Layout.fillWidth: true
            dashed: bracket
            color: caps ? c.ink ?? "black" : c.line ?? "gray"
        }

        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // The side: portrait, name, years, birthplace, biography, and the key that filters Browse by them.
            Item {
                id: sidePanel
                Layout.preferredWidth: 300
                Layout.minimumWidth: 300
                Layout.maximumWidth: 300
                Layout.fillHeight: true

                ColumnLayout {
                    anchors.fill: parent
                    anchors.margins: 24
                    spacing: 14

                    // The portrait once it is on disk, else each board's empty one with the initials: Paper's hatched square, Artboard's grey circle, Blueprint's crossed box.
                    Item {
                        id: portrait
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 120

                        Rectangle {
                            id: placeholder
                            anchors.fill: parent
                            visible: picture.status !== Image.Ready
                            radius: plain ? 60 : 0
                            color: plain ? "#E9ECF1" : "transparent"
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
                                            for (let x = 6; x < 250; x += 6)
                                                p += "M" + x + " 0L" + (x - 120) + " 120";
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
                                        path: "M0 0L120 120M120 0L0 120"
                                    }
                                }
                            }
                            Text {
                                id: initialsText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: P.initials(page.shown.name)
                                color: (plain ? c.muted : c.ink) ?? "gray"
                                font.family: (caps ? fonts.display : page.bodyFont) ?? ""
                                font.pixelSize: caps ? 42 : plain ? 34 : 31
                                font.weight: caps ? Font.Normal : Font.Bold
                            }
                        }
                        Image {
                            id: picture
                            anchors.fill: parent
                            visible: status === Image.Ready
                            source: page.image ? "file://" + page.image : ""
                            asynchronous: true
                            fillMode: Image.PreserveAspectCrop
                            sourceSize.width: 240
                            // Artboard's portrait is a circle: the image is masked by one.
                            layer.enabled: page.plain
                            layer.effect: MultiEffect {
                                maskEnabled: true
                                maskSource: roundMask
                            }
                        }
                        Rectangle {
                            id: roundMask
                            anchors.fill: parent
                            visible: false
                            radius: 60
                            layer.enabled: true
                        }
                        Rectangle {
                            anchors.fill: parent
                            visible: !plain
                            color: "transparent"
                            border.width: 1
                            border.color: (bracket ? c.accent : c.muted) ?? "gray"
                        }
                    }
                    Text {
                        id: bigName
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: page.name
                        color: c.ink ?? "black"
                        font.family: (caps ? fonts.display : page.bodyFont) ?? ""
                        font.pixelSize: caps ? 30 : 22
                        font.weight: caps ? Font.Normal : Font.Bold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        id: sublineText
                        Layout.fillWidth: true
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: page.detail ? P.subline(voice, info.birthday, info.deathday, sets) : ""
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        font.letterSpacing: bracket ? 0.7 : 0
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        id: placeText
                        Layout.fillWidth: true
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: bracket ? D.title(info.place_of_birth).toUpperCase() : D.title(info.place_of_birth)
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        font.letterSpacing: bracket ? 0.7 : 0
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    // The biography fills what the side has left and ends in an ellipsis there, so the key below it stays in sight.
                    Item {
                        id: bioBox
                        Layout.fillWidth: true
                        Layout.fillHeight: true
                        clip: true

                        Text {
                            id: bioText
                            width: parent.width
                            height: parent.height
                            textFormat: Text.PlainText
                            text: D.title(info.biography)
                            color: c.ink ?? "black"
                            font.family: page.bodyFont
                            font.pixelSize: plain ? 13 : 12
                            lineHeight: 1.55
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignLeft
                        implicitWidth: buttonRow.implicitWidth + (plain ? 24 : 20)
                        implicitHeight: buttonRow.implicitHeight + (plain ? 20 : 16)
                        radius: plain ? 12 : 0
                        color: plain ? look.tile.fill : "transparent"
                        border.width: plain ? 0 : 1
                        border.color: (bracket ? c.accent : c.ink) ?? "gray"

                        Row {
                            id: buttonRow
                            anchors.centerIn: parent
                            spacing: bracket ? 8 : 6

                            Text {
                                id: buttonKey
                                textFormat: Text.PlainText
                                text: look.keys([["f", "filter the library by " + P.firstName(page.shown.name)]])[0].key
                                color: (bracket ? c.accent : c.ink) ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: plain ? 12 : 11
                                font.weight: Font.Bold
                                font.letterSpacing: plain ? 0 : 1
                            }
                            Text {
                                id: buttonWord
                                textFormat: Text.PlainText
                                text: look.keys([["f", "filter the library by " + P.firstName(page.shown.name)]])[0].word
                                color: c.ink ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: plain ? 12 : 11
                                font.letterSpacing: plain ? 0 : 1
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, 190)
                            }
                        }
                    }
                }

                // The side's right edge: solid in Paper and Artboard, dashed in Blueprint.
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    visible: !bracket
                    color: caps ? c.ink ?? "black" : c.line ?? "gray"
                }
                Shape {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    visible: bracket
                    preferredRendererType: Shape.GeometryRenderer

                    ShapePath {
                        strokeColor: page.c.line ?? "gray"
                        strokeWidth: 1
                        strokeStyle: ShapePath.DashLine
                        dashPattern: [4, 3]
                        fillColor: "transparent"
                        PathLine {
                            x: 0.5
                            y: 0
                        }
                        PathLine {
                            x: 0.5
                            y: sidePanel.height
                        }
                    }
                }
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.fillHeight: true
                Layout.leftMargin: 18
                Layout.rightMargin: 18
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                spacing: 14

                RowLayout {
                    Layout.fillWidth: true
                    spacing: 8

                    Text {
                        id: countText
                        textFormat: Text.PlainText
                        text: page.detail ? words.filmography(page.flat.length) : ""
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: caps || bracket ? 10 : 11
                        font.letterSpacing: caps || bracket ? 1.4 : 0
                    }
                    Text {
                        id: nextText
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        textFormat: Text.PlainText
                        text: page.sets.length > 1 ? words.next : ""
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: bracket ? 10 : 11
                        font.letterSpacing: bracket ? 1.4 : 0
                    }
                }

                Flickable {
                    id: creditView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: creditColumn.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    Column {
                        id: creditColumn
                        width: creditView.width
                        spacing: 2

                        Repeater {
                            id: creditLines
                            model: page.lines

                            Item {
                                id: ln

                                required property var modelData
                                required property int index
                                readonly property bool head: modelData.head
                                readonly property bool cursor: !head && page.cursor === modelData.index
                                // The cursor's row inverts in Paper and Blueprint; Artboard tints it and rings it in its accent.
                                readonly property bool inverse: cursor && !page.plain
                                readonly property color fore: inverse ? page.c.surface ?? "white" : page.c.ink ?? "black"
                                readonly property color soft: inverse ? (page.caps ? page.c.line : page.c.surface) ?? "white" : page.c.muted ?? "gray"
                                readonly property int cardRadius: card.radius

                                function drawn() {
                                    return head ? {
                                        head: true,
                                        text: headText.text,
                                        count: countBadge.text
                                    } : {
                                        head: false,
                                        group: modelData.key,
                                        year: yearText.text,
                                        title: titleText.text,
                                        titleLines: titleText.lineCount,
                                        kind: kindText.text,
                                        role: roleText.text,
                                        roleLines: roleText.lineCount,
                                        vote: voteText.text,
                                        cursor: cursor,
                                        poster: poster.drawn()
                                    };
                                }

                                width: creditColumn.width
                                height: head ? (index === 0 ? 0 : 12) + 30 : 30

                                Item {
                                    anchors.left: parent.left
                                    anchors.right: parent.right
                                    anchors.bottom: parent.bottom
                                    height: 30
                                    visible: ln.head

                                    Row {
                                        anchors.left: parent.left
                                        anchors.leftMargin: 12
                                        anchors.verticalCenter: parent.verticalCenter
                                        spacing: 10

                                        Text {
                                            id: headText
                                            textFormat: Text.PlainText
                                            text: ln.head ? page.words.heading(ln.modelData.key) : ""
                                            color: page.c.ink ?? "black"
                                            font.family: page.bodyFont
                                            font.pixelSize: page.plain ? 11 : page.bracket ? 11 : 10
                                            font.weight: page.plain || page.bracket ? Font.Bold : Font.DemiBold
                                            font.letterSpacing: page.plain ? 0 : 1.4
                                        }
                                        Text {
                                            id: countBadge
                                            textFormat: Text.PlainText
                                            text: ln.head ? String(ln.modelData.count) : ""
                                            color: page.c.muted ?? "gray"
                                            font.family: page.bodyFont
                                            font.pixelSize: page.plain ? 11 : page.bracket ? 11 : 10
                                            font.letterSpacing: page.plain ? 0 : 1.4
                                        }
                                    }
                                    Rule {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                        dashed: page.bracket
                                        color: (page.caps ? "#D8CDB6" : page.c.line) ?? "gray"
                                    }
                                }

                                Rectangle {
                                    id: card
                                    anchors.fill: parent
                                    visible: !ln.head
                                    radius: page.plain ? 10 : 0
                                    color: ln.cursor ? (page.plain ? page.look.label.fill : page.bracket ? page.c.accent : page.c.ink) ?? "black" : "transparent"
                                    border.width: ln.cursor && page.plain ? 1.5 : 0
                                    border.color: page.c.accent ?? "blue"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        // The poster's place, as each board marks it until the poster is on disk: Paper's hatch, Artboard's grey tile, Blueprint's crossed box.
                                        Rectangle {
                                            id: place
                                            Layout.preferredWidth: 18
                                            Layout.preferredHeight: 27
                                            radius: page.plain ? 4 : 0
                                            color: page.plain ? "#E9ECF1" : page.bracket ? page.c.surface ?? "black" : "transparent"
                                            border.width: page.plain ? 0 : 1
                                            border.color: (page.bracket ? ln.soft : page.c.muted) ?? "gray"
                                            clip: true

                                            Shape {
                                                anchors.fill: parent
                                                visible: page.caps
                                                preferredRendererType: Shape.GeometryRenderer

                                                ShapePath {
                                                    strokeColor: "#D8CDB6"
                                                    strokeWidth: 1
                                                    fillColor: "transparent"
                                                    PathSvg {
                                                        path: "M6 0L0 6M12 0L0 12M18 0L0 18M24 0L0 24M30 0L0 30M36 0L0 36M42 0L0 42"
                                                    }
                                                }
                                            }
                                            Shape {
                                                anchors.fill: parent
                                                visible: page.bracket
                                                preferredRendererType: Shape.GeometryRenderer

                                                ShapePath {
                                                    strokeColor: ln.soft
                                                    strokeWidth: 1
                                                    fillColor: "transparent"
                                                    PathSvg {
                                                        path: "M0 0L18 27M18 0L0 27"
                                                    }
                                                }
                                            }
                                            DekhoPicture {
                                                id: poster
                                                anchors.fill: parent
                                                dekho: page.dekho
                                                size: "w342"
                                                path: ln.head ? null : ln.modelData.row.poster
                                                radius: place.radius
                                            }
                                        }
                                        Text {
                                            id: yearText
                                            Layout.preferredWidth: 48
                                            textFormat: Text.PlainText
                                            text: ln.head ? "" : D.title(ln.modelData.row.year)
                                            color: ln.soft
                                            font.family: page.bodyFont
                                            font.pixelSize: 12
                                            font.letterSpacing: page.bracket ? 0.7 : 0
                                        }
                                        Text {
                                            id: titleText
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                            text: ln.head ? "" : ln.modelData.row.titleText
                                            color: ln.cursor && page.plain ? "#2638C9" : ln.fore
                                            font.family: page.bodyFont
                                            font.pixelSize: page.plain ? 14 : 13
                                            font.weight: ln.cursor && page.bracket ? Font.Bold : Font.Medium
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                        Text {
                                            id: kindText
                                            Layout.preferredWidth: 70
                                            textFormat: Text.PlainText
                                            text: ln.head ? "" : P.kindText(page.voice, ln.modelData.row.kind)
                                            color: ln.soft
                                            font.family: page.bodyFont
                                            font.pixelSize: page.bracket ? 10 : 11
                                            font.letterSpacing: page.bracket ? 1.4 : 0
                                        }
                                        Text {
                                            id: roleText
                                            Layout.preferredWidth: 220
                                            textFormat: Text.PlainText
                                            text: ln.head ? "" : ln.modelData.row.roleText
                                            color: ln.soft
                                            font.family: page.bodyFont
                                            font.pixelSize: page.plain ? 13 : 12
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                        Text {
                                            id: voteText
                                            Layout.preferredWidth: 64
                                            horizontalAlignment: Text.AlignRight
                                            textFormat: Text.PlainText
                                            text: ln.head ? "" : ln.modelData.row.voteText
                                            color: ln.soft
                                            font.family: page.bodyFont
                                            font.pixelSize: 12
                                            font.letterSpacing: page.bracket ? 0.7 : 0
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }
        }

        Rule {
            Layout.fillWidth: true
            dashed: bracket
            color: caps ? c.ink ?? "black" : c.line ?? "gray"
        }

        // The keys, as Home and the Title page strip them.
        Flow {
            Layout.fillWidth: true
            Layout.leftMargin: plain ? 14 : 16
            Layout.rightMargin: plain ? 14 : 16
            Layout.topMargin: plain ? 10 : 11
            Layout.bottomMargin: plain ? 10 : 11
            spacing: plain ? 8 : 16

            Repeater {
                model: page.look.keys(page.words.keys(page.sets, page.shown.name))

                Rectangle {
                    required property var modelData
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
                            // The f key's word carries the person's name, which TMDB controls.
                            width: Math.min(implicitWidth, 360)
                            textFormat: Text.PlainText
                            text: D.title(modelData.word)
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: page.caps ? 10 : 11
                            font.letterSpacing: page.caps ? 1 : page.bracket ? 1.5 : 0
                            elide: Text.ElideRight
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
}
