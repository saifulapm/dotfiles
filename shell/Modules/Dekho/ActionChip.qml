import QtQuick
import "../../components"

// A pill that DOES something: a genre that filters, a crew name that opens a
// person, a season, a filter value. The hub had exactly one of these (the sort
// row) written inline; once genres, crew, seasons and six browse facets all
// wanted the same thing, the inline copy was going to drift the way
// ChipSurface's header describes.
//
// It is a control and has to look like one at a glance — that is most of the
// point of this task. ChipSurface already carries the shell's chosen/cursor/
// hover colours; what this adds is the module's type scale, the pointer-guard
// signal every cursor in this module needs, and a border that never disappears,
// so a chip reads as pressable even at rest and even when nothing is chosen.
ChipSurface {
    id: chip

    // The hub's module-local type scale (Dekho.qml `fonts`).
    required property var fonts
    property string label: ""
    // The keyboard cursor is on this chip.
    property bool current: false

    signal activated
    // The pointer's scene position, so the owner can tell a moved mouse from a
    // chip that scrolled under a stationary one (FilePicker's guard).
    signal entered(real sceneX, real sceneY)

    implicitWidth: chipLabel.implicitWidth + chip.theme.space(7)
    implicitHeight: Math.round(chip.fonts.meta * 2.4)
    width: implicitWidth
    height: implicitHeight
    radius: height / 2
    hasCursor: chip.current
    pointerOver: chipHover.hovered

    StyledText {
        id: chipLabel

        anchors.centerIn: parent
        theme: chip.theme
        font.pixelSize: chip.fonts.meta
        font.weight: Font.DemiBold
        color: chip.chosen || chip.current ? chip.theme.accent : chip.theme.textPrimary
        text: chip.label
    }

    HoverHandler {
        id: chipHover

        cursorShape: Qt.PointingHandCursor
        onPointChanged: {
            if (hovered)
                chip.entered(point.scenePosition.x, point.scenePosition.y);
        }
    }

    TapHandler {
        onTapped: chip.activated()
    }
}
