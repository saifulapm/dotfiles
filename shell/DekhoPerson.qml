import QtQuick
import QtQuick.Effects
import QtQuick.Layouts
import "lib/dekho.mjs" as D
import "lib/dekho-person.mjs" as P

// Dekho's Person page: the portrait, years, birthplace and biography beside the credits split by role, the cursor walking them.
FocusScope {
    id: page

    required property var dekho
    // The now-playing bar at its foot, for the state the checks read.
    property alias playingBar: nowBar

    readonly property var c: dekho.c
    readonly property var tones: dekho.tones
    readonly property var fonts: dekho.fonts
    readonly property var look: dekho.look
    readonly property var words: P.personText()
    readonly property string bodyFont: fonts.ui ?? ""

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

    // A click on a credit moves the cursor there and does what Enter does.
    function pick(at) {
        cursor = at;
        reveal();
        keys.forceActiveFocus();
        choose();
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
            Layout.preferredHeight: 52
            Layout.leftMargin: 18
            Layout.rightMargin: 18
            spacing: 12

            Rectangle {
                implicitWidth: labelText.implicitWidth + 18
                implicitHeight: labelText.implicitHeight + 6
                radius: 8
                color: look.label.fill

                Text {
                    id: labelText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: words.label
                    color: look.label.color ?? "blue"
                    font.family: page.bodyFont
                    font.pixelSize: 12
                    font.weight: Font.Medium
                }
            }
            Text {
                id: headName
                Layout.fillWidth: true
                textFormat: Text.PlainText
                text: page.name
                color: c.ink ?? "black"
                font.family: page.bodyFont
                font.pixelSize: 14
                font.weight: Font.Bold
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Rectangle {
                implicitWidth: pageText.implicitWidth + 18
                implicitHeight: pageText.implicitHeight + 6
                radius: 8
                color: look.tile.fill

                Text {
                    id: pageText
                    anchors.centerIn: parent
                    textFormat: Text.PlainText
                    text: words.page
                    color: c.muted ?? "gray"
                    font.family: page.bodyFont
                    font.pixelSize: 11
                    font.weight: Font.Medium
                }
            }
        }

        Rule {
            Layout.fillWidth: true
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

                    // The portrait once it is on disk, else a grey circle with the initials.
                    Item {
                        id: portrait
                        Layout.preferredWidth: 120
                        Layout.preferredHeight: 120

                        Rectangle {
                            id: placeholder
                            anchors.fill: parent
                            visible: picture.status !== Image.Ready
                            radius: 60
                            color: tones.thumb
                            clip: true

                            Text {
                                id: initialsText
                                anchors.centerIn: parent
                                textFormat: Text.PlainText
                                text: P.initials(page.shown.name)
                                color: c.muted ?? "gray"
                                font.family: page.bodyFont
                                font.pixelSize: 34
                                font.weight: Font.Bold
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
                            // The portrait is a circle: the image is masked by one.
                            layer.enabled: true
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
                    }
                    Text {
                        id: bigName
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: page.name
                        color: c.ink ?? "black"
                        font.family: page.bodyFont
                        font.pixelSize: 22
                        font.weight: Font.Bold
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        id: sublineText
                        Layout.fillWidth: true
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: page.detail ? P.subline(info.birthday, info.deathday, sets) : ""
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: 12
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        id: placeText
                        Layout.fillWidth: true
                        visible: text !== ""
                        textFormat: Text.PlainText
                        text: D.title(info.place_of_birth)
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: 12
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
                            font.pixelSize: 13
                            lineHeight: 1.55
                            wrapMode: Text.Wrap
                            elide: Text.ElideRight
                        }
                    }
                    Rectangle {
                        Layout.alignment: Qt.AlignLeft
                        implicitWidth: buttonRow.implicitWidth + 24
                        implicitHeight: buttonRow.implicitHeight + 20
                        radius: 12
                        color: look.tile.fill

                        Row {
                            id: buttonRow
                            anchors.centerIn: parent
                            spacing: 6

                            Text {
                                id: buttonKey
                                textFormat: Text.PlainText
                                text: look.keys([["f", "filter the library by " + P.firstName(page.shown.name)]])[0].key
                                color: c.ink ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: 12
                                font.weight: Font.Bold
                            }
                            Text {
                                id: buttonWord
                                textFormat: Text.PlainText
                                text: look.keys([["f", "filter the library by " + P.firstName(page.shown.name)]])[0].word
                                color: c.ink ?? "black"
                                font.family: page.bodyFont
                                font.pixelSize: 12
                                elide: Text.ElideRight
                                width: Math.min(implicitWidth, 190)
                            }
                        }
                    }
                }

                // The side's right edge.
                Rectangle {
                    anchors.right: parent.right
                    anchors.top: parent.top
                    anchors.bottom: parent.bottom
                    width: 1
                    color: c.line ?? "gray"
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
                        font.pixelSize: 11
                    }
                    Text {
                        id: nextText
                        Layout.fillWidth: true
                        horizontalAlignment: Text.AlignRight
                        textFormat: Text.PlainText
                        text: page.sets.length > 1 ? words.next : ""
                        color: c.muted ?? "gray"
                        font.family: page.bodyFont
                        font.pixelSize: 11
                    }
                }

                Flickable {
                    id: creditView
                    Layout.fillWidth: true
                    Layout.fillHeight: true
                    contentWidth: width
                    contentHeight: creditColumn.height
                    interactive: false
                    clip: true

                    // Under the credits, the wheel scrolls them and leaves the cursor where it is.
                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.NoButton
                        onWheel: event => creditView.contentY = D.wheeled(creditView.contentY, event.angleDelta.y, creditView.contentHeight, creditView.height)
                    }

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
                                // The cursor's row is tinted and ringed in the accent.
                                readonly property color soft: page.c.muted ?? "gray"
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
                                        shown: ln.y >= creditView.contentY - 0.5 && ln.y + ln.height <= creditView.contentY + creditView.height + 0.5,
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
                                            font.pixelSize: 11
                                            font.weight: Font.Bold
                                        }
                                        Text {
                                            id: countBadge
                                            textFormat: Text.PlainText
                                            text: ln.head ? String(ln.modelData.count) : ""
                                            color: page.c.muted ?? "gray"
                                            font.family: page.bodyFont
                                            font.pixelSize: 11
                                        }
                                    }
                                    Rule {
                                        anchors.left: parent.left
                                        anchors.right: parent.right
                                        anchors.bottom: parent.bottom
                                    }
                                }

                                Rectangle {
                                    id: card
                                    anchors.fill: parent
                                    visible: !ln.head

                                    Click {
                                        name: "person-credit:" + ln.modelData.index
                                        onTapped: page.pick(ln.modelData.index)
                                    }
                                    radius: 10
                                    color: ln.cursor ? page.look.label.fill : "transparent"
                                    border.width: ln.cursor ? 1.5 : 0
                                    border.color: page.c.accent ?? "blue"

                                    RowLayout {
                                        anchors.fill: parent
                                        anchors.leftMargin: 12
                                        anchors.rightMargin: 12
                                        spacing: 12

                                        // The poster's place, a grey tile until the poster is on disk.
                                        Rectangle {
                                            id: place
                                            Layout.preferredWidth: 18
                                            Layout.preferredHeight: 27
                                            radius: 4
                                            color: page.tones.thumb
                                            clip: true

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
                                        }
                                        Text {
                                            id: titleText
                                            Layout.fillWidth: true
                                            textFormat: Text.PlainText
                                            text: ln.head ? "" : ln.modelData.row.titleText
                                            color: ln.cursor ? page.tones.deep : page.c.ink ?? "black"
                                            font.family: page.bodyFont
                                            font.pixelSize: 14
                                            font.weight: Font.Medium
                                            elide: Text.ElideRight
                                            maximumLineCount: 1
                                        }
                                        Text {
                                            id: kindText
                                            Layout.preferredWidth: 70
                                            textFormat: Text.PlainText
                                            text: ln.head ? "" : P.kindText(ln.modelData.row.kind)
                                            color: ln.soft
                                            font.family: page.bodyFont
                                            font.pixelSize: 11
                                        }
                                        Text {
                                            id: roleText
                                            Layout.preferredWidth: 220
                                            textFormat: Text.PlainText
                                            text: ln.head ? "" : ln.modelData.row.roleText
                                            color: ln.soft
                                            font.family: page.bodyFont
                                            font.pixelSize: 13
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
        }

        // While a film plays, the now-playing bar takes the keys' place.
        DekhoBar {
            id: nowBar
            Layout.fillWidth: true
            dekho: page.dekho
        }

        // The keys, as Home and the Title page strip them.
        Flow {
            Layout.fillWidth: true
            visible: page.dekho.nowPlaying === null
            Layout.leftMargin: 14
            Layout.rightMargin: 14
            Layout.topMargin: 10
            Layout.bottomMargin: 10
            spacing: 8

            Repeater {
                model: page.look.keys(page.words.keys(page.sets, page.shown.name))

                Rectangle {
                    required property var modelData
                    implicitWidth: keyPair.implicitWidth + 14
                    implicitHeight: keyPair.implicitHeight + 6
                    radius: 6
                    color: "transparent"

                    Row {
                        id: keyPair
                        anchors.centerIn: parent
                        spacing: 6

                        Text {
                            textFormat: Text.PlainText
                            text: modelData.key
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 11
                            font.weight: Font.Medium
                        }
                        Text {
                            // The f key's word carries the person's name, which TMDB controls.
                            width: Math.min(implicitWidth, 360)
                            textFormat: Text.PlainText
                            text: D.title(modelData.word)
                            color: page.c.muted ?? "gray"
                            font.family: page.bodyFont
                            font.pixelSize: 11
                            elide: Text.ElideRight
                        }
                    }
                }
            }
        }
    }

    // A one-pixel rule in the line colour.
    component Rule: Rectangle {
        implicitHeight: 1
        color: page.c.line ?? "gray"
    }
}
