import QtQuick
import Quickshell
import "../components"
import "../../../components"

// Goals — the one active goal, as a bar label: "SplitRoute 3/7 · 19h".
//
// The widget exists to be SEEN rather than opened. A goal tracker you have to
// launch is one you stop opening by the second week, so the ratio and the
// clock live in the bar itself and the panel is only for editing. The ratio
// always travels with the clock: a bare countdown reads as dread, and the
// count of what is already done is the half that motivates.
//
// It does not hide itself when there is no active goal — it collapses to the
// dimmed glyph alone, a single 27 px slot. A widget that vanished would take
// the only way of creating a goal with it (there is no launcher command for
// this yet), and an empty slot in the corner of the eye is a better prompt to
// set one than an absence nobody notices.
//
// Left click opens the panel. Right click ticks the NEXT task without opening
// anything, which is the whole loop in one gesture — finish a thing, click,
// watch 3/7 become 4/7. Safe to misfire: clicking the row again in the panel
// puts it back.
BarButton {
    id: rootItem

    required property GoalsService goals

    // Collapsed to the icon slot when idle, and on a vertical bar always: a
    // label is a run of text and a 28 px column has nowhere to put one
    // (the window-title widget's rule).
    readonly property bool showLabel: goals.hasActive && !vertical

    fixedWidth: showLabel ? -1 : (vertical ? -1 : 27)
    fixedHeight: vertical ? 27 : -1

    dimmed: !goals.hasActive

    tooltipText: goals.tooltip

    readonly property color markColor: goals.overdue ? theme.warn : rootItem.barFg

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("GoalsPanel.qml", {
                theme: rootItem.theme,
                goals: rootItem.goals
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
    }

    onTapped: button => {
        // Nothing to tick with no goal, and nothing to tick once every task
        // is done — both fall through to the panel, where the answer to
        // "everything is ticked" is the Ship button.
        if (button === Qt.RightButton && rootItem.goals.nextTask)
            rootItem.goals.toggleTask(rootItem.goals.nextTask.id);
        else
            openPanel();
    }

    Behavior on implicitWidth {
        NumberAnimation {
            duration: rootItem.theme.time(1.2)
            easing.type: rootItem.theme.motion.easing
        }
    }

    OpticalGlyph {
        text: "󰣉" // md-bullseye-arrow
        pixelSize: 13
        verticalInkCenter: true
        anchors.verticalCenter: parent.verticalCenter
        color: rootItem.markColor
        opacity: rootItem.goals.overdue ? 1.0 : 0.85
        colorAnimationEnabled: !rootItem.bar || rootItem.bar.foregroundAnimationEnabled === true
    }

    // Three runs rather than one label: the name carries the weight, the
    // clock carries the colour, and the ratio sits between them at the bar's
    // normal presence. Reading the slot left to right should answer "what am
    // I on" before "how long have I got".
    Row {
        anchors.verticalCenter: parent.verticalCenter
        visible: rootItem.showLabel
        spacing: rootItem.theme.space(1)

        StyledText {
            theme: rootItem.theme
            role: StyledText.BodyLarge
            mono: true
            font.weight: Font.DemiBold
            opacity: 1.0
            color: rootItem.markColor
            renderType: Text.NativeRendering
            text: rootItem.goals.barName
        }

        StyledText {
            theme: rootItem.theme
            role: StyledText.BodyLarge
            mono: true
            visible: text !== ""
            opacity: 0.85
            color: rootItem.markColor
            renderType: Text.NativeRendering
            text: rootItem.goals.barRatio
        }

        StyledText {
            theme: rootItem.theme
            role: StyledText.BodyLarge
            mono: true
            visible: rootItem.goals.barTime !== "" && rootItem.goals.barRatio !== ""
            opacity: 0.45
            color: rootItem.markColor
            renderType: Text.NativeRendering
            text: "·"
        }

        // The one coloured thing in the slot. Overdue keeps the warning hue
        // the whole widget takes, so a blown deadline never reads as normal.
        StyledText {
            theme: rootItem.theme
            role: StyledText.BodyLarge
            mono: true
            visible: text !== ""
            opacity: 1.0
            color: rootItem.goals.overdue ? rootItem.theme.warn : rootItem.theme.accent
            renderType: Text.NativeRendering
            text: rootItem.goals.barTime
        }
    }

    PanelLoader {
        id: panelLoader
    }
}
