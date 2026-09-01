import QtQuick
import "../components"
import "../../../components"
import "DnsShieldModel.js" as Model

// DNS Shield panel — the helper chain as five verdict rows (client,
// forwarder, LAN listener, live block test, this laptop's own resolver),
// in the family's visual language: hero over the state sentence, the error
// line, read-only rows. The rows are diagnoses, not switches — the chain is
// system units, and turning the family's DNS off is not a one-click thing.
//
// r re-probes, o opens the uBlockDNS dashboard (rules and query log live
// there, not here).
BarPanel {
    id: panel

    required property var dnsshield

    panelTitle: ""
    cardWidth: theme.space(85)

    readonly property var rows: dnsshield.rows

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_R:
            panel.dnsshield.refresh();
            break;
        case Qt.Key_O:
            panel.dnsshield.openDashboard();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // Probe-on-open: one snapshot squares the rows with reality.
    onPanelOpened: panel.dnsshield.refresh()

    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "DNS Shield"
        meta: Model.heroMeta(panel.dnsshield.state)
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0
        metaPixelSize: panel.theme.fontPx(0.833)

        icon: OpticalGlyph {
            text: "󰞀"
            pixelSize: panel.theme.fontPx(1.6)
            color: panel.dnsshield.healthy ? panel.theme.textPrimary : panel.theme.textMuted
            opacity: panel.dnsshield.healthy ? 1.0 : 0.6
        }
    }

    StyledText {
        theme: panel.theme
        role: StyledText.Small

        visible: panel.dnsshield.lastError !== ""
        width: parent.width
        text: panel.dnsshield.lastError
        color: panel.theme.error
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
    }

    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "CHAIN"
            value: panel.dnsshield.healthy ? "BLOCKING" : "CHECK"
        }

        Column {
            id: rowColumn

            width: parent.width
            spacing: panel.theme.space(0.5)

            Repeater {
                model: panel.rows

                StatusRow {
                    required property var modelData

                    width: rowColumn.width
                    row: modelData
                }
            }
        }
    }

    // --------------------------------------------------------------- footer
    Item {
        width: parent.width
        implicitHeight: footerText.implicitHeight

        StyledText {
            id: footerText
            theme: panel.theme
            role: StyledText.Caption
            muted: true

            anchors.left: parent.left
            anchors.right: dashboardChip.left
            anchors.rightMargin: panel.theme.space(2)
            text: "Ads and YouTube for every device the router hands here. AdGuard answers while this machine is off."
            wrapMode: Text.WordWrap
        }

        ChipSurface {
            id: dashboardChip

            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            theme: panel.theme
            implicitWidth: panel.theme.space(8)
            implicitHeight: panel.theme.space(7)
            pointerOver: dashboardMouse.containsMouse

            OpticalGlyph {
                anchors.centerIn: parent
                text: "󰖟"
                color: panel.theme.textPrimary
                pixelSize: panel.theme.fontPx(1.0)
            }

            MouseArea {
                id: dashboardMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: panel.dnsshield.openDashboard()
            }

            PanelHint {
                theme: panel.theme
                visible: dashboardMouse.containsMouse
                anchor: dashboardChip
                above: true
                text: "Open dashboard"
            }
        }
    }

    // ----------------------------------------------------------- components
    component StatusRow: Item {
        id: row

        property var row: null

        implicitHeight: rowLabels.implicitHeight + panel.theme.space(2)

        Column {
            id: rowLabels

            anchors.left: parent.left
            anchors.right: rowState.left
            anchors.rightMargin: panel.theme.space(2)
            anchors.verticalCenter: parent.verticalCenter
            anchors.leftMargin: panel.theme.space(2.5)
            spacing: panel.theme.space(0.25)

            StyledText {
                theme: panel.theme

                width: parent.width
                text: row.row ? row.row.label : ""
                elide: Text.ElideRight
            }

            StyledText {
                theme: panel.theme
                role: StyledText.Caption
                mono: true
                muted: true

                width: parent.width
                text: row.row ? row.row.detail : ""
                elide: Text.ElideRight
            }
        }

        StyledText {
            id: rowState
            theme: panel.theme
            role: StyledText.Caption
            mono: true

            anchors.right: parent.right
            anchors.rightMargin: panel.theme.space(2.5)
            anchors.verticalCenter: parent.verticalCenter
            text: row.row ? row.row.state : ""
            color: row.row && row.row.ok ? panel.theme.textPrimary : panel.theme.error
        }
    }
}
