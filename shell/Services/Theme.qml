import QtQuick
import Quickshell
import Quickshell.Io
import "../Commons/color.js" as ColorMath
import "../Commons/defaults.js" as Defaults

// Token resolution + live reload. Instantiated once by shell.qml and passed
// down by property injection — relative-path singleton imports do not share
// state (see CREDITS.md: omarchy).
//
// Reads the active theme from ~/.local/state/qshell/theme.toml (a symlink
// repointed by bin/theme-set). Every token falls back to the builtin values
// below, so the shell renders identically with a missing or broken theme.
QtObject {
    id: root

    // Builtin defaults live in Commons/defaults.js — shared with bin/theme-apply
    // so the shell and every templated app agree on fallbacks. A loaded theme
    // overrides per-key; keys it omits return to these values, not to the
    // previous theme's.
    readonly property var builtin: Defaults.THEME_DEFAULTS

    property var values: builtin

    // Preview overlay for the theme switcher: a full candidate token map that
    // temporarily replaces the loaded theme (not merged with it — a preview
    // must show the candidate's fallbacks, not the current theme's values).
    // Any real theme load clears it, so applying a theme needs no handshake.
    property var previewValues: null

    function preview(tokens) {
        previewValues = tokens && typeof tokens === "object" ? tokens : null;
    }

    function endPreview() {
        previewValues = null;
    }

    function tok(key) {
        if (previewValues !== null) {
            const p = previewValues[key];
            return p !== undefined ? p : builtin[key];
        }
        const v = values[key];
        return v !== undefined ? v : builtin[key];
    }
    function num(key) {
        const n = Number(tok(key));
        return isFinite(n) ? n : Number(builtin[key]);
    }
    function col(key) {
        const v = String(tok(key));
        return /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(v) ? v : String(builtin[key]);
    }

    // ------------------------------------------------------------- tokens
    readonly property string mode: String(tok("meta.mode")) === "light" ? "light" : "dark"
    readonly property color surface0: col("surface.0")
    readonly property color surface1: col("surface.1")
    readonly property color surface2: col("surface.2")
    readonly property color surface3: col("surface.3")
    readonly property color textPrimary: col("text.primary")
    readonly property color textMuted: col("text.muted")
    readonly property color textInverse: col("text.inverse")
    // Derived when the theme omits it: contrast-guaranteed against the accent
    // (noctalia's construction rule, via Commons/color.js).
    readonly property color textOnAccent: {
        const v = values["text.on-accent"];
        if (v !== undefined && /^#[0-9A-Fa-f]{6}$/.test(String(v)))
            return String(v);
        return ColorMath.ensureContrast(col("surface.0"), col("accent.accent"), 4.5);
    }
    readonly property color accent: col("accent.accent")
    readonly property color error: col("accent.error")
    readonly property color warn: col("accent.warn")
    readonly property color okColor: col("accent.ok")
    readonly property real radiusBase: num("shape.radius")
    readonly property int borderWidth: Math.round(num("shape.border-width"))
    readonly property real spaceUnit: num("space.unit")
    readonly property real density: num("space.density")
    readonly property string fontUi: String(tok("font.ui"))
    readonly property string fontMono: String(tok("font.mono"))
    readonly property int fontSize: Math.round(num("font.size"))
    readonly property int motionDuration: Math.round(num("motion.duration"))
    readonly property int barHeight: Math.round(num("bar.height"))
    readonly property int easing: {
        const e = String(tok("motion.easing"));
        if (e === "snap")
            return Easing.OutQuint;
        if (e === "spring")
            return Easing.OutBack;
        return Easing.OutCubic;
    }

    // ------------------------------------------------------------ helpers
    // Every gap, corner, and animation in the shell goes through these, so a
    // theme setting radius = 0 / duration = 0 / density = 0.85 changes the
    // desktop's character, not just its colors.
    function space(n) {
        return Math.round(spaceUnit * density * n);
    }
    function radius(n) {
        return Math.round(radiusBase * n);
    }
    function time(n) {
        return Math.round(motionDuration * n);
    }
    function fontPx(mult) {
        return Math.max(1, Math.round(fontSize * mult));
    }
    function alpha(c, a) {
        return Qt.rgba(c.r, c.g, c.b, a);
    }

    // ------------------------------------------------------- TOML loading
    // Sectioned key = value walker (strings, numbers, quoted keys, inline
    // comments). Deliberately limited — the schema needs nothing fancier.
    // Pattern from omarchy's Color.qml parseShell (CREDITS.md).
    function parseToml(raw) {
        const out = {};
        const lines = String(raw || "").split("\n");
        let section = "";
        for (let i = 0; i < lines.length; i++) {
            const line = lines[i].trim();
            if (!line || line.startsWith("#"))
                continue;
            const sec = line.match(/^\[([A-Za-z0-9_.-]+)\]\s*(#.*)?$/);
            if (sec) {
                section = sec[1];
                continue;
            }
            const kv = line.match(/^(?:"([^"]+)"|([A-Za-z0-9_-]+))\s*=\s*(?:"([^"]*)"|(-?\d+(?:\.\d+)?)|([A-Za-z][A-Za-z0-9_-]*))\s*(#.*)?$/);
            if (!kv || !section)
                continue;
            const key = kv[1] !== undefined ? kv[1] : kv[2];
            const value = kv[3] !== undefined ? kv[3] : (kv[4] !== undefined ? kv[4] : kv[5]);
            out[section + "." + key] = value;
        }
        return out;
    }

    function load(raw) {
        const parsed = parseToml(raw);
        values = Object.keys(parsed).length > 0 ? parsed : builtin;
        previewValues = null;
        validateContrast();
    }

    // Warn-only: explicit theme choices are respected, but failures are named.
    function validateContrast() {
        const checks = [["text.primary", "surface.0", 4.5], ["text.primary", "surface.2", 4.5], ["text.muted", "surface.0", 3.0]];
        for (const [fg, bg, min] of checks) {
            const r = ColorMath.contrastRatio(col(fg), col(bg));
            if (r < min)
                console.warn("Theme: " + fg + " on " + bg + " is " + r.toFixed(2) + ":1, below " + min + ":1");
        }
    }

    property FileView themeFile: FileView {
        path: Quickshell.env("HOME") + "/.local/state/qshell/theme.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.load(text())
        onFileChanged: reload()
        onLoadFailed: root.values = root.builtin
    }
}
