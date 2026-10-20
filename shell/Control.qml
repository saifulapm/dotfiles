import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/control.mjs" as Lib
import "lib/voice.mjs" as V

// A section is an Item with: required property var theme; property int selected; readonly property var rows ([{title, detail}]); function key(event): bool for keys other than Tab, Shift+Tab, j/k, Up/Down and Esc, or for every key while its optional typing is true; function state(): object; its implicitHeight sizes its band above the rows.
Item {
    id: control

    required property var theme
    required property var notifs
    required property var sync
    property bool shown: false
    property int current: 0
    property int opens: 0
    property var openMs: null
    // When the open being timed was requested, or -1 once its first frame is swapped.
    property real openT0: -1

    readonly property var c: theme.color
    readonly property var fonts: theme.tokens ? theme.tokens.type : ({})
    readonly property var sections: [audio, wifi, bluetooth, power, display, route]
    readonly property var section: sections[current]
    readonly property var rows: section.rows
    readonly property var look: V.listLook(theme.tokens)
    readonly property var legend: look.keys(section.typing ? [["↵", "join"], ["esc", "cancel"]] : [["tab", "section"], ["j/k", "move"], ["esc", "close"]])
    readonly property Root.Motion motion: Root.Motion {
        shown: control.shown
        tokens: control.theme.tokens
    }

    function open(t0) {
        openT0 = t0;
        openMs = null;
        opens += 1;
        current = 0;
        shown = true;
        forceActiveFocus();
    }

    function close() {
        shown = false;
        // Only the secret clears as Control closes; the rest of the line is drawn until the close stops drawing.
        wifi.psk = "";
    }

    function swapped() {
        if (shown && openT0 >= 0) {
            openMs = Date.now() - openT0;
            openT0 = -1;
        }
    }

    function move(by) {
        section.selected = Math.max(0, Math.min(rows.length - 1, section.selected + by));
    }

    // An item's box in window coordinates.
    function box(item) {
        const p = item.mapToItem(null, 0, 0);
        return { x: p.x, y: p.y, w: item.width, h: item.height };
    }

    function state() {
        const cur = rowRepeater.itemAt(section.selected);
        const tab = tabRepeater.itemAt(current);
        return JSON.stringify(Object.assign({
            open: shown,
            section: Lib.SECTIONS[current],
            sections: Lib.SECTIONS,
            selected: section.selected,
            rows: rows.map(r => r.title),
            openMs: openMs,
            opens: opens,
            motion: motion.curves?.kind ?? null,
            settleMs: motion.settleMs,
            firstFrame: motion.firstFrame,
            settled: motion.settled,
            drawing: control.visible,
            cardBox: card.drawnBox(),
            frameLabel: card.frameLabel(),
            heading: header.visible ? header.text : "",
            tabFill: tab ? String(tab.color) : null,
            tabText: tab ? tab.text : null,
            tabBox: tab ? box(tab) : null,
            ruleBox: box(topRule),
            cursorFill: cur ? String(cur.color) : null,
            cursorBox: cur ? box(cur) : null,
            legend: legend.map(k => k.key + " " + k.word).join("  "),
            legendDrawn: Array.from({ length: legendRepeater.count }, (_, i) => legendRepeater.itemAt(i).label).join("  "),
            legendSpacing: look.small.spacing,
            // The window has the keyboard; niri lists a layer Exclusive a moment before its keys arrive.
            keyboard: control.Window.active
        }, section.state()));
    }

    Component.onCompleted: Root.State.loaded.push("control")
    visible: motion.drawing

    Keys.onPressed: event => {
        // A section's open password line takes every key first, so j, k and Tab type and Esc closes only the line.
        if (section.typing) {
            section.key(event);
            event.accepted = true;
            return;
        }
        const back = event.key === Qt.Key_Backtab || (event.key === Qt.Key_Tab && (event.modifiers & Qt.ShiftModifier));
        if (back)
            current = Lib.cycle(current, -1);
        else if (event.key === Qt.Key_Tab)
            current = Lib.cycle(current, 1);
        else if (event.key === Qt.Key_J || event.key === Qt.Key_Down)
            move(1);
        else if (event.key === Qt.Key_K || event.key === Qt.Key_Up)
            move(-1);
        else if (event.key === Qt.Key_Escape)
            close();
        else if (!section.key(event))
            return;
        event.accepted = true;
    }

    Rectangle {
        anchors.fill: parent
        color: Qt.alpha(c.paper, card.style.wash)
    }

    Root.Surface {
        id: card
        x: Math.round((parent.width - width) / 2)
        y: 168
        width: 720
        height: column.implicitHeight
        tokens: control.theme.tokens
        label: "Control"
        motion: control.motion

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            // Blueprint names Control and its section on a line of their own above the tabs.
            Text {
                id: header
                visible: look.label.kind === "header"
                textFormat: Text.PlainText
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 12
                text: look.heading("control", Lib.SECTIONS[control.current])
                color: look.small.color
                font.family: look.small.font
                font.pixelSize: look.small.size
                font.letterSpacing: look.small.spacing
            }

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: look.label.kind === "header" ? 8 : 14
                Layout.bottomMargin: 14
                spacing: 4

                Repeater {
                    id: tabRepeater
                    model: Lib.TITLES

                    // The current tab takes the launcher's mode label: Paper's ink chip, Artboard's tint pill, Blueprint's cyan cursor.
                    Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool on: index === control.current
                        readonly property string text: tab.text
                        implicitWidth: tab.implicitWidth + 20
                        implicitHeight: tab.implicitHeight + 10
                        radius: look.tab.radius
                        color: on ? look.tab.fill : "transparent"
                        Text {
                            id: tab
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: look.tabText(modelData)
                            color: on ? look.tab.text : c.muted
                            font.family: look.name.font
                            font.pixelSize: 13
                            font.weight: on && look.voice === "plain" ? Font.Medium : Font.Normal
                        }
                    }
                }
            }

            Rule {
                id: topRule
            }

            Item {
                Layout.fillWidth: true
                Layout.topMargin: 12
                implicitHeight: control.section.implicitHeight

                Root.ControlAudio {
                    id: audio
                    width: parent.width
                    visible: control.current === 0
                    theme: control.theme
                }
                Root.ControlWifi {
                    id: wifi
                    width: parent.width
                    visible: control.current === 1
                    theme: control.theme
                }
                Root.ControlBluetooth {
                    id: bluetooth
                    width: parent.width
                    visible: control.current === 2
                    theme: control.theme
                }
                Root.ControlPower {
                    id: power
                    width: parent.width
                    visible: control.current === 3
                    theme: control.theme
                }
                Root.ControlDisplay {
                    id: display
                    width: parent.width
                    visible: control.current === 4
                    theme: control.theme
                }
                Root.ControlRoute {
                    id: route
                    width: parent.width
                    visible: control.current === 5
                    theme: control.theme
                    notifs: control.notifs
                    sync: control.sync
                }
            }

            Column {
                id: list
                Layout.fillWidth: true
                Layout.topMargin: 8
                Layout.bottomMargin: 8
                // Paper's rows run edge to edge; the others sit inset as tiles.
                Layout.leftMargin: look.voice === "plain" ? 8 : look.voice === "bracket" ? 10 : 0
                Layout.rightMargin: Layout.leftMargin

                Repeater {
                    id: rowRepeater
                    model: control.rows

                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool on: index === control.section.selected
                        width: list.width
                        implicitHeight: row.implicitHeight + 22
                        radius: look.cursor.radius
                        color: on ? look.cursor.fill : "transparent"

                        RowLayout {
                            id: row
                            anchors.fill: parent
                            anchors.leftMargin: look.voice === "caps" ? 20 : 12
                            anchors.rightMargin: anchors.leftMargin
                            spacing: 14

                            // Paper marks the cursor row with the accent's ▸.
                            Text {
                                visible: look.slot === "marker"
                                textFormat: Text.PlainText
                                text: "▸"
                                color: on ? look.cursor.marker : "transparent"
                                font.family: fonts.ui
                                font.pixelSize: 15
                            }

                            GridLayout {
                                Layout.fillWidth: true
                                // Artboard sets the detail under the name; the others put it at the right.
                                columns: look.voice === "plain" ? 1 : 2
                                rowSpacing: 0
                                columnSpacing: 14

                                Text {
                                    textFormat: Text.PlainText
                                    Layout.fillWidth: true
                                    text: look.title(modelData.title)
                                    elide: Text.ElideRight
                                    color: on ? look.cursor.text : look.name.color
                                    font.family: look.name.font
                                    font.pixelSize: look.name.size
                                    font.weight: on ? look.cursor.weight : look.name.weight
                                    font.letterSpacing: look.name.spacing
                                }
                                Text {
                                    textFormat: Text.PlainText
                                    text: look.detailText(modelData.detail)
                                    color: on ? look.cursor.detail : look.detail.color
                                    font.family: look.detail.font
                                    font.italic: look.detail.italic
                                    font.pixelSize: look.detail.size
                                    font.letterSpacing: look.detail.spacing ?? 0
                                }
                            }

                            Rectangle {
                                visible: on && look.cursor.badge !== ""
                                implicitWidth: badge.implicitWidth + 14
                                implicitHeight: badge.implicitHeight + 4
                                radius: 6
                                color: c.surface
                                Text {
                                    id: badge
                                    textFormat: Text.PlainText
                                    anchors.centerIn: parent
                                    text: look.cursor.badge
                                    color: look.cursor.text
                                    font.family: fonts.mono
                                    font.pixelSize: 11
                                }
                            }
                        }
                    }
                }
            }

            Rule {}

            // The keys, as chips in Artboard.
            Flow {
                Layout.fillWidth: true
                Layout.leftMargin: look.voice === "plain" ? 14 : 20
                Layout.rightMargin: Layout.leftMargin
                Layout.topMargin: look.voice === "plain" ? 10 : 12
                Layout.bottomMargin: Layout.topMargin
                spacing: look.legend("").chips ? 8 : 14

                Repeater {
                    id: legendRepeater
                    model: control.legend

                    Rectangle {
                        required property var modelData
                        readonly property string label: pairKey.text + " " + pairWord.text
                        width: pair.implicitWidth + (look.legend("").chips ? 14 : 0)
                        height: pair.implicitHeight + (look.legend("").chips ? 6 : 0)
                        radius: 6
                        color: look.chip.fill

                        Row {
                            id: pair
                            anchors.centerIn: parent
                            spacing: look.legend("").chips ? 6 : 5

                            Text {
                                id: pairKey
                                textFormat: Text.PlainText
                                text: modelData.key
                                color: look.chip.key
                                font.family: fonts.mono
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                                font.bold: true
                            }
                            Text {
                                id: pairWord
                                textFormat: Text.PlainText
                                text: modelData.word
                                color: c.muted
                                font.family: look.small.font
                                font.pixelSize: look.small.size
                                font.letterSpacing: look.small.spacing
                            }
                        }
                    }
                }
            }
        }
    }

    // A rule across the card: solid, or dashed in Blueprint.
    component Rule: Rectangle {
        Layout.fillWidth: true
        implicitHeight: 1
        color: look.rule.dashed ? "transparent" : look.rule.color

        Root.Dashed {
            visible: look.rule.dashed
            anchors.fill: parent
            color: look.rule.color
        }
    }
}
