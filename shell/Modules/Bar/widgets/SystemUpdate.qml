import QtQuick
import Quickshell
import Quickshell.Io
import "../components"

// Pending dnf updates, omarchy system-update style: a 21 px status slot
// with the refresh glyph, visible only when updates exist. The count comes
// from ~/.local/state/qshell/updates, written by bin/check-updates via the
// qshell-updates systemd user timer — the shell only watches the file.
// Click opens the upgrade in a floating terminal.
BarIcon {
    id: rootItem

    property int count: 0

    glyph: "󰚰" // md-update
    status: true
    visible: count > 0
    tooltipText: count + " update" + (count === 1 ? "" : "s") + " available"

    onTapped: Quickshell.execDetached(["foot-run", "--app-id=qshell-float", "-e", "bash", "-lc", "sudo dnf upgrade --refresh; rm -f ~/.local/state/qshell/updates; read -r -p 'done — press enter to close'"])

    FileView {
        path: Quickshell.env("HOME") + "/.local/state/qshell/updates"
        watchChanges: true
        printErrors: false
        onLoaded: rootItem.count = parseInt(text(), 10) || 0
        onFileChanged: reload()
        onLoadFailed: rootItem.count = 0
    }
}
