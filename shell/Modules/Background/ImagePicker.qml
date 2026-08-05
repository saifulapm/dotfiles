import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"
import "../../components/PickerModel.js" as PickerModel

// Wallpaper picker — the caller half of the filmstrip port (CREDITS.md).
// The strip, the keyboard model and the filter all live in
// components/FilmstripPicker.qml, shared with the theme switcher, which is
// how omarchy has it: their theme switcher is their image selector, opened
// on a directory of theme previews.
//
// Their picker does not preview as you move, and neither does this one: the
// wallpaper only changes when a selection is applied, so cancelling has
// nothing to restore. Applying goes through bin/background-next --set, the
// same atomic write bin/theme-set uses, which the Background module watches.
//
// LazyLoader-gated — nothing here exists until first summoned.
Scope {
    id: pickerRoot

    required property var theme

    readonly property alias open: strip.open
    // The live wallpaper, straight from the state file — this is what the
    // picker opens pre-selected on.
    property string currentPath: ""

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin"

    function show() {
        strip.prepare();
        listProc.running = true;
        strip.open = true;
    }

    function hide() {
        strip.open = false;
    }

    function toggle() {
        if (strip.open)
            hide();
        else
            show();
    }

    function loadRows(rows) {
        const next = PickerModel.loadRows(rows);
        strip.setItems(next, PickerModel.indexForSelectedImage(next, currentPath));
    }

    function apply(index) {
        const item = strip.items[index];
        if (!item || !item.filePath)
            return;
        Quickshell.execDetached([binDir + "/background-next", "--set", item.filePath]);
    }

    Process {
        id: listProc
        command: [pickerRoot.binDir + "/background-next", "--list"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: pickerRoot.loadRows(String(text || ""))
        }
    }

    // The picker's idea of "current" is the same file the wallpaper itself
    // comes from, so an external `background-next` moves the selection too.
    FileView {
        path: Quickshell.env("HOME") + "/.local/state/qshell/background"
        watchChanges: true
        printErrors: false
        // A FileView stays unloaded until something reads it — without this,
        // neither onLoaded nor onLoadFailed ever fires.
        Component.onCompleted: reload()
        onLoaded: pickerRoot.currentPath = text().trim()
        onFileChanged: reload()
        onLoadFailed: pickerRoot.currentPath = ""
    }

    FilmstripPicker {
        id: strip
        theme: pickerRoot.theme
        layerNamespace: "qshell-wallpaper"
        emptyText: "No wallpapers found"
        onApplied: index => pickerRoot.apply(index)
    }
}
