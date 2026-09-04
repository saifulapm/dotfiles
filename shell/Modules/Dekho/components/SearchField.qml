import QtQuick
import QtQuick.Controls

// omakade's search field (qml/Main.qml:572–624): a real TextField with a glyph
// in its left padding, an accent border while it has the keyboard, Escape to
// clear-then-leave, and Down to hand the keyboard to the grid.
//
// A REAL TextField, which the module could not have before. The old query line
// was a Rectangle drawing a string the key catcher had collected, because a
// focused TextInput eats Left and Right for its own caret and those were how
// you walked a rail (doc §6). The grid owns the arrows now and the field owns
// only itself, so the caret, selection, middle-click paste and Ctrl+A all come
// back for free.
TextField {
    id: field

    required property var style

    signal escaped
    signal steppedDown

    placeholderText: "Search films and series"
    color: style.fg
    placeholderTextColor: style.alpha(style.fg, 0.42)
    font.family: style.fontFamily
    font.pixelSize: style.type(11)
    leftPadding: style.ui(36)
    rightPadding: style.ui(12)
    selectByMouse: true
    focus: false
    Accessible.name: "Search films and series"
    Accessible.description: "Look a title up on TMDB"

    Keys.onEscapePressed: event => {
        if (field.text.length > 0)
            field.clear();
        field.escaped();
        event.accepted = true;
    }
    Keys.onDownPressed: event => {
        field.steppedDown();
        event.accepted = true;
    }

    background: Rectangle {
        radius: field.style.radiusSm
        color: field.style.alpha(field.style.fg, field.activeFocus ? 0.075 : 0.045)
        border.width: field.activeFocus ? field.style.ui(2) : field.style.hairline
        border.color: field.activeFocus ? field.style.accent : field.style.alpha(field.style.fg, 0.15)
    }

    Text {
        textFormat: Text.PlainText
        anchors.left: parent.left
        anchors.leftMargin: field.style.ui(13)
        anchors.verticalCenter: parent.verticalCenter
        text: "⌕"
        color: field.activeFocus ? field.style.accent : field.style.muted
        font.family: field.style.fontFamily
        font.pixelSize: field.style.type(15)
    }
}
