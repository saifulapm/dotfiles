import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import QtQuick
import "." as Root
import "lib/themes.mjs" as Lib

// The theme switcher; stays mapped once loaded, like the launcher, since a remap costs 20 to 30 ms.
PanelWindow {
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

    Connections {
        target: switcher.contentItem.Window.window
        function onFrameSwapped() {
            if (switcher.shown && switcher.openT0 >= 0) {
                switcher.openMs = Date.now() - switcher.openT0;
                switcher.openT0 = -1;
            }
        }
    }

    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: "dots-themes"
    WlrLayershell.keyboardFocus: shown ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    color: "transparent"
    mask: shown ? null : noInput

    Region {
        id: noInput
    }

    Item {
        id: keys
        anchors.fill: parent
        visible: switcher.shown
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
            color: Qt.alpha(c.paper, 0.72)
        }

        // The hard offset shadow, square like the panel.
        Rectangle {
            x: panel.x + 6
            y: panel.y + 6
            width: panel.width
            height: panel.height
            color: c.ink
        }

        Rectangle {
            id: panel
            x: Math.round((parent.width - width) / 2)
            y: 168
            width: 1000
            height: column.implicitHeight + 36
            color: c.surface
            border.color: c.ink
            border.width: 1.5

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

                                    Item {
                                        required property var modelData
                                        x: modelData[0]
                                        y: 30
                                        width: modelData[1]
                                        height: 118

                                        Rectangle {
                                            visible: card.tp.shadow !== "none"
                                            x: card.tp.shadow === "hard-offset" ? 3 : 0
                                            y: card.tp.shadow === "hard-offset" ? 3 : 8
                                            width: parent.width
                                            height: parent.height
                                            radius: card.radius ? 10 : 0
                                            color: card.tp.shadow === "hard-offset" ? card.tc.ink : Qt.alpha(card.tc.ink, 0.18)
                                        }
                                        Rectangle {
                                            anchors.fill: parent
                                            radius: card.radius ? 10 : 0
                                            color: card.tc.surface
                                            border.color: card.frameColor
                                            border.width: card.frameWidth
                                        }
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
