import QtQuick

// Omarchy's WidgetButton, ported: the bar has NO button chrome.
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

    // Bar orientation, for widgets that lay themselves out along it. A widget
    // built before its `bar` is injected reads horizontal, which is also what
    // it renders as until the injection lands.
    readonly property bool vertical: bar ? bar.vertical === true : false
    readonly property int barSize: bar ? bar.barSize : theme.barHeight

    property string tooltipText: ""
    property bool active: false
    // Whether `active` recolors the content. Indicators carry their state in
    // opacity instead and switch this off (omarchy's WidgetButton).
    property bool useActiveColor: true
    property bool dimmed: false
    // Size of one content slot along the bar: -1 sizes to content + margins.
    // Omarchy's pair — a slot is a fixed WIDTH on a horizontal bar and a fixed
    // HEIGHT on a vertical one, and the other axis is the bar's thickness.
    property real fixedWidth: -1
    property real fixedHeight: -1
    property real horizontalMargin: 8.5
    property real verticalPadding: 6

    signal tapped(int button)
    signal wheelMoved(int delta)

    // ------------------------------------------------- click-target registry
    // The bar's drag-to-reorder MouseArea covers every widget, so it takes the
    // left press before any handler under it sees one. Omarchy solves this
    // with a registry: every clickable registers with the bar,
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

    // Their swap: across the bar the button is the bar's thickness, along it
    // it is its content plus margins.
    //
    // The cross axis is the bar's own size and NEVER the parent's — that is
    // omarchy's invariant and it is load-bearing on a vertical bar, where the
    // slot takes its height from this implicitHeight and reading parent.height
    // back out of it closes a size cycle. (The two are the same number on a
    // horizontal bar, since every container between the bar and a nested
    // button is bar-height tall.) For the same reason the orientation is read
    // straight off `bar` rather than through the derived `vertical` below:
    // bindings dirtied by the same change re-evaluate in an arbitrary order,
    // so a stale `vertical` beside a live `bar` would take the wrong branch
    // for a frame — long enough for Qt to see the cycle.
    implicitWidth: fixedWidth > 0 ? fixedWidth : (bar && bar.vertical === true ? barSize : Math.max(12, contentRow.implicitWidth + horizontalMargin * 2))
    implicitHeight: fixedHeight > 0 ? fixedHeight : (bar && bar.vertical === true ? Math.max(12, contentRow.implicitHeight + verticalPadding * 2) : barSize)
    width: implicitWidth
    height: implicitHeight

    opacity: dimmed ? 0.45 : 1
    Behavior on opacity {
        NumberAnimation {
            duration: button.theme.motion.standard
            easing.type: button.theme.motion.easing
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

    // Content stays a Row at both orientations: on a vertical bar a widget
    // shows one thing (the glyph — omarchy hides the labels), so the Row holds
    // a single centered child, and a widget that really does stack (the clock)
    // puts its own Column in here.
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
