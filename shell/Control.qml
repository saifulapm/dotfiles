import QtQuick
import QtQuick.Layouts
import "." as Root
import "lib/control.mjs" as Lib

// A section is an Item with: required property var theme; property int selected; readonly property var rows ([{title, detail}]); function key(event): bool for keys other than Tab, Shift+Tab, j/k, Up/Down and Esc; function state(): object; its implicitHeight sizes its band above the rows.
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

    function state() {
        return JSON.stringify(Object.assign({
            open: shown,
            section: Lib.SECTIONS[current],
            sections: Lib.SECTIONS,
            selected: section.selected,
            rows: rows.map(r => r.title),
            openMs: openMs,
            opens: opens,
            // The window has the keyboard; niri lists a layer Exclusive a moment before its keys arrive.
            keyboard: control.Window.active
        }, section.state()));
    }

    Component.onCompleted: Root.State.loaded.push("control")
    visible: shown

    Keys.onPressed: event => {
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

        ColumnLayout {
            id: column
            width: parent.width
            spacing: 0

            RowLayout {
                Layout.fillWidth: true
                Layout.leftMargin: 20
                Layout.rightMargin: 20
                Layout.topMargin: 14
                Layout.bottomMargin: 14
                spacing: 4

                Repeater {
                    model: Lib.TITLES

                    Rectangle {
                        required property string modelData
                        required property int index
                        readonly property bool on: index === control.current
                        implicitWidth: tab.implicitWidth + 20
                        implicitHeight: tab.implicitHeight + 10
                        color: on ? c.ink : "transparent"
                        Text {
                            id: tab
                            textFormat: Text.PlainText
                            anchors.centerIn: parent
                            text: modelData
                            color: on ? c.surface : c.muted
                            font.family: fonts.ui
                            font.pixelSize: 13
                        }
                    }
                }

                Item {
                    Layout.fillWidth: true
                }

                Text {
                    textFormat: Text.PlainText
                    text: "⇥ NEXT"
                    color: c.muted
                    font.family: fonts.ui
                    font.pixelSize: 10
                    font.letterSpacing: 1.2
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: c.ink
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

                Repeater {
                    model: control.rows

                    Rectangle {
                        required property var modelData
                        required property int index
                        readonly property bool on: index === control.section.selected
                        width: list.width
                        implicitHeight: row.implicitHeight + 22
                        color: on ? c.ink : "transparent"

                        RowLayout {
                            id: row
                            anchors.fill: parent
                            anchors.leftMargin: 20
                            anchors.rightMargin: 20
                            spacing: 14

                            Text {
                                textFormat: Text.PlainText
                                Layout.fillWidth: true
                                text: modelData.title
                                elide: Text.ElideRight
                                color: on ? c.surface : c.ink
                                font.family: fonts.ui
                                font.pixelSize: 15
                            }
                            Text {
                                textFormat: Text.PlainText
                                text: modelData.detail
                                color: on ? c.line : c.muted
                                font.family: fonts.ui
                                font.pixelSize: 12
                            }
                        }
                    }
                }
            }

            Rectangle {
                Layout.fillWidth: true
                implicitHeight: 1
                color: c.ink
            }

            Text {
                textFormat: Text.PlainText
                Layout.fillWidth: true
                leftPadding: 20
                rightPadding: 20
                topPadding: 12
                bottomPadding: 12
                horizontalAlignment: Text.AlignRight
                text: "TAB · J/K · ESC"
                color: c.muted
                font.family: fonts.ui
                font.pixelSize: 10
                font.letterSpacing: 1.2
            }
        }
    }
}
