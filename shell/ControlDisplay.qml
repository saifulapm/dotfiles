import QtQuick

// Control's Display section, not built yet.
Item {
    id: section

    required property var theme
    property int selected: 0
    readonly property var rows: []

    function key(event) {
        return false;
    }

    function state() {
        return {};
    }

    implicitHeight: line.implicitHeight

    Text {
        id: line
        textFormat: Text.PlainText
        leftPadding: 20
        text: "NOT YET"
        color: section.theme.color.muted
        font.family: section.theme.tokens ? section.theme.tokens.type.ui : ""
        font.pixelSize: 10
        font.letterSpacing: 1.2
    }
}
