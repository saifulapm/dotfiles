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
    // Whether `active` recolors the content. Indicators carry their state in
    // opacity instead and switch this off (omarchy's WidgetButton).
    property bool useActiveColor: true
    property bool dimmed: false
    // Width of one content slot: -1 sizes to content + margins.
    property real fixedWidth: -1
    property real horizontalMargin: 8.5

    signal tapped(int button)
    signal wheelMoved(int delta)

    // ------------------------------------------------- click-target registry
    // The bar's drag-to-reorder MouseArea covers every widget, so it takes the
    // left press before any handler under it sees one. Omarchy solves this
    // with a registry (CREDITS.md): every clickable registers with the bar,
    // and a press that did not turn into a drag is dispatched back to whichever
    // registered target sits under the pointer — which is also what lets a
    // button nested inside a widget (a workspace pip, a tray icon, a revealed
    // indicator) stay clickable. Right and middle clicks are not accepted by
    // that MouseArea and reach the TapHandlers below directly.
    function triggerPress(pressedButton) {
        if (button.bar)
            button.bar.hideTooltip(button);
        button.tapped(pressedButton);
    }

    property var registeredBar: null

    function syncClickRegistration() {
        if (registeredBar && registeredBar.unregisterClickTarget)
            registeredBar.unregisterClickTarget(button);
        registeredBar = button.bar;
        if (registeredBar && registeredBar.registerClickTarget)
            registeredBar.registerClickTarget(button);
    }

    onBarChanged: syncClickRegistration()
    Component.onCompleted: syncClickRegistration()
    Component.onDestruction: {
        if (registeredBar && registeredBar.unregisterClickTarget)
            registeredBar.unregisterClickTarget(button);
    }
    // A button that stops being visible or interactive must not leave its
    // tooltip on screen (omarchy's WidgetButton does the same).
    onVisibleChanged: if (!visible && bar)
        bar.hideTooltip(button)
    onEnabledChanged: if (!enabled && bar)
        bar.hideTooltip(button)

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
    readonly property color contentColor: active && useActiveColor ? theme.error : barFg
    readonly property color barFg: bar ? bar.barForeground : theme.textPrimary

    // Width of the painted content, for bar chrome that wants to line up with
    // what the widget draws rather than with the slot it sits in (omarchy's
    // WidgetButton.labelWidth — the open-panel pill reads it).
    readonly property real labelWidth: contentRow.implicitWidth

    // Live hover state, for widgets that hang behavior off it (the indicator
    // container holds its reveal open while a revealed item is hovered).
    readonly property alias hovered: hover.hovered

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
