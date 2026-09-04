import QtQuick
import QtQuick.Controls

// Dekho's SearchField, retuned for the one string this hub asks you to type: an
// ayah reference like `2:255`. A real TextField with an accent border while it
// has the keyboard, and Escape to give the keyboard back.
//
// NO LEADING GLYPH, unlike the field it is ported from. A search box needs one
// because "type here to search" is not otherwise obvious; a field sitting
// between ◀ and ▶ with `2:255` in it is already saying what it is, and the icon
// only cost the string its centre.
//
// It is centred rather than left-aligned because a reference is three or four
// characters in a field sized for the surah numbers that go to 114, and a short
// string pinned left in a wide box reads as a form field with room left over.
//
// The window's Space shortcut stands down while this has focus — see
// `editingReference` in ReciteScreen — or typing a space into "1:1" would start
// a recording instead of a space.
TextField {
    id: field

    required property var style

    signal escaped

    placeholderText: "1:1"
    color: style.fg
    placeholderTextColor: style.alpha(style.fg, 0.42)
    font.family: style.fontFamily
    font.pixelSize: style.type(13)
    font.weight: Font.DemiBold
    horizontalAlignment: TextInput.AlignHCenter
    leftPadding: style.ui(12)
    rightPadding: style.ui(12)
    selectByMouse: true
    focus: false
    Accessible.name: "Ayah reference"
    Accessible.description: "Surah and ayah, as 2:255"

    Keys.onEscapePressed: event => {
        field.escaped();
        event.accepted = true;
    }

    background: Rectangle {
        radius: field.style.radiusSm
        color: field.style.alpha(field.style.fg, field.activeFocus ? 0.075 : 0.045)
        border.width: field.activeFocus ? field.style.ui(2) : field.style.hairline
        border.color: field.activeFocus ? field.style.accent : field.style.alpha(field.style.fg, 0.15)
    }
}
