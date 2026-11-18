import QtQuick
import "." as Root
import "lib/voice.mjs" as V

// While a tool shows, the island draws the tool, not its notice, so the tool draws the latest notice itself: one line at its foot for 5 s, as Control draws a failed pairing.
Text {
    id: note

    required property var theme

    visible: text !== ""
    textFormat: Text.PlainText
    elide: Text.ElideRight
    font.pixelSize: 12

    Connections {
        target: note.theme
        function onNotice(text) {
            note.text = V.line(text);
            clear.restart();
        }
    }

    Root.Tick {
        id: clear
        interval: 5000
        onTriggered: note.text = ""
    }
}
