import QtQuick

// The hero header every bar-widget panel opens with: a mark on the left, a
// title over a status/meta caption, and the panel's headline controls on the
// trailing edge. Nine panels carried this scaffold as private copies
// (ui-audit 2026-08-06, A10); the layout lives here once and the variance
// stays at the call site — the mark and the trailing controls are slots, the
// label styling is knobs defaulting to the majority recipe (title fontUi
// 1.083 DemiBold; caption mono 0.75 DemiBold ls 1.2). The phrase-flavoured
// panels (Tailscale, Dropbox) restyle the caption to their sentence-case
// fontUi 0.833 look through the knobs rather than a second component.
//
// Slot contract, same as the pre-extraction code: `icon` children are plain
// self-sized items (no anchors — the slot centers itself against the row);
// `trailing` children live in a Row and set
// `anchors.verticalCenter: parent.verticalCenter`. Invisible trailing
// controls take no space, which is what the conditional
// `anchors.right: x.visible ? x.left : parent.right` bindings encoded
// before.
Item {
    id: root

    required property var theme

    property alias icon: iconSlot.data
    property alias trailing: trailingRow.data

    property alias title: titleText.text
    property alias titleColor: titleText.color

    property alias meta: metaText.text
    // PhraseRotator fades the caption by object reference; alias, so call
    // sites can keep `target: hero.metaItem`.
    property alias metaItem: metaText
    property alias metaColor: metaText.color
    property alias metaFamily: metaText.font.family
    property alias metaWeight: metaText.font.weight
    property alias metaLetterSpacing: metaText.font.letterSpacing
    property alias metaPixelSize: metaText.font.pixelSize
    property alias metaElide: metaText.elide
    property alias metaVisible: metaText.visible

    // space(3) is the majority; Power and Ai run tighter at space(2),
    // Monitor (no trailing controls) at 0.
    property real labelRightMargin: theme.space(3)

    implicitHeight: Math.max(iconSlot.implicitHeight, labels.implicitHeight, trailingRow.implicitHeight)

    Item {
        id: iconSlot

        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        implicitWidth: childrenRect.width
        implicitHeight: childrenRect.height
    }

    Row {
        id: trailingRow

        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.theme.space(2)
    }

    Column {
        id: labels

        anchors.left: iconSlot.right
        anchors.leftMargin: root.theme.space(3)
        anchors.right: trailingRow.left
        anchors.rightMargin: root.labelRightMargin
        anchors.verticalCenter: parent.verticalCenter
        spacing: root.theme.space(0.5)

        Text {
            id: titleText

            width: parent.width
            color: root.theme.textPrimary
            font.family: root.theme.fontUi
            font.pixelSize: root.theme.fontPx(1.083)
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }

        Text {
            id: metaText

            width: parent.width
            color: root.theme.textMuted
            font.family: root.theme.fontMono
            font.pixelSize: root.theme.fontPx(0.75)
            font.letterSpacing: 1.2
            font.weight: Font.DemiBold
            elide: Text.ElideRight
        }
    }
}
