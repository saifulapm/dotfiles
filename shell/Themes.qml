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
            opens: opens
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

    visible: shown

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

            Column {
                id: column
                x: 18
                y: 18
                width: parent.width - 36
                spacing: 16

                Row {
                    spacing: 12
                    Text {
                        anchors.baseline: currentName.baseline
                        text: "THEMES"
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 11
                        font.letterSpacing: 0.66
                    }
                    Text {
                        id: currentName
                        text: "current: " + switcher.theme.name
                        color: c.muted
                        font.family: fonts.ui
                        font.pixelSize: 12
                    }
                }

                Row {
                    id: cards
                    spacing: 16

                    Repeater {
                        model: switcher.themes

                        Item {
                            id: card
                            required property var modelData
                            readonly property var tc: modelData.color
                            readonly property var tp: modelData.primitive
                            readonly property real radius: tp.corner === "round" ? 12 : 0
                            readonly property color frameColor: tp.frame === "glow" ? tc.accent : tp.frame === "hairline" ? tc.line : tc.ink
                            readonly property real frameWidth: tp.frame === "none" ? 0 : tp.frame === "double" ? 3 : 1
                            width: (column.width - 2 * cards.spacing) / 3
                            height: caption.y + caption.height

                            Rectangle {
                                anchors.fill: parent
                                anchors.margins: -6
                                visible: card.modelData.name === switcher.selected
                                color: "transparent"
                                border.color: c.accent
                                border.width: 2
                                radius: 4
                            }

                            Rectangle {
                                id: preview
                                width: parent.width
                                height: 190
                                clip: true
                                color: card.tc.paper
                                radius: card.radius
                                border.color: card.frameColor
                                border.width: card.frameWidth

                                Repeater {
                                    model: [[24, 150], [188, 84]]

                                    // Each preview window is drawn in its own theme's primitives, not the current one's.
                                    Root.Surface {
                                        required property var modelData
                                        x: modelData[0]
                                        y: 30
                                        width: modelData[1]
                                        height: 118
                                        tokens: card.modelData
                                        role: "window"
                                    }
                                }

                                Text {
                                    anchors.horizontalCenter: parent.horizontalCenter
                                    y: 8
                                    text: "14:32"
                                    color: card.tc.ink
                                    font.family: card.modelData.type.display
                                    font.pixelSize: 13
                                }
                            }

                            Item {
                                id: caption
                                y: preview.height + 10
                                width: parent.width
                                height: name.height

                                Text {
                                    id: name
                                    text: card.modelData.name.charAt(0).toUpperCase() + card.modelData.name.slice(1)
                                    color: c.ink
                                    font.family: card.modelData.type.display
                                    font.pixelSize: 20
                                }
                                Text {
                                    anchors.right: parent.right
                                    anchors.baseline: name.baseline
                                    text: Lib.summary(card.modelData)
                                    color: c.muted
                                    font.family: fonts.mono
                                    font.pixelSize: 11
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
                        text: "j/k or ←/→ choose    ↵ apply (≤ 300 ms)"
                        color: c.muted
                        font.family: fonts.mono
                        font.pixelSize: 11
                    }
                    Text {
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
