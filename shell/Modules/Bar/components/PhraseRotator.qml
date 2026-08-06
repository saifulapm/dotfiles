import QtQuick

// The rotating hero status phrase: every 2.8 s fade the target out, emit
// advance (the panel steps its own phrase index), fade back in — the
// changeover reads as one organism rather than a hard cut. Going !running
// mid-swap restores the target's opacity, a guard three of the five
// original per-panel copies lacked.
Item {
    id: rotator

    required property var theme
    property Item target: null
    property bool running: false

    signal advance

    visible: false

    Timer {
        interval: 2800
        running: rotator.running
        repeat: true
        onTriggered: swap.restart()
    }

    SequentialAnimation {
        id: swap

        PropertyAnimation {
            target: rotator.target
            property: "opacity"
            to: 0.0
            duration: rotator.theme.time(1.2)
            easing.type: Easing.OutQuad
        }

        ScriptAction {
            script: rotator.advance()
        }

        PropertyAnimation {
            target: rotator.target
            property: "opacity"
            to: 1.0
            duration: rotator.theme.time(1.73)
            easing.type: Easing.InQuad
        }
    }

    onRunningChanged: {
        if (!running) {
            swap.stop();
            if (target)
                target.opacity = 1.0;
        }
    }
}
