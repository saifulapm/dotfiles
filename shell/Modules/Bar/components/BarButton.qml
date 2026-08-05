import QtQuick

// Omarchy's WidgetButton, ported (CREDITS.md): the bar has NO button chrome.
// No hover fill, no background — hover feedback is the tooltip and the
// pointer cursor; state is carried by the glyph color alone (active =
// theme.error, matching omarchy's bar.active = red) and by opacity dims.
Item {
    id: button

    required property var theme
    property var bar: null

    // This widget's inline shell.json entry ({id, ...}), injected by the
    // bar's WidgetSlot. Plain-string layout entries arrive as just {id}.
    property var settings: ({})

    // Read one user-tunable value from the inline entry, with a fallback
    // for missing/null values (omarchy's BarWidget.setting).
    function setting(name, fallback) {
        const value = settings ? settings[name] : undefined;
        return value === undefined || value === null ? fallback : value;
    }

    property string tooltipText: ""
    property bool active: false
    property bool dimmed: false
    // Width of one content slot: -1 sizes to content + margins.
    property real fixedWidth: -1
    property real horizontalMargin: 8.5

    signal tapped(int button)
    signal wheelMoved(int delta)

    default property alias content: contentRow.data

    implicitWidth: fixedWidth > 0 ? fixedWidth : Math.max(12, contentRow.implicitWidth + horizontalMargin * 2)
    implicitHeight: parent ? parent.height : contentRow.implicitHeight
    width: implicitWidth
    height: implicitHeight

    opacity: dimmed ? 0.45 : 1
    Behavior on opacity {
        NumberAnimation {
            duration: 140
            easing.type: Easing.OutCubic
        }
    }

    // Color offered to content glyphs/labels: active swaps to the attention
    // color, with omarchy's 160 ms transition.
    readonly property color contentColor: active ? theme.error : barFg
    readonly property color barFg: bar ? bar.barForeground : theme.textPrimary

    Row {
        id: contentRow
        anchors.centerIn: parent
        spacing: 6
    }

    HoverHandler {
        id: hover
        cursorShape: Qt.PointingHandCursor
        onHoveredChanged: {
            if (!button.bar)
                return;
            if (hovered && button.tooltipText !== "")
                button.bar.showTooltip(button, button.tooltipText);
            else
                button.bar.hideTooltip(button);
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onTapped: button.tapped(Qt.LeftButton)
    }

    TapHandler {
        acceptedButtons: Qt.RightButton
        onTapped: button.tapped(Qt.RightButton)
    }

    TapHandler {
        acceptedButtons: Qt.MiddleButton
        onTapped: button.tapped(Qt.MiddleButton)
    }

    WheelHandler {
        onWheel: event => button.wheelMoved(event.angleDelta.y)
    }
}
