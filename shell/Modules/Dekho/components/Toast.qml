import QtQuick

// omakade's toast: a pill at the bottom of the window for 2.4 seconds. It is
// how this module answers the actions that used to answer with nothing at all —
// a filter cleared, a release chosen, a stop sent. Distinct from the playback
// screen's narration, which is a trail you read; this is a receipt you glance
// at and forget.
Rectangle {
    id: toast

    required property var style
    property string message: ""

    function show(text) {
        toast.message = text;
        timer.restart();
    }

    anchors.horizontalCenter: parent.horizontalCenter
    anchors.bottom: parent.bottom
    anchors.bottomMargin: style.ui(26)
    width: label.implicitWidth + style.ui(34)
    height: style.ui(42)
    radius: style.radiusMd
    color: style.alpha(style.panel, 0.94)
    border.color: style.alpha(style.accent, 0.5)
    opacity: timer.running ? 1 : 0
    visible: opacity > 0

    Behavior on opacity {
        NumberAnimation {
            duration: toast.style.normal
            easing.type: toast.style.easing
        }
    }

    Text {
        id: label

        anchors.centerIn: parent
        text: toast.message
        color: toast.style.fg
        font.family: toast.style.fontFamily
        font.pixelSize: toast.style.type(11)
    }

    Timer {
        id: timer

        interval: 2400
    }
}
