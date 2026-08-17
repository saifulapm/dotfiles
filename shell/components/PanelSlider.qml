import QtQuick

// Minimal slider (no QtQuick.Controls): track, fill, drag/click/wheel.
// Values are absolute (minimum…maximum, default 0–1). While `dragging`,
// `liveValue` follows the pointer so a caller can label the value it is
// about to commit — a node that refuses the write (a mono mic, say) still
// gets a handle that tracks the finger.
Item {
    id: slider

    required property var theme
    property real value: 0
    property real minimum: 0
    property real maximum: 1
    property real step: 0.05
    property bool dragging: false
    property real liveValue: value

    signal moved(real value)
    signal rightClicked

    readonly property real fraction: {
        const span = maximum - minimum;
        if (span <= 0)
            return 0;
        return Math.max(0, Math.min(1, ((dragging ? liveValue : value) - minimum) / span));
    }

    implicitHeight: theme.space(6)

    function clampValue(v) {
        return Math.max(minimum, Math.min(maximum, v));
    }

    function setFromX(x) {
        const v = clampValue(minimum + (x / Math.max(1, width)) * (maximum - minimum));
        liveValue = v;
        moved(v);
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: slider.theme.space(1.5)
        radius: height / 2
        color: slider.theme.surface3
    }

    Rectangle {
        anchors.verticalCenter: parent.verticalCenter
        width: Math.max(height, parent.width * slider.fraction)
        height: slider.theme.space(1.5)
        radius: height / 2
        color: slider.theme.accent
    }

    Rectangle {
        x: parent.width * slider.fraction - width / 2
        anchors.verticalCenter: parent.verticalCenter
        width: slider.theme.space(3.5)
        height: width
        radius: width / 2
        color: slider.theme.textPrimary
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        // The panel scrolls; a drag started on the track belongs to the
        // slider, not to the Flickable underneath it.
        preventStealing: true

        onPressed: mouse => {
            if (mouse.button === Qt.RightButton) {
                slider.rightClicked();
                return;
            }
            slider.dragging = true;
            slider.setFromX(mouse.x);
        }
        onPositionChanged: mouse => {
            if (slider.dragging)
                slider.setFromX(mouse.x);
        }
        onReleased: slider.dragging = false
        onCanceled: slider.dragging = false
        onWheel: wheel => slider.moved(slider.clampValue(slider.value + (wheel.angleDelta.y > 0 ? slider.step : -slider.step)))
    }
}
