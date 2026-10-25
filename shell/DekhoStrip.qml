import QtQuick
import QtQuick.Layouts
import QtQuick.Shapes
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
    readonly property real cardRadius: page.plain ? 12 : 0
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
            font.pixelSize: strip.page.voice === "caps" ? 10 : 11
            font.letterSpacing: strip.page.plain ? 0 : strip.page.bracket ? 1.54 : 1.4
        }
        Text {
            id: tailLabel
            textFormat: Text.PlainText
            text: strip.tailText
            color: strip.page.c.muted ?? "gray"
            font.family: strip.page.bodyFont
            font.pixelSize: strip.page.voice === "caps" ? 10 : 11
            font.letterSpacing: strip.page.plain ? 0 : strip.page.bracket ? 1.54 : 1.4
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

        readonly property var voiceText: progressed ? H.continueLine(page.voice, modelData) : H.hitLine(modelData)
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
        color: page.plain ? (focused ? page.c.surface ?? "white" : "#F6F7F9") : page.bracket && focused ? Qt.alpha(page.c.accent ?? "cyan", 0.1) : "transparent"
        border.width: page.plain ? (focused ? 1.5 : 0) : 1
        border.color: (page.plain ? page.c.accent : page.bracket ? (focused ? page.c.accent : page.c.line) : page.c.ink) ?? "black"

        DekhoClick {
            name: card.row + ":" + card.index
            onTapped: card.tapped()
        }

        // Paper rings the cursor's card in its accent, two pixels inside its ink border.
        Rectangle {
            anchors.fill: parent
            visible: card.focused && card.page.voice === "caps"
            color: "transparent"
            border.width: 2
            border.color: card.page.c.accent ?? "red"
        }

        ColumnLayout {
            id: body
            anchors.fill: parent
            anchors.margins: 10
            spacing: 10

            RowLayout {
                Layout.fillWidth: true
                spacing: 12

                // The poster's place, as each board marks it until the poster is on disk: Paper's hatch, Artboard's grey tile, Blueprint's crossed box.
                Rectangle {
                    id: place
                    implicitWidth: card.page.plain ? 36 : 38
                    implicitHeight: card.page.plain ? 54 : 56
                    radius: card.page.plain ? 8 : 0
                    color: card.page.plain ? "#E9ECF1" : "transparent"
                    border.width: card.page.plain ? 0 : 1
                    border.color: (card.page.bracket ? card.page.c.line : card.page.c.muted) ?? "gray"
                    clip: true

                    Shape {
                        anchors.fill: parent
                        visible: !card.page.plain
                        preferredRendererType: Shape.GeometryRenderer

                        ShapePath {
                            strokeColor: card.page.c.line ?? "gray"
                            strokeWidth: 1
                            fillColor: "transparent"
                            PathSvg {
                                path: card.page.bracket ? "M0 0L38 56M38 0L0 56" : "M6 0L0 6M12 0L0 12M18 0L0 18M24 0L0 24M30 0L0 30M36 0L0 36M42 0L0 42M48 0L0 48M54 0L0 54M60 0L4 56M66 0L10 56M72 0L16 56M78 0L22 56M84 0L28 56M90 0L34 56M96 0L40 56"
                            }
                        }
                    }
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
                        text: card.voiceText
                        color: card.page.c.muted ?? "gray"
                        font.family: card.page.bodyFont
                        font.pixelSize: card.page.bracket ? 10 : 11
                        font.letterSpacing: card.page.bracket ? 1.4 : 0
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
                radius: card.page.plain ? 2 : 0
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
