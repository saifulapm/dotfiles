import QtQuick
import Quickshell
import Quickshell.Io
import "../../components"
import "../../components/PickerModel.js" as PickerModel

// Theme switcher — omarchy's, which is their image selector opened on a
// directory of theme previews (`omarchy-theme-switcher` builds that directory
// and calls `omarchy-menu-images --print-name --show-labels --filterable
// --lazy-thumbnails --selected <current>`). So this is the same filmstrip the
// wallpaper picker uses, one tile per theme, labelled and pre-selected on the
// active theme, filterable by typing. See CREDITS.md.
//
// Preview images are resolved by bin/theme-list (their find_preview order:
// preview.* in the theme's directory, else the first sorted image in its
// backgrounds/). A theme with neither — no reference clone on this machine —
// still gets a tile: its own surface holding its accent ramp, the swatch the
// list-style switcher used to draw.
//
// What is ours and not theirs: moving the selection LIVE-PREVIEWS the
// highlighted theme across the whole shell (Theme.preview swaps the full
// token map — colors, radius, motion), so the strip restyles itself as you
// walk it. Enter applies for real via bin/theme-set and deliberately leaves
// the preview up: Theme.load() clears it the moment the real theme lands, so
// the handover needs no handshake and never flashes the old theme back.
// Escape or the scrim ends the preview.
//
// LazyLoader-gated — nothing here exists until first summoned via IPC.
Scope {
    id: switcherRoot

    required property var theme

    readonly property alias open: strip.open
    property var themes: []

    readonly property string binDir: Quickshell.env("HOME") + "/.dotfiles/bin"

    function show() {
        strip.prepare();
        listProc.running = true;
        strip.open = true;
    }

    function hide() {
        strip.open = false;
        theme.endPreview();
    }

    function toggle() {
        if (strip.open)
            hide();
        else
            show();
    }

    function loadThemes(raw) {
        let list = [];
        try {
            list = JSON.parse(raw);
        } catch (e) {
            console.warn("ThemeSwitcher: theme-list parse failed:", e);
            list = [];
        }
        themes = list;

        const tiles = [];
        let current = 0;
        for (let i = 0; i < list.length; i++) {
            const t = list[i];
            const tk = t.tokens || {};
            if (t.current)
                current = i;
            tiles.push({
                key: t.name,
                // Their label is the preview file's basename title-cased, and
                // that basename is the theme name.
                label: PickerModel.labelForPath(t.name),
                imagePath: t.preview || "",
                swatch: {
                    background: tk["surface.1"] || "#000000",
                    dots: [tk["accent.accent"], tk["accent.error"], tk["accent.warn"], tk["accent.ok"], tk["text.primary"]]
                }
            });
        }
        strip.setItems(tiles, current);
    }

    function previewSelection() {
        if (!strip.open)
            return;
        const t = themes[strip.selectedIndex];
        if (t && t.tokens)
            theme.preview(t.tokens);
    }

    function apply(index) {
        const t = themes[index];
        if (!t)
            return;
        Quickshell.execDetached([binDir + "/theme-set", t.name]);
    }

    Process {
        id: listProc
        command: [switcherRoot.binDir + "/theme-list", "--json"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: switcherRoot.loadThemes(String(text || "[]"))
        }
    }

    FilmstripPicker {
        id: strip
        theme: switcherRoot.theme
        layerNamespace: "qshell-themes"
        emptyText: "No themes found"

        onSelectedIndexChanged: switcherRoot.previewSelection()
        onApplied: index => switcherRoot.apply(index)
        onCancelled: switcherRoot.theme.endPreview()
    }
}
