import Quickshell
import Quickshell.Io
import QtQuick
import QtQuick.Effects
import "." as Root
import "lib/themes.mjs" as Lib

// The theme switcher, drawn in the Surfaces window.
Item {
    id: switcher

    required property var theme
    // themes.json's entries, read by the shell at start.
    required property var themes
    readonly property var names: themes.map(t => t.name)
    property bool shown: false
    property string selected: ""
    // The card that last played its switch, for the state.
    property string played: ""
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var c: theme.color
    readonly property var look: Lib.pickerLook(theme.tokens)
    readonly property var header: look.header(themes.length, theme.name)
    readonly property Root.Motion motion: Root.Motion {
        shown: switcher.shown
        tokens: switcher.theme.tokens
    }

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        selected = theme.name;
        played = "";
        shown = true;
        keys.forceActiveFocus();
    }

    function close() {
        shown = false;
    }

    // Called on each of the host window's frames; the first one after open() ends the timing.
    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function move(by) {
        land(Lib.step(names, selected, by));
    }

    function jump(digit) {
        land(Lib.jump(names, selected, digit));
    }

    // The card the cursor lands on plays its theme's switch in miniature; the desktop waits for Enter.
    function land(name) {
        if (name === selected)
            return;
        const t0 = Date.now();
        selected = name;
        played = name;
        cardList.itemAt(names.indexOf(name))?.play(t0);
    }

    function apply() {
        // dots theme measures the switch from this key press, not from its own start.
        dotsTheme.environment = { DOTS_SWITCH_T0: String(Date.now()) };
        dotsTheme.command = [Quickshell.shellDir + "/../bin/dots", "theme", selected];
        dotsTheme.running = true;
        close();
    }

    function state() {
        return JSON.stringify({
            open: shown,
            themes: names,
            selected: selected,
            current: theme.name,
            openMs: openMs,
            opens: opens,
            motion: motion.curves?.kind ?? null,
            settleMs: motion.settleMs,
            settled: motion.settled,
            drawing: switcher.visible,
            cardBox: panel.drawnBox(),
            header: [title.text + sub.text, headRight.text],
            legend: legend.line(),
            cards: cards.drawn(),
            played: played ? { name: played, ms: cardList.itemAt(names.indexOf(played))?.playedMs ?? null } : null
        });
    }

    Component.onCompleted: Root.State.loaded.push("themes")

    Process {
        id: dotsTheme
        stderr: StdioCollector {
            onStreamFinished: if (text)
                console.warn("dots theme: " + text)
        }
    }

    visible: motion.drawing

    Item {
        id: keys
        anchors.fill: parent
        focus: true
        Keys.onPressed: event => {
            if (event.key === Qt.Key_J || event.key === Qt.Key_Right)
                switcher.move(1);
            else if (event.key === Qt.Key_K || event.key === Qt.Key_Left)
                switcher.move(-1);
            else if (event.key >= Qt.Key_1 && event.key <= Qt.Key_9)
                switcher.jump(event.key - Qt.Key_0);
            else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter)
                switcher.apply();
            else if (event.key === Qt.Key_Escape)
                switcher.close();
            else
                return;
            event.accepted = true;
        }

        Rectangle {
            anchors.fill: parent
            color: Qt.alpha(c.paper, panel.style.wash)
        }

        Root.Surface {
            id: panel
            x: Math.round((parent.width - width) / 2)
            y: 140
            width: 1056
            height: column.implicitHeight
            tokens: switcher.theme.tokens
            label: "Themes"
            motion: switcher.motion

            Column {
                id: column
                width: parent.width

                Item {
                    width: parent.width
                    height: title.height + 32

                    Row {
                        x: 22
                        y: 18
                        spacing: 12
                        Text {
                            id: title
                            textFormat: Text.PlainText
                            text: switcher.header.title
                            color: switcher.header.color
                            font.family: switcher.header.font
                            font.pixelSize: switcher.header.size
                            font.weight: switcher.header.weight
                            font.letterSpacing: switcher.look.voice === "bracket" ? 1.76 : 0
                        }
                        Text {
                            id: sub
                            textFormat: Text.PlainText
                            anchors.baseline: title.baseline
                            text: switcher.header.sub
                            color: c.muted
                            font.family: switcher.header.subFont
                            font.pixelSize: switcher.header.subSize
                            font.italic: switcher.header.italic
                            font.letterSpacing: title.font.letterSpacing
                        }
                    }
                    Text {
                        id: headRight
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.baseline: title.baseline
                        text: switcher.header.right
                        color: c.muted
                        font.family: switcher.look.small.font
                        font.pixelSize: switcher.look.small.size
                        font.letterSpacing: switcher.look.small.spacing
                    }
                    Rule {
                        anchors.bottom: parent.bottom
                        visible: switcher.look.voice !== "plain"
                    }
                }

                Item {
                    width: parent.width
                    height: cards.height + 36

                    Row {
                        id: cards
                        x: 22
                        y: 18
                        spacing: 16
                        // n cards share the panel's width; past three the specimens shrink to fit.
                        readonly property real cardWidth: (column.width - 44 - (cardList.count - 1) * spacing) / Math.max(1, cardList.count)

                        // Each card as drawn, in list order.
                        function drawn() {
                            const out = [];
                            for (let i = 0; i < cardList.count; i++)
                                out.push(cardList.itemAt(i).drawn());
                            return out;
                        }

                        Repeater {
                            id: cardList
                            model: switcher.themes

                            Item {
                                id: card
                                required property var modelData
                                required property int index
                                readonly property bool cursor: modelData.name === switcher.selected
                                readonly property bool current: modelData.name === switcher.theme.name
                                readonly property var dress: cursor ? switcher.look.cursor : switcher.look.tile
                                readonly property var tag: switcher.look.tag(current, cursor)
                                readonly property real pad: switcher.look.tile.pad
                                readonly property real fit: Math.min(1, (width - 2 * pad) / specimen.width)
                                width: cards.cardWidth
                                height: specimen.height * fit + 2 * pad

                                function play(t0) {
                                    specimen.play(t0);
                                }

                                readonly property real playedMs: specimen.playedMs

                                function drawn() {
                                    const a = tile.mapToItem(null, 0, 0);
                                    return Object.assign({
                                        name: modelData.name,
                                        box: { x: a.x, y: a.y, w: tile.width, h: tile.height },
                                        fill: tile.color.toString(),
                                        border: { width: tile.border.width, color: tile.border.color.toString() },
                                        number: number.text,
                                        title: name.text,
                                        tag: tagText.visible ? tagText.text : ""
                                    }, specimen.drawn());
                                }

                                // The cursor's hard shadow, offset under the tile.
                                Rectangle {
                                    visible: card.dress.shadow?.kind === "hard"
                                    x: card.dress.shadow?.x ?? 0
                                    y: card.dress.shadow?.y ?? 0
                                    width: parent.width
                                    height: parent.height
                                    color: card.dress.shadow?.color ?? "transparent"
                                }

                                Loader {
                                    active: card.dress.shadow?.kind === "soft" || card.dress.shadow?.kind === "glow"
                                    anchors.fill: parent
                                    sourceComponent: RectangularShadow {
                                        offset.x: card.dress.shadow.x
                                        offset.y: card.dress.shadow.y
                                        // Qt's docs give 1.2 times the CSS blur for the same falloff.
                                        blur: card.dress.shadow.blur * 1.2
                                        spread: card.dress.shadow.spread
                                        radius: card.dress.radius ?? 0
                                        color: Qt.alpha(card.dress.shadow.color, card.dress.shadow.alpha)
                                    }
                                }

                                Rectangle {
                                    id: tile
                                    anchors.fill: parent
                                    radius: switcher.look.tile.radius
                                    color: card.dress.fill
                                    border.width: card.dress.border.width
                                    border.color: card.dress.border.color
                                }

                                // Blueprint's cursor: registration ticks just outside each corner.
                                Repeater {
                                    model: card.dress.ticks ? [[0, 0], [1, 0], [0, 1], [1, 1]] : []
                                    Item {
                                        required property var modelData
                                        x: modelData[0] ? card.width - 4 : -6
                                        y: modelData[1] ? card.height - 4 : -6
                                        width: 10
                                        height: 10
                                        Rectangle {
                                            x: parent.modelData[0] ? 9 : 0
                                            width: 1
                                            height: 10
                                            color: c.accent
                                        }
                                        Rectangle {
                                            y: parent.modelData[1] ? 9 : 0
                                            width: 10
                                            height: 1
                                            color: c.accent
                                        }
                                    }
                                }

                                Root.Specimen {
                                    id: specimen
                                    x: card.pad
                                    y: card.pad
                                    scale: card.fit
                                    transformOrigin: Item.TopLeft
                                    tokens: card.modelData
                                    dir: switcher.theme.dir
                                    under: switcher.c.paper

                                    Item {
                                        width: parent.width
                                        height: name.height
                                        readonly property var cardName: Lib.cardName(card.modelData)
                                        readonly property var tagline: Lib.tagline(card.modelData)

                                        Row {
                                            spacing: 10
                                            Text {
                                                id: number
                                                textFormat: Text.PlainText
                                                visible: text !== ""
                                                anchors.baseline: name.baseline
                                                text: switcher.look.number(card.index)
                                                color: card.cursor ? c.accent : c.muted
                                                font.family: switcher.look.small.font
                                                font.pixelSize: switcher.look.small.size
                                                font.letterSpacing: switcher.look.small.spacing
                                            }
                                            Text {
                                                id: name
                                                textFormat: Text.PlainText
                                                text: parent.parent.cardName.text
                                                color: c.ink
                                                font.family: parent.parent.cardName.font
                                                font.pixelSize: parent.parent.cardName.size
                                                font.weight: parent.parent.cardName.weight
                                                font.letterSpacing: parent.parent.cardName.spacing
                                            }
                                            Text {
                                                textFormat: Text.PlainText
                                                anchors.baseline: name.baseline
                                                // The tag keeps its place; the line gives way before it.
                                                width: Math.max(0, parent.parent.width - x - (tagText.visible ? tagText.implicitWidth + 22 : 0))
                                                elide: Text.ElideRight
                                                text: parent.parent.tagline.text
                                                color: c.muted
                                                font.family: parent.parent.tagline.font
                                                font.pixelSize: parent.parent.tagline.size
                                                font.italic: parent.parent.tagline.italic
                                                font.letterSpacing: parent.parent.tagline.spacing
                                            }
                                        }

                                        Rectangle {
                                            visible: card.tag !== null
                                            anchors.right: parent.right
                                            anchors.verticalCenter: tagText.verticalCenter
                                            width: tagText.implicitWidth + 12
                                            height: tagText.implicitHeight + 4
                                            radius: card.tag?.radius ?? 0
                                            color: card.tag?.fill ?? "transparent"
                                            border.width: card.tag && card.tag.border !== "transparent" ? 1 : 0
                                            border.color: card.tag?.border ?? "transparent"
                                        }
                                        Text {
                                            id: tagText
                                            textFormat: Text.PlainText
                                            visible: card.tag !== null
                                            anchors.right: parent.right
                                            anchors.rightMargin: 6
                                            anchors.baseline: name.baseline
                                            text: card.tag?.text ?? ""
                                            color: card.tag?.color ?? "transparent"
                                            font.family: switcher.look.small.font
                                            font.pixelSize: switcher.look.small.size
                                            font.letterSpacing: switcher.look.small.spacing
                                            font.weight: Font.Medium
                                        }
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    width: parent.width
                    height: legend.height + 24

                    Rule {}

                    Row {
                        id: legend
                        x: 22
                        y: 12
                        spacing: switcher.look.chips ? 8 : 16

                        // The keys as drawn, then Esc, for the state.
                        function line() {
                            const out = [];
                            for (let i = 0; i < legendKeys.count; i++)
                                out.push(legendKeys.itemAt(i).drawnText);
                            return out.concat([esc.text]).join("  ");
                        }

                        Repeater {
                            id: legendKeys
                            model: switcher.look.legend(cardList.count)

                            Rectangle {
                                required property var modelData
                                readonly property string drawnText: keyText.text + " " + wordText.text
                                width: keyRow.width + (switcher.look.chips ? 14 : 0)
                                height: keyRow.height + (switcher.look.chips ? 6 : 0)
                                radius: switcher.look.chips ? 6 : 0
                                color: switcher.look.chips ? switcher.look.chip.fill : "transparent"

                                Row {
                                    id: keyRow
                                    anchors.centerIn: parent
                                    spacing: 5
                                    Text {
                                        id: keyText
                                        textFormat: Text.PlainText
                                        text: parent.parent.modelData.key
                                        color: switcher.look.chip.key
                                        font.family: switcher.look.small.font
                                        font.pixelSize: switcher.look.small.size
                                        font.letterSpacing: switcher.look.small.spacing
                                        font.weight: Font.Bold
                                    }
                                    Text {
                                        id: wordText
                                        textFormat: Text.PlainText
                                        text: parent.parent.modelData.word
                                        color: c.muted
                                        font.family: switcher.look.small.font
                                        font.pixelSize: switcher.look.small.size
                                        font.letterSpacing: switcher.look.small.spacing
                                    }
                                }
                            }
                        }
                    }
                    Text {
                        id: esc
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        anchors.rightMargin: 22
                        anchors.verticalCenter: legend.verticalCenter
                        text: switcher.look.esc
                        color: switcher.look.voice === "plain" ? c.muted : switcher.look.chip.key
                        font.family: switcher.look.small.font
                        font.pixelSize: switcher.look.small.size
                        font.letterSpacing: switcher.look.small.spacing
                        font.weight: switcher.look.voice === "plain" ? Font.Normal : Font.Bold
                    }
                }
            }
        }
    }

    // A rule across the panel in the theme's rule colour, dashed where the theme dashes its rules.
    component Rule: Item {
        width: column.width
        height: 1

        Rectangle {
            anchors.fill: parent
            visible: !switcher.look.rule.dashed
            color: switcher.look.rule.color
        }
        Root.Dashed {
            anchors.fill: parent
            visible: switcher.look.rule.dashed
            color: switcher.look.rule.color
        }
    }
}
