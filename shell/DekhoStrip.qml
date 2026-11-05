import QtQuick
import QtQuick.Layouts
import "lib/dekho.mjs" as D
import "lib/dekho-home.mjs" as H

// One row of titles: its heading, then a strip of cards, as many shown as the board's five columns fit, scrolled without motion to keep the cursor's card in view. Home draws its rows with it and a title page its More like this; the page owns the cursor and answers a click.
ColumnLayout {
    id: strip

    required property var page
    // Names the cards for the checks' `dekho box`, as <name>:<index>.
    required property string name
    required property var items
    property string headText: ""
    property string tailText: ""
    // The cursor's card, or -1 when the cursor is in another row.
    property int cursor: -1
    // A row of titles being watched: each card draws its episode or RESUME and a progress bar.
    property bool progressed: false
    readonly property real cardWidth: Math.max(0, (width - 4 * 14) / 5)
    readonly property real cardRadius: 12
    readonly property string tailDrawn: tailLabel.text

    // A click on a card; the page moves its cursor there and does what Enter does.
    signal picked(int index)

    function reveal(i) {
        const card = cards.itemAt(i);
        if (!card)
            return;
        if (card.x < view.contentX)
            view.contentX = card.x;
        else if (card.x + card.width > view.contentX + view.width)
            view.contentX = card.x + card.width - view.width;
    }

    function drawn() {
        const out = [];
        for (let i = 0; i < cards.count; i++)
            out.push(cards.itemAt(i).drawn());
        return out;
    }

    spacing: 8

    // Its items change when an answer lands, and the strip starts at its first card again.
    onItemsChanged: view.contentX = 0

    RowLayout {
        Layout.fillWidth: true

        Text {
            Layout.fillWidth: true
            textFormat: Text.PlainText
            text: strip.headText
            color: strip.page.c.muted ?? "gray"
            font.family: strip.page.bodyFont
            font.pixelSize: 11
        }
        Text {
            id: tailLabel
            textFormat: Text.PlainText
            text: strip.tailText
            color: strip.page.c.muted ?? "gray"
            font.family: strip.page.bodyFont
            font.pixelSize: 11
        }
    }

    Flickable {
        id: view
        Layout.fillWidth: true
        implicitHeight: cardRow.implicitHeight
        contentWidth: cardRow.implicitWidth
        interactive: false
        clip: true

        // Under the cards, the wheel scrolls the strip along them and leaves the cursor where it is.
        MouseArea {
            anchors.fill: parent
            acceptedButtons: Qt.NoButton
            onWheel: event => view.contentX = D.wheeled(view.contentX, event.angleDelta.y || event.angleDelta.x, view.contentWidth, view.width)
        }

        Row {
            id: cardRow
            spacing: 14

            Repeater {
                id: cards
                model: strip.items

                Card {
                    page: strip.page
                    row: strip.name
                    viewport: view
                    width: strip.cardWidth
                    radius: strip.cardRadius
                    progressed: strip.progressed
                    focused: strip.cursor === index
                    onTapped: strip.picked(index)
                }
            }
        }
    }

    // A title's card: a poster's place, the title on one elided line, its subtitle, and for a title being watched a thin progress bar.
    component Card: Rectangle {
        id: card

        required property var modelData
        required property int index
        required property var page
        required property Item viewport
        required property string row
        property bool progressed: false
        property bool focused: false

        signal tapped

        readonly property var lineWords: progressed ? H.continueLine(modelData) : H.hitLine(modelData)
        readonly property real played: Math.max(0, Math.min(1, Number(modelData.progress) || 0))

        function drawn() {
            const at = card.mapToItem(viewport, 0, 0);
            const d = {
                title: titleText.text,
                line: lineText.text,
                lines: titleText.lineCount,
                elided: titleText.truncated,
                poster: poster.drawn(),
                shown: card.visible && viewport.visible && at.x >= -0.5 && at.x + card.width <= viewport.width + 0.5
            };
            if (progressed)
                d.progress = Math.round(bar.width / track.width * 100) / 100;
            return d;
        }

        implicitHeight: body.implicitHeight + 20
        color: focused ? page.c.surface ?? "white" : page.tones.field
        border.width: focused ? 1.5 : 0
        border.color: page.c.accent ?? "black"

        Click {
            name: card.row + ":" + card.index
            onTapped: card.tapped()
        }

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // The poster's place, a grey tile until the poster is on disk.
                Rectangle {
                    id: place
                    implicitWidth: 36
                    implicitHeight: 54
                    radius: 8
                    color: card.page.tones.thumb
                    clip: true

                    DekhoPicture {
                        id: poster
                        anchors.fill: parent
                        dekho: card.page.dekho
                        size: "w342"
                        path: card.modelData.poster
                        radius: place.radius
                    }
                }
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 4

                    Text {
                        id: titleText
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: D.title(card.modelData.title)
                        color: card.page.c.ink ?? "black"
                        font.family: card.page.bodyFont
                        font.pixelSize: 13
                        font.weight: Font.Medium
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        id: lineText
                        Layout.fillWidth: true
                        textFormat: Text.PlainText
                        text: card.lineWords
                        color: card.page.c.muted ?? "gray"
                        font.family: card.page.bodyFont
                        font.pixelSize: 11
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }
            Rectangle {
                id: track
                Layout.fillWidth: true
                visible: card.progressed
                implicitHeight: 4
                radius: 2
                color: card.page.c.line ?? "gray"

                Rectangle {
                    id: bar
                    width: parent.width * card.played
                    height: parent.height
                    radius: parent.radius
                    color: card.page.c.accent ?? "red"
                }
            }
        }
    }
}
