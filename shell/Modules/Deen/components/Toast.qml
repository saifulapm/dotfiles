import QtQuick

// Dekho's toast, unchanged: a pill at the bottom of the window for 2.4 seconds.
//
// It is how this hub answers the actions that used to answer with nothing at
// all — a surah enrolled, a card graded, a word sent to the speakers. Adding an
// ayah to the memorisation queue from the Read screen changed a number on a
// screen you were not looking at, and nothing else.
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
        textFormat: Text.PlainText

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
