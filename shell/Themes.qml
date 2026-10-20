import Quickshell
import Quickshell.Io
import QtQuick
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
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property Root.Motion motion: Root.Motion {
        shown: switcher.shown
        tokens: switcher.theme.tokens
    }

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        selected = theme.name;
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
        selected = Lib.step(names, selected, by);
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
            cards: cards.drawn()
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
            y: 168
            width: 1000
            height: column.implicitHeight + 36
            tokens: switcher.theme.tokens
            label: "Themes"
            motion: switcher.motion

            Column {
                id: column
                x: 18
                y: 18
                width: parent.width - 36
                spacing: 16

                Row {
                    spacing: 12
                    Text {
                        textFormat: Text.PlainText
                        anchors.baseline: currentName.baseline
                        text: "THEMES"
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 11
                        font.letterSpacing: 0.66
                    }
                    Text {
                        id: currentName
                        textFormat: Text.PlainText
                        text: "current: " + switcher.theme.name
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 12
                    }
                }

                Row {
                    id: cards
                    spacing: 16

                    // Each card's specimen as drawn, in list order.
                    function drawn() {
                        const out = [];
                        for (let i = 0; i < cardList.count; i++)
                            out.push(Object.assign({ name: cardList.itemAt(i).modelData.name }, cardList.itemAt(i).specimenState()));
                        return out;
                    }

                    Repeater {
                        id: cardList
                        model: switcher.themes

                        Item {
                            id: card
                            required property var modelData
                            width: specimen.width
                            height: specimen.height

                            function specimenState() {
                                return specimen.drawn();
                            }

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -6
                                visible: card.modelData.name === switcher.selected
                                color: "transparent"
                                border.color: c.accent
                                border.width: 2
                                radius: 4
                            }

                            Root.Specimen {
                                id: specimen
                                tokens: card.modelData
                                dir: switcher.theme.dir

                                Row {
                                    width: parent.width
                                    spacing: 10
                                    readonly property var cardName: Lib.cardName(card.modelData)
                                    readonly property var tagline: Lib.tagline(card.modelData)

                                    Text {
                                        id: name
                                        textFormat: Text.PlainText
                                        text: parent.cardName.text
                                        color: c.ink
                                        font.family: parent.cardName.font
                                        font.pixelSize: parent.cardName.size
                                        font.weight: parent.cardName.weight
                                        font.letterSpacing: parent.cardName.spacing
                                    }
                                    Text {
                                        textFormat: Text.PlainText
                                        anchors.baseline: name.baseline
                                        text: parent.tagline.text
                                        color: c.muted
                                        font.family: parent.tagline.font
                                        font.pixelSize: parent.tagline.size
                                        font.italic: parent.tagline.italic
                                        font.letterSpacing: parent.tagline.spacing
                                    }
                                }
                            }
                        }
                    }
                }

                Item {
                    width: column.width
                    height: hint.height

                    Text {
                        id: hint
                        textFormat: Text.PlainText
                        text: "j/k or ←/→ choose    ↵ apply (≤ 300 ms)"
                        color: c.muted
                        font.family: fonts.mono
                        font.pixelSize: 11
                    }
                    Text {
                        textFormat: Text.PlainText
                        anchors.right: parent.right
                        text: "Esc"
                        color: c.muted
                        font.family: fonts.mono
                        font.pixelSize: 11
                    }
                }
            }
        }
    }
}
