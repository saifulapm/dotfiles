import QtQuick
import QtQuick.Window
import "FocusNav.js" as FocusNav

// omakade's dialog shape (qml/Main.qml:970–1125): a scrim over the whole
// window, a centred opaque panel, click-outside to close, and — the part worth
// having — focus capture and restore. Opening a sheet remembers what had the
// keyboard, focuses the first thing inside, and hands the focus back on the way
// out, so a sheet dismissed by Escape does not leave the page behind it deaf.
//
// The panel is opaque rather than translucent for the same reason the page is
// (doc §10): everything in this module that draws a rounded picture covers its
// corners with a stroke in the colour behind it, and "the colour behind it" has
// to be a colour.
Rectangle {
    id: sheet

    required property var style
    property bool open: false
    // The item to put the focus on when it opens. Left null, the first
    // focusable thing in the chain gets it.
    property var preferredFocus: null

    default property alias content: body.data

    signal dismissed

    property var previousFocus: null

    anchors.fill: parent
    visible: open
    z: 30
    color: style.alpha(style.bg, 0.72)

    onVisibleChanged: {
        if (sheet.visible) {
            sheet.previousFocus = sheet.Window.window ? sheet.Window.window.activeFocusItem : null;
            Qt.callLater(function () {
                FocusNav.focusWithin(sheet.Window.window, sheet, true, sheet.preferredFocus);
            });
        } else if (sheet.previousFocus) {
            const restore = sheet.previousFocus;
            sheet.previousFocus = null;
            if (restore.visible && restore.enabled)
                Qt.callLater(restore.forceActiveFocus);
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: sheet.dismissed()
    }

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(sheet.style.ui(620), parent.width - sheet.style.ui(56))
        height: Math.min(sheet.style.ui(560), parent.height - sheet.style.ui(56))
        radius: sheet.style.radiusLg
        color: sheet.style.alpha(sheet.style.panel, 0.98)
        border.color: sheet.style.alpha(sheet.style.fg, 0.22)

        // Swallows the clicks the scrim's MouseArea would otherwise read as
        // "dismiss".
        MouseArea {
            anchors.fill: parent
        }

        Item {
            id: body

            anchors.fill: parent
            anchors.margins: sheet.style.ui(24)
        }
    }
}
