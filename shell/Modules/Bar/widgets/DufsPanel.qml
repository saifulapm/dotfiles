import QtQuick
import "../components"

// Dufs panel — the file server's card in the family's visual language: a
// hero of the mark over the serving state with the switch as the headline
// control, the addresses the server answers on (click to copy), and the
// credentials a phone types in (generated on this machine, never in the
// repo).
//
// Keys: Enter/Space flips the switch, o opens the server in the browser,
// r re-probes. The rows are copy-only, so there is no row cursor.
BarPanel {
    id: panel

    required property var dufs

    panelTitle: ""
    cardWidth: theme.space(85)

    onContentKey: event => {
        switch (event.key) {
        case Qt.Key_Return:
        case Qt.Key_Enter:
        case Qt.Key_Space:
            panel.dufs.toggle();
            break;
        case Qt.Key_O:
            panel.dufs.openBrowser();
            break;
        case Qt.Key_R:
            panel.dufs.refreshDetails();
            break;
        default:
            return;
        }
        event.accepted = true;
    }

    // Probe-on-open: the unit's word squares a stranded flag with reality,
    // the credentials exist from the first ask, and the address rows follow
    // whatever network this machine is on right now.
    onPanelOpened: panel.dufs.refreshDetails()

    // -------------------------------------------------------------- content
    PanelHero {
        theme: panel.theme
        width: parent.width
        title: "File Server"
        meta: panel.dufs.active ? "Serving home on port " + panel.dufs.port : "Off — nothing is listening"
        metaFamily: panel.theme.fontUi
        metaWeight: Font.Normal
        metaLetterSpacing: 0

        icon: OpticalGlyph {
            text: "󰣳"
            pixelSize: panel.theme.fontPx(1.6)
            verticalInkCenter: true
            color: panel.dufs.active ? panel.theme.textPrimary : panel.theme.textMuted
            opacity: panel.dufs.active ? 1.0 : 0.6
        }

        trailing: [
            // The server in the browser, dimmed while there is nothing to
            // open.
            GlyphButton {
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                glyph: "󰖟" // md-web
                enabled: panel.dufs.active
                hint: "Open in browser"
                onActivated: panel.dufs.openBrowser()
            },
            // The service flips `active` optimistically, so the knob throws
            // on the click rather than when systemd settles.
            PanelSwitch {
                theme: panel.theme
                anchors.verticalCenter: parent.verticalCenter
                checked: panel.dufs.active
                busy: panel.dufs.pending !== ""
                hint: panel.dufs.active ? "Stop sharing" : "Start sharing"
                onToggled: panel.dufs.toggle()
            }
        ]
    }

    // ---------------------------------------------------------- action/error
    Text {
        visible: panel.dufs.actionStatus !== "" || panel.dufs.lastError !== ""
        width: parent.width
        text: panel.dufs.actionStatus !== "" ? panel.dufs.actionStatus : panel.dufs.lastError
        color: panel.dufs.actionStatus !== "" ? panel.theme.textMuted : panel.theme.error
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.833)
        wrapMode: Text.WordWrap
    }

    Separator {
        theme: panel.theme
    }

    // ------------------------------------------------------------- addresses
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "REACH IT AT"
            value: panel.dufs.active ? "LIVE" : "WHEN ON"
        }

        InfoPair {
            theme: panel.theme
            label: "This machine"
            value: panel.dufs.localUrl
            copyValue: panel.dufs.localUrl
            valueColor: panel.theme.textPrimary
            onCopyRequested: copyValue => panel.dufs.copyToClipboard(copyValue, "the local address")
        }

        InfoPair {
            visible: panel.dufs.lanUrl !== ""
            theme: panel.theme
            label: "LAN"
            value: panel.dufs.lanUrl
            copyValue: panel.dufs.lanUrl
            valueColor: panel.theme.textPrimary
            onCopyRequested: copyValue => panel.dufs.copyToClipboard(copyValue, "the LAN address")
        }

        InfoPair {
            visible: panel.dufs.tailscaleUrl !== ""
            theme: panel.theme
            label: "Tailscale"
            value: panel.dufs.tailscaleUrl
            copyValue: panel.dufs.tailscaleUrl
            valueColor: panel.theme.textPrimary
            onCopyRequested: copyValue => panel.dufs.copyToClipboard(copyValue, "the tailnet address")
        }
    }

    // ------------------------------------------------------------ credentials
    Column {
        width: parent.width
        spacing: panel.theme.space(1.5)

        SectionHeader {
            theme: panel.theme
            width: parent.width
            label: "SIGN IN"
            value: ""
        }

        InfoPair {
            theme: panel.theme
            label: "User"
            value: panel.dufs.authUser === "" ? "—" : panel.dufs.authUser
            copyValue: panel.dufs.authUser
            valueColor: panel.theme.textPrimary
            onCopyRequested: copyValue => panel.dufs.copyToClipboard(copyValue, "the user name")
        }

        InfoPair {
            theme: panel.theme
            label: "Password"
            value: panel.dufs.authPassword === "" ? "—" : panel.dufs.authPassword
            copyValue: panel.dufs.authPassword
            valueColor: panel.theme.textPrimary
            onCopyRequested: copyValue => panel.dufs.copyToClipboard(copyValue, "the password")
        }
    }

    // --------------------------------------------------------------- footer
    Text {
        width: parent.width
        text: "Runs only while the switch is on. Serves your home folder over HTTP — dotfiles hidden, uploads allowed — behind the sign-in above."
        color: panel.theme.textMuted
        font.family: panel.theme.fontUi
        font.pixelSize: panel.theme.fontPx(0.75)
        wrapMode: Text.WordWrap
    }
}
