import QtQuick
import QtQuick.Layouts
import Quickshell
import "NotificationLogic.js" as Logic

// Notification card — a full port of omarchy's
// plugins/notifications/components/NotificationCard.qml (CREDITS.md) in our
// theme tokens. Pure presentation: no service, Notification or ListModel
// references, so the popup container owns lifetime and this only draws.
Rectangle {
    id: root

    required property var theme

    property string app: ""
    property string appIcon: ""
    property string summary: ""
    property string body: ""
    property string image: ""
    // Nerd Font glyph rendered in the icon slot when no real icon is set,
    // carried by the `qshell-glyph` hint so a sender's own glyph does not
    // have to leak into the summary text.
    property string glyph: ""
    // Nerd Font glyphs come from the symbols font directly (the UI font has
    // no coverage), same rule as the bar's OpticalGlyph.
    readonly property string glyphFamily: "Symbols Nerd Font"
    // NotificationUrgency: Low = 0, Normal = 1, Critical = 2.
    property int urgency: 1
    property double timestamp: 0
    // Actions as the server reports them; the container passes the live
    // notification's list, or nothing for a replayed history row.
    property var actions: []
    // Remaining share of this toast's lifetime, 1 → 0. Drives the countdown
    // rail along the bottom edge; a lifetime of 0 (critical) hides it.
    property real progress: 1
    property bool showCountdown: false

    readonly property bool hovered: hoverTracker.hovered

    signal closeRequested
    signal cardClicked
    signal actionInvoked(var action)

    // Prefer per-notification media/avatar data, then fall back to the app
    // icon. Anything that fails to resolve leaves the slot empty rather than
    // drawing Qt's broken-image placeholder.
    readonly property string smallIconSource: image.length > 0 ? resolveImage(image) : iconSource(appIcon)
    readonly property bool hasGlyph: glyph.length > 0
    readonly property bool compactGlyph: Logic.shouldRenderCompactGlyph(glyph, smallIconSource, singleLineToast)
    readonly property bool hasSmallIcon: smallIconSource.length > 0
    readonly property bool summaryStartsWithGlyph: Logic.summaryStartsWithGlyph(summary)
    readonly property bool singleLineToast: sanitizedBody.length === 0 && actionRow.count === 0
    readonly property bool collapseRedundantIcon: singleLineToast && !hasGlyph && summaryStartsWithGlyph
    readonly property string sanitizedBody: Logic.sanitizeBody(body, app, appIcon)
    readonly property string styledBody: sanitizedBody.replace(/\r\n|\r|\n/g, "<br/>")

    // Their urgency ladder: critical borrows the urgent colour, low dims,
    // everything else takes the accent. It colours the countdown rail and,
    // for critical (which has no countdown), the card border.
    // Read through the [notifications] surface, so a theme section restyles
    // toasts alone; every key falls back to the base token it always used.
    readonly property color accentColor: urgency === 2 ? theme.notifications.borderError : (urgency === 0 ? theme.notifications.textMuted : theme.notifications.countdown)

    // `notify-send -i <name>` arrives as an `image-path` hint, which
    // Quickshell hands over as `image://icon/<name>` — and its icon provider
    // answers an unknown name with a placeholder texture (the magenta
    // checkerboard) instead of failing, so upstream's Image.Error guard never
    // fires for it. Ask the icon theme first and drop the source when the
    // name resolves to nothing. Provider URLs that carry an explicit
    // `?path=` are left alone: those load from disk, not from the theme.
    function resolveImage(value) {
        const v = String(value || "");
        const prefix = "image://icon/";
        if (v.indexOf(prefix) !== 0 || v.indexOf("?") >= 0)
            return v;
        return Quickshell.iconPath(decodeURIComponent(v.substring(prefix.length)), true);
    }

    function iconSource(icon) {
        const value = String(icon || "");
        if (value.length === 0)
            return "";
        if (value.indexOf("file://") === 0 || value.indexOf("image://") === 0)
            return value;
        if (value.charAt(0) === "/")
            return "file://" + encodeURI(value);
        return Quickshell.iconPath(value, true);
    }

    implicitWidth: theme.space(95)
    implicitHeight: mainColumn.implicitHeight + border.width * 2
    radius: theme.radius(1)
    color: theme.notifications.background
    border.width: Math.max(theme.borderWidth, theme.space(0.5))
    border.color: urgency === 2 ? theme.notifications.borderError : theme.notifications.border
    clip: true

    HoverHandler {
        id: hoverTracker
    }

    MouseArea {
        anchors.fill: parent
        cursorShape: Qt.PointingHandCursor
        acceptedButtons: Qt.LeftButton | Qt.RightButton
        onClicked: mouse => {
            if (mouse.button === Qt.RightButton)
                root.closeRequested();
            else
                root.cardClicked();
        }
    }

    ColumnLayout {
        id: mainColumn
        // Inset by the card border so content never paints over it.
        anchors.top: parent.top
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.topMargin: root.border.width
        anchors.leftMargin: root.border.width
        anchors.rightMargin: root.border.width
        spacing: 0

        RowLayout {
            Layout.fillWidth: true
            Layout.leftMargin: root.theme.space(3)
            Layout.rightMargin: root.theme.space(3)
            Layout.topMargin: root.singleLineToast ? root.theme.space(1.75) : root.theme.space(2.5)
            Layout.bottomMargin: root.singleLineToast ? root.theme.space(1.75) : root.theme.space(2.5)
            spacing: root.collapseRedundantIcon ? 0 : (root.compactGlyph ? root.theme.space(2) : root.theme.space(3))

            Item {
                id: smallIconSlot
                Layout.preferredWidth: visible ? root.theme.space(10) : 0
                Layout.preferredHeight: visible ? root.theme.space(10) : 0
                Layout.alignment: Qt.AlignVCenter
                // Hidden when the icon failed to resolve (a themed name that
                // is not in the icon theme) and there is no glyph fallback.
                visible: !root.collapseRedundantIcon && !root.compactGlyph && (root.hasSmallIcon || root.hasGlyph) && (root.hasGlyph || smallIconImage.status !== Image.Error)

                Image {
                    id: smallIconImage
                    anchors.fill: parent
                    source: root.smallIconSource
                    sourceSize.width: smallIconSlot.width * Screen.devicePixelRatio
                    sourceSize.height: smallIconSlot.height * Screen.devicePixelRatio
                    fillMode: Image.PreserveAspectFit
                    asynchronous: true
                    smooth: true
                    visible: !root.hasGlyph || smallIconImage.status === Image.Ready
                }

                Text {
                    anchors.centerIn: parent
                    visible: root.hasGlyph && smallIconImage.status !== Image.Ready
                    text: root.glyph
                    color: root.theme.notifications.text
                    font.family: root.glyphFamily
                    font.pixelSize: root.theme.fontPx(2.333)
                }
            }

            Text {
                Layout.alignment: Qt.AlignVCenter
                visible: root.compactGlyph
                text: root.glyph
                color: root.theme.notifications.text
                font.family: root.glyphFamily
                font.pixelSize: root.theme.fontPx(1.167)
            }

            ColumnLayout {
                Layout.fillWidth: true
                Layout.alignment: Qt.AlignVCenter
                spacing: root.theme.space(0.5)

                Text {
                    Layout.fillWidth: true
                    visible: root.summary.length > 0
                    text: root.summary
                    color: root.theme.notifications.text
                    font.family: root.theme.fontUi
                    font.pixelSize: root.theme.fontPx(1.167)
                    // Upstream sets `font.bold` here. Title and body are the
                    // same pixel size (theirs too), so weight is the only
                    // thing separating them, and a full 700 makes the title a
                    // slab against the regular-weight body. Maple Mono ships a
                    // real SemiBold face, so this is a face swap rather than a
                    // synthesised weight, and it is what every panel in this
                    // shell already uses for a heading.
                    font.weight: Font.DemiBold
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: 2
                }

                Text {
                    Layout.fillWidth: true
                    Layout.topMargin: root.theme.space(0.5)
                    visible: root.sanitizedBody.length > 0
                    text: root.styledBody
                    textFormat: Text.StyledText
                    color: root.theme.notifications.textMuted
                    font.family: root.theme.fontUi
                    font.pixelSize: root.theme.fontPx(1.167)
                    wrapMode: Text.WordWrap
                    elide: Text.ElideRight
                    maximumLineCount: 3
                }

                // Action buttons are ours: their card renders none and leans
                // entirely on click-the-card invoking the "default" action,
                // which we kept as well.
                RowLayout {
                    id: actionRow
                    readonly property int count: repeater.count
                    Layout.topMargin: count > 0 ? root.theme.space(1.5) : 0
                    visible: count > 0
                    spacing: root.theme.space(2)

                    Repeater {
                        id: repeater
                        model: root.actions

                        delegate: Rectangle {
                            id: actionButton
                            required property var modelData

                            implicitWidth: actionLabel.implicitWidth + root.theme.space(4)
                            implicitHeight: actionLabel.implicitHeight + root.theme.space(2)
                            radius: root.theme.radius(0.5)
                            color: actionHover.hovered ? root.theme.alpha(root.theme.accent, 0.3) : root.theme.alpha(root.theme.accent, 0.15)

                            HoverHandler {
                                id: actionHover
                                cursorShape: Qt.PointingHandCursor
                            }

                            TapHandler {
                                onTapped: root.actionInvoked(actionButton.modelData)
                            }

                            Text {
                                id: actionLabel
                                anchors.centerIn: parent
                                color: root.theme.accent
                                font.family: root.theme.fontUi
                                font.pixelSize: root.theme.fontPx(0.917)
                                text: actionButton.modelData.text
                            }
                        }
                    }
                }
            }
        }
    }

    // Countdown rail: the share of the lifetime still to run, in the urgency
    // colour. Their card computes the same two things (a decaying
    // `remainingLifetime` on the slot, an urgency `accentColor` on the card)
    // and then draws neither — this is what those pieces were for.
    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: root.border.width
        anchors.bottomMargin: root.border.width
        height: root.theme.space(0.5)
        width: Math.max(0, (parent.width - root.border.width * 2) * Math.max(0, Math.min(1, root.progress)))
        color: root.accentColor
        visible: root.showCountdown
        opacity: root.hovered ? 0.45 : 1

        Behavior on opacity {
            NumberAnimation {
                duration: root.theme.time(1)
                easing.type: root.theme.easing
            }
        }
    }
}
