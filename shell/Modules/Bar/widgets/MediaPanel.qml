import QtQuick
import "../components"

// The media widget's right-click card — omarchy's media popup
// (shell/plugins/services/media/BarWidget.qml's PopupCard, CREDITS.md) on our
// BarPanel machinery: album art beside title/artist/album, the transport row,
// and the SOURCES list with one row per MPRIS player where clicking a row
// makes it the service's sticky preferred player. The art box falls back to
// their 󰝚 glyph when a track carries no art.
//
// Keyboard is ours in the house panel style (their PopupCard has none, but a
// panel here holds exclusive keyboard focus and should answer): j/k walks the
// source rows, Enter selects, h/l is previous/next, Space play/pause.
BarPanel {
    id: panel

    panelTitle: ""
    cardWidth: 340

    // The shared media service, injected by the widget.
    property var media: null

    readonly property var player: media ? media.activePlayer : null
    readonly property var sourcePlayers: media ? media.sourcePlayers : []
    readonly property string title: media ? media.title : ""
    readonly property string artist: media ? media.artist : ""
    readonly property string album: media ? media.album : ""
    readonly property string artUrl: media ? media.artUrl : ""
    readonly property bool playing: player !== null && player.isPlaying

    function activeKey() {
        return media && player ? media.playerKey(player) : "";
    }

    function transport(action) {
        if (media)
            media.runAction(action, false, media.playerKey(panel.player));
    }

    // -------------------------------------------------------------- cursor
    property bool cursorActive: false
    property int selectedIndex: 0

    // The loader keeps the panel alive across opens — a fresh open parks the
    // cursor again instead of resuming a stale row.
    onPanelClosed: {
        cursorActive = false;
        selectedIndex = 0;
    }

    function moveCursor(delta) {
        const count = panel.sourcePlayers.length;
        if (count === 0)
            return;
        selectedIndex = Math.max(0, Math.min(count - 1, selectedIndex + delta));
    }

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_Down:
        case Qt.Key_J:
            if (panel.cursorActive)
                panel.moveCursor(1);
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Up:
        case Qt.Key_K:
            if (panel.cursorActive)
                panel.moveCursor(-1);
            else
                panel.cursorActive = true;
            break;
        case Qt.Key_Return:
        case Qt.Key_Enter:
            if (panel.cursorActive && panel.media && panel.selectedIndex < panel.sourcePlayers.length)
                panel.media.selectPlayer(panel.media.playerKey(panel.sourcePlayers[panel.selectedIndex]));
            break;
        case Qt.Key_Space:
            panel.transport("playPause");
            break;
        case Qt.Key_Right:
        case Qt.Key_L:
            panel.transport("next");
            break;
        case Qt.Key_Left:
        case Qt.Key_H:
            panel.transport("previous");
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // ------------------------------------------------------------- content
    Column {
        id: sections

        width: parent.width
        spacing: panel.theme.space(2.5)

        // ------------------------------------------------------------ hero
        Row {
            width: parent.width
            spacing: panel.theme.space(2.5)

            Rectangle {
                id: artBox

                width: panel.theme.space(16)
                height: panel.theme.space(16)
                radius: panel.theme.radius(0.75)
                color: panel.theme.surface2
                border.width: panel.theme.borderWidth
                border.color: panel.theme.surface3
                clip: true

                Image {
                    anchors.fill: parent
                    anchors.margins: 1
                    fillMode: Image.PreserveAspectCrop
                    asynchronous: true
                    // Drawn at ~64 px; without a decode cap every distinct
                    // cover of a listening session sits in the pixmap cache
                    // at its native resolution, forever.
                    sourceSize.width: 256
                    sourceSize.height: 256
                    cache: false
                    source: panel.artUrl
                    visible: panel.artUrl !== ""
                }

                OpticalGlyph {
                    anchors.centerIn: parent
                    visible: panel.artUrl === ""
                    text: "󰝚"
                    color: panel.theme.textMuted
                    pixelSize: panel.theme.fontPx(2)
                }
            }

            Column {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - artBox.width - panel.theme.space(2.5)
                spacing: panel.theme.space(0.75)

                Text {
                    width: parent.width
                    text: panel.title || "Nothing playing"
                    color: panel.theme.textPrimary
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(1.083)
                    font.weight: Font.DemiBold
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: panel.artist
                    color: panel.theme.textMuted
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.917)
                    elide: Text.ElideRight
                }

                Text {
                    width: parent.width
                    visible: text !== ""
                    text: panel.album
                    color: panel.theme.alpha(panel.theme.textMuted, 0.7)
                    font.family: panel.theme.fontUi
                    font.pixelSize: panel.theme.fontPx(0.75)
                    elide: Text.ElideRight
                }
            }
        }

        // ------------------------------------------------------- transport
        Item {
            width: parent.width
            implicitHeight: transportRow.implicitHeight

            Row {
                id: transportRow

                anchors.horizontalCenter: parent.horizontalCenter
                spacing: panel.theme.space(1.5)

                TransportButton {
                    glyph: "󰒮"
                    hint: "Previous"
                    enabled: panel.player !== null && panel.player.canGoPrevious
                    onClicked: panel.transport("previous")
                }

                TransportButton {
                    glyph: panel.playing ? "󰏤" : "󰐊"
                    hint: panel.playing ? "Pause" : "Play"
                    glyphSize: panel.theme.fontPx(1.4)
                    buttonWidth: panel.theme.space(14)
                    enabled: panel.player !== null && (panel.player.canTogglePlaying || panel.player.canPlay || panel.player.canPause)
                    onClicked: panel.transport("playPause")
                }

                TransportButton {
                    glyph: "󰒭"
                    hint: "Next"
                    enabled: panel.player !== null && panel.player.canGoNext
                    onClicked: panel.transport("next")
                }
            }
        }

        // --------------------------------------------------------- sources
        Separator {
            visible: panel.sourcePlayers.length > 1
        }

        SectionHeader {
            visible: panel.sourcePlayers.length > 1
            width: parent.width
            label: "SOURCES"
        }

        Column {
            visible: panel.sourcePlayers.length > 1
            width: parent.width
            spacing: panel.theme.space(1)

            Repeater {
                model: panel.sourcePlayers

                Rectangle {
                    id: sourceRow

                    required property var modelData
                    required property int index

                    // Guarded on the active player too (upstream's rule): a
                    // degenerate player with no identity keys to "" and would
                    // otherwise match an empty activeKey.
                    readonly property bool current: panel.player !== null && modelData !== null && panel.media.playerKey(modelData) === panel.activeKey()
                    readonly property bool hasCursor: panel.cursorActive && panel.selectedIndex === index
                    readonly property string sourceTitle: modelData ? (modelData.trackTitle || modelData.identity || modelData.desktopEntry || "Media source") : "Media source"
                    readonly property string sourceDetail: modelData && modelData.trackArtist ? modelData.trackArtist : (modelData && modelData.identity ? modelData.identity : "")

                    width: parent.width
                    implicitHeight: sourceInner.implicitHeight + panel.theme.space(2.5)
                    radius: panel.theme.radius(0.75)
                    color: current ? panel.theme.alpha(panel.theme.accent, 0.18) : (hasCursor ? panel.theme.alpha(panel.theme.textPrimary, 0.06) : "transparent")
                    border.width: panel.theme.borderWidth
                    border.color: hasCursor ? panel.theme.alpha(panel.theme.accent, 0.6) : (current ? panel.theme.alpha(panel.theme.accent, 0.35) : "transparent")

                    Row {
                        id: sourceInner

                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.leftMargin: panel.theme.space(2)
                        anchors.rightMargin: panel.theme.space(2)
                        spacing: panel.theme.space(2)

                        OpticalGlyph {
                            anchors.verticalCenter: parent.verticalCenter
                            text: sourceRow.modelData && sourceRow.modelData.isPlaying ? "󰏤" : "󰐊"
                            color: sourceRow.current ? panel.theme.accent : panel.theme.textPrimary
                            pixelSize: panel.theme.fontPx(0.917)
                        }

                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - panel.theme.space(6)
                            spacing: 0

                            Text {
                                width: parent.width
                                text: sourceRow.sourceTitle
                                color: panel.theme.textPrimary
                                font.family: panel.theme.fontUi
                                font.pixelSize: panel.theme.fontPx(0.917)
                                font.weight: sourceRow.current ? Font.DemiBold : Font.Normal
                                elide: Text.ElideRight
                            }

                            Text {
                                width: parent.width
                                visible: text !== ""
                                text: sourceRow.sourceDetail
                                color: panel.theme.textMuted
                                font.family: panel.theme.fontUi
                                font.pixelSize: panel.theme.fontPx(0.75)
                                elide: Text.ElideRight
                            }
                        }
                    }

                    HoverHandler {
                        cursorShape: Qt.PointingHandCursor
                        onHoveredChanged: {
                            if (hovered) {
                                panel.cursorActive = true;
                                panel.selectedIndex = sourceRow.index;
                            }
                        }
                    }

                    TapHandler {
                        onTapped: if (panel.media)
                            panel.media.selectPlayer(panel.media.playerKey(sourceRow.modelData))
                    }
                }
            }
        }
    }

    // ---------------------------------------------------------- components
    component TransportButton: Rectangle {
        id: transportButton

        property string glyph: ""
        property string hint: ""
        property real glyphSize: panel.theme.fontPx(1.083)
        property real buttonWidth: panel.theme.space(11)
        property bool enabled: true

        signal clicked

        implicitWidth: buttonWidth
        implicitHeight: panel.theme.space(8)
        radius: panel.theme.radius(0.75)
        color: transportHover.hovered && enabled ? panel.theme.alpha(panel.theme.textPrimary, 0.08) : panel.theme.surface2
        border.width: panel.theme.borderWidth
        border.color: panel.theme.surface3
        opacity: enabled ? 1 : 0.4

        OpticalGlyph {
            anchors.centerIn: parent
            text: transportButton.glyph
            color: panel.theme.textPrimary
            pixelSize: transportButton.glyphSize
        }

        HoverHandler {
            id: transportHover
            cursorShape: transportButton.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
        }

        TapHandler {
            enabled: transportButton.enabled
            onTapped: transportButton.clicked()
        }
    }

    component Separator: Rectangle {
        width: sections.width
        height: 1
        color: panel.theme.surface3
    }

    component SectionHeader: Item {
        id: sectionHeader

        property string label: ""

        implicitHeight: sectionLabel.implicitHeight + panel.theme.space(1)

        Text {
            id: sectionLabel
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            text: sectionHeader.label
            color: panel.theme.textMuted
            font.family: panel.theme.fontMono
            font.pixelSize: panel.theme.fontPx(0.75)
            font.letterSpacing: 1.2
            font.weight: Font.DemiBold
        }
    }
}
