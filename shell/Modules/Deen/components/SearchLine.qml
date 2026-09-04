import QtQuick
import QtQuick.Controls

// Dekho's search field, itself omakade's: a real TextField with a glyph in its
// left padding, an accent border while it has the keyboard, Escape to
// clear-then-leave, and Down to hand the keyboard to the list under it.
//
// NOT NAMED SearchField, WHICH IS THE NAME IT HAS OVER THERE. Qt now ships a
// `QtQuick.Controls.SearchField`, and an explicit module import outranks the
// implicit directory one — so in any file that imports QtQuick.Controls (this
// module's picker needs it for ScrollBar) `SearchField` silently resolves to
// Qt's, and every custom property on it fails with "Cannot assign to
// non-existent property", which reads as a typo and is not one.
//
// Dekho's copy is only safe because LibraryScreen.qml happens not to import
// QtQuick.Controls. Adding that import there would break its search line the
// same way, with the same misleading message.
TextField {
    id: field

    required property var style

    // No `submitted` signal of our own: TextField already emits `accepted` on
    // Enter, and a second name for it collides with something in the base type
    // — Qt refuses the handler with "Cannot assign to non-existent property
    // onSubmitted", which reads as a typo and is not one.
    signal escaped
    signal steppedDown

    color: style.fg
    placeholderTextColor: style.alpha(style.fg, 0.42)
    font.family: style.fontFamily
    font.pixelSize: style.type(12)
    leftPadding: style.ui(36)
    rightPadding: style.ui(12)
    selectByMouse: true
    focus: false

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
        font.pixelSize: field.style.type(16)
    }
}
