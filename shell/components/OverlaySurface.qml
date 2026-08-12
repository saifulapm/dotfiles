import QtQuick
import Quickshell
import Quickshell.Wayland

// The fullscreen overlay scaffold every centered-card surface hand-rolled
// (ui-audit 2026-08-06, A11): a full-screen Overlay-layer window that grabs
// the keyboard while open, a dimmed click-to-dismiss scrim, and a centered
// glass card easing in with the shared fade+scale entrance. Seven copies
// (Launcher, Emojis, Menu, Clipboard, FilePicker, ReminderFlow,
// FilmstripPicker) collapse onto this; the QR and speed-test overlays stay
// separate on purpose — no fade-out hold, a deep black scrim, and a
// hard-cut close are their design, not drift.
//
// The load-bearing subtleties, kept verbatim from the copies:
// - The window is held visible through the card's fade-OUT, but input drops
//   instantly via the empty mask, so the dying scrim can't eat a click
//   (BarPanel's pattern).
// - Keyboard focus flips Exclusive/None with `opened`. Focus-timing quirks
//   stay at the call site (Clipboard re-acquires focus in onVisibleChanged
//   on this window; see the polkit None→Exclusive note in the audit).
// - The frost is card-shaped and only while blur is enabled and the
//   surface is open; the scrim around it stays a plain dim. It is an
//   in-scene blurred wallpaper (CardFrost), not protocol blur, so it can
//   ride the card's entrance and exit.
//
// Card content is the default property: children land inside the card and
// anchor to it, exactly as they did in the private copies. The card itself
// stays caller-sized (cardWidth/cardHeight — bind computed expressions
// freely). FilmstripPicker's chrome-less variant rides the knobs:
// transparent card, no blur, and a `cardShown` gate stricter than `opened`.
PanelWindow {
    id: root

    required property var theme
    required property bool opened
    property string namespace: "qshell-overlay"

    // Scrim click. Callers route to their hide()/cancel().
    signal dismissed

    property alias cardWidth: card.width
    property alias cardHeight: card.height
    property alias cardRadius: card.radius
    property alias cardColor: card.color
    property alias cardBorderWidth: card.border.width
    // The card's entrance gate — `opened` for every surface but the
    // filmstrip, which also waits for load + settled layout.
    property bool cardShown: root.opened
    // Card-shaped compositor blur; off for chrome-less cards.
    property bool blurable: true

    default property alias content: card.data
    // Window-level extras that must outlive a hidden card — e.g. the
    // filmstrip's empty-state caption, which shows exactly when the card
    // does not. Fills the window above the scrim.
    property alias scrimContent: scrimExtra.data

    // Held through the card's fade-out (see BarPanel.qml): input drops
    // instantly via the mask so the dying scrim can't eat a click.
    visible: root.opened || card.opacity > 0
    mask: root.opened ? null : closedMask
    anchors {
        top: true
        bottom: true
        left: true
        right: true
    }
    exclusionMode: ExclusionMode.Ignore
    color: "transparent"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.namespace: root.namespace
    WlrLayershell.keyboardFocus: root.opened ? WlrKeyboardFocus.Exclusive : WlrKeyboardFocus.None

    Region {
        id: closedMask
    }

    Rectangle {
        anchors.fill: parent
        // The [menu] scrim token (same default composition: surface0 at
        // 0.5): every overlay draws the menu visual language, so a theme
        // that restyles the menu's scrim restyles them all together.
        color: root.theme.menu.scrim
        opacity: root.opened ? 1 : 0
        Behavior on opacity {
            NumberAnimation {
                // Asymmetric like omarchy's window animations: exits run
                // faster than entrances, which is most of what reads as
                // "snappy". The binding re-evaluates when the Behavior
                // fires, so each direction gets its own duration.
                duration: root.opened ? root.theme.time(0.5) : root.theme.time(0.35)
                easing.type: root.theme.easing
            }
        }

        MouseArea {
            anchors.fill: parent
            onClicked: root.dismissed()
        }
    }

    Item {
        id: scrimExtra

        anchors.fill: parent
    }

    // Card-shaped frost: an in-scene blurred-wallpaper backdrop that rides
    // the card's fade and scale, so the frost opens and closes with the
    // card instead of popping in behind it (see CardFrost.qml for why the
    // protocol blur can never do this). The scrim around it stays a plain
    // dim, and its tint is folded into the frost so the card area keeps
    // the same dimming the protocol blur got from sitting under it.
    CardFrost {
        theme: root.theme
        card: card
        windowWidth: root.width
        windowHeight: root.height
        tint: root.theme.menu.scrim
        visible: root.blurable && root.theme.blurActive && card.visible
    }

    Rectangle {
        id: card

        anchors.centerIn: parent
        radius: root.theme.radius(1.5)
        color: root.theme.glass(root.theme.surface1)
        border.width: root.theme.borderWidth
        border.color: root.theme.surface3

        // Also gates input: at opacity 0 an open-but-not-settled filmstrip
        // must not take clicks, and invisible is what blocks them.
        visible: opacity > 0
        opacity: root.cardShown ? 1 : 0
        scale: root.cardShown ? 1 : 0.96
        Behavior on opacity {
            NumberAnimation {
                // Matches the scrim: quicker in, quicker still out.
                duration: root.cardShown ? root.theme.time(0.5) : root.theme.time(0.35)
                easing.type: root.theme.easing
            }
        }
        Behavior on scale {
            NumberAnimation {
                duration: root.cardShown ? root.theme.time(0.5) : root.theme.time(0.35)
                easing.type: root.theme.easing
            }
        }

        MouseArea {
            // Swallow clicks so they don't fall through to the scrim.
            anchors.fill: parent
        }
    }
}
