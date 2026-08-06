import QtQuick
import Quickshell
import Quickshell.Io
import "../Commons/color.js" as ColorMath
import "../Commons/defaults.js" as Defaults
import "../Commons/gradient.js" as Gradient

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

    // Machine-level overrides from ~/.config/qshell/theme-override.toml.
    // Layered on top of whatever theme is active, so a per-machine tweak
    // survives theme switches (omarchy's ~/.config/omarchy/shell.toml).
    // It also wins over a preview, so the switcher shows what you would
    // actually get rather than the candidate theme's unmodified values.
    property var overrideValues: ({})

    // Preview overlay for the theme switcher: a full candidate token map that
    // temporarily replaces the loaded theme (not merged with it — a preview
    // must show the candidate's fallbacks, not the current theme's values).
    // The map comes from `bin/theme-list --json`, which parses the whole file,
    // so it carries the theme's per-surface sections too.
    // Any real theme load clears it, so applying a theme needs no handshake.
    property var previewValues: null

    function preview(tokens) {
        previewValues = tokens && typeof tokens === "object" ? tokens : null;
    }

    function endPreview() {
        previewValues = null;
    }

    // Raw lookup through the whole layer stack — override > preview-or-theme.
    // Returns undefined when no layer defines the key, so callers can tell
    // "unset" from "set to something unparseable".
    function rawTok(key) {
        const o = overrideValues[key];
        if (o !== undefined)
            return o;
        const base = previewValues !== null ? previewValues : values;
        const v = base[key];
        return v !== undefined ? v : undefined;
    }

    function tok(key) {
        const v = rawTok(key);
        return v !== undefined ? v : builtin[key];
    }
    function num(key) {
        const n = Number(tok(key));
        return isFinite(n) ? n : Number(builtin[key]);
    }
    // Every color leaving this service goes through Gradient.qmlColor: a theme
    // writes 8-digit hex the way CSS, niri and omarchy do (#rrggbbaa), and Qt
    // reads that byte order as #aarrggbb.
    function col(key) {
        const v = String(tok(key));
        return /^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(v) ? Gradient.qmlColor(v) : String(builtin[key]);
    }

    // ---------------------------------------------------- per-surface tokens
    // A theme (or the machine override) may carry optional sections that
    // restyle ONE surface — [lock], [polkit], [bar], [panel], [tooltip],
    // [notifications], [menu], [osd] — without touching the base tokens every
    // other surface reads. Anything a section omits falls back to the base
    // token the surface would otherwise have used, so a section is always a
    // partial override. Omarchy's surface-role model (Commons/Color.qml,
    // CREDITS.md) adapted to our single-file themes.

    // A section value may name another token instead of carrying a literal:
    // `border = "accent.error"` reads accent.error. Bounded, so a cycle
    // resolves to the last value seen rather than hanging.
    function deref(value) {
        let s = String(value === undefined ? "" : value).trim();
        for (let i = 0; i < 8; i++) {
            if (!/^[A-Za-z0-9_-]+\.[A-Za-z0-9_-]+$/.test(s))
                break;
            const next = rawTok(s) !== undefined ? rawTok(s) : builtin[s];
            if (next === undefined || String(next).trim() === s)
                break;
            s = String(next).trim();
        }
        return s;
    }

    // Per-surface color: [section] key wins, else the base-token fallback the
    // caller passes in. `fallback` is a color, so callers stay readable
    // (theme.sCol("bar", "text", theme.textPrimary)).
    //
    // A border-ish key may hold a gradient instead of a color; color-only
    // consumers get its first stop, which is omarchy's gradient_start
    // degradation. Use sSpec() where the gradient itself can be drawn.
    function sCol(section, key, fallback) {
        const v = rawTok(section + "." + key);
        if (v === undefined)
            return fallback;
        const s = deref(v);
        if (/^#[0-9A-Fa-f]{6}([0-9A-Fa-f]{2})?$/.test(s))
            return Gradient.qmlColor(s);
        const first = Gradient.firstColor(s);
        return first !== "" ? Gradient.qmlColor(first) : fallback;
    }

    // The raw gradient-or-solid string behind a surface's border key, for the
    // renderers that can draw a gradient. `fallbackSpec` is used verbatim when
    // the section does not name the key.
    function sSpec(section, key, fallbackSpec) {
        const v = rawTok(section + "." + key);
        return v === undefined ? String(fallbackSpec) : deref(v);
    }

    // The `-alpha` companion of a surface key, clamped to 0..1.
    function sAlpha(section, key, fallback) {
        const v = rawTok(section + "." + key + "-alpha");
        if (v === undefined)
            return fallback;
        const n = Number(v);
        return isFinite(n) ? Math.max(0, Math.min(1, n)) : fallback;
    }

    // X + X-alpha composed into one color (omarchy's composed()). Used where
    // an alpha companion is meaningful — card and scrim fills, borders — not
    // for plain text colors, which have no companion.
    function sComposed(section, key, colorFallback, alphaFallback) {
        const base = sCol(section, key, colorFallback);
        const a = sAlpha(section, key, alphaFallback);
        if (a >= 0.999)
            return base;
        const c = Qt.color(base);
        return Qt.rgba(c.r, c.g, c.b, c.a * a);
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
        const v = rawTok("text.on-accent");
        if (v !== undefined && /^#[0-9A-Fa-f]{6}$/.test(String(v)))
            return String(v);
        return ColorMath.ensureContrast(col("surface.0"), col("accent.accent"), 4.5);
    }
    readonly property color accent: col("accent.accent")
    readonly property color error: col("accent.error")
    readonly property color warn: col("accent.warn")
    readonly property color okColor: col("accent.ok")
    // The theme's active-border token: one string carrying either a solid
    // color or a gradient ("#26a269ee #2ec27eee 45deg"), omarchy's grammar
    // for hyprland_active_border. Derived from the accent when a theme omits
    // it, the same way text.on-accent is — a literal default would give every
    // theme without the token tokyo-night's blue.
    readonly property string borderActiveSpec: {
        const v = rawTok("border.active");
        return v !== undefined ? deref(v) : String(col("accent.accent"));
    }
    readonly property color borderActive: {
        const first = Gradient.firstColor(borderActiveSpec);
        return first !== "" ? Gradient.qmlColor(first) : col("accent.accent");
    }
    readonly property real radiusBase: num("shape.radius")
    readonly property int borderWidth: Math.round(num("shape.border-width"))
    readonly property real spaceUnit: num("space.unit")
    readonly property real density: num("space.density")
    // The concrete family the fontconfig `monospace` alias resolves to right
    // now — Maple Mono, pinned by the repo's fontconfig policy
    // (home/dot_config/fontconfig/conf.d/50-qshell.conf).
    //
    // ONE FAMILY DRAWS THE WHOLE SHELL, which is omarchy's design too (their
    // Style.fontFamily is the literal string "monospace"): `fontUi` and
    // `fontMono` are the same value unless a theme overrides one. There is no
    // font picker — user decision 2026-08-06, after trying the split.
    //
    // Resolving the alias rather than handing Qt the literal "monospace"
    // matters: Qt resolves a family name once and caches it, so the alias
    // would freeze at whatever it meant when the shell started.
    property string resolvedMono: String(builtin["font.mono"])

    // PRECEDENCE: a theme that names the token wins, because a theme pinning
    // its typeface is a deliberate choice. A theme that stays quiet — which is
    // every ported one — follows the system alias.
    readonly property string fontUi: {
        const v = rawTok("font.ui");
        return v !== undefined ? String(v) : resolvedMono;
    }
    readonly property string fontMono: {
        const v = rawTok("font.mono");
        return v !== undefined ? String(v) : resolvedMono;
    }
    readonly property int fontSize: Math.round(num("font.size"))
    readonly property int motionDuration: Math.round(num("motion.duration"))
    readonly property int barHeight: Math.round(num("bar.height"))
    // A bar on the left or right edge is a column, and a column needs more
    // room than a strip does: omarchy's two bar sizes, 26 horizontal / 28
    // vertical, as two tokens instead of one.
    readonly property int barWidthVertical: Math.round(num("bar.width-vertical"))
    readonly property int easing: {
        const e = String(tok("motion.easing"));
        if (e === "snap")
            return Easing.OutQuint;
        if (e === "spring")
            return Easing.OutBack;
        return Easing.OutCubic;
    }

    // -------------------------------------------------- surface accessors
    // One object per themable surface. Every member falls back to the base
    // token the surface used before per-surface overrides existed, so a theme
    // that ships no sections renders exactly as it did.
    readonly property QtObject bar: QtObject {
        readonly property color background: root.sComposed("bar", "background", root.surface1, 1.0)
        readonly property color text: root.sCol("bar", "text", root.col("ansi.white"))
        // Widgets calling attention to themselves (recording, updates, urgent).
        readonly property color active: root.sCol("bar", "active", root.error)
    }
    // Bar widget flyout cards (omarchy's [popups]).
    readonly property QtObject panel: QtObject {
        readonly property color background: root.sComposed("panel", "background", root.surface1, 1.0)
        readonly property color text: root.sCol("panel", "text", root.textPrimary)
        // Chains to the theme's active border, as omarchy's popups.border
        // does — so a card picks up a gradient theme without every theme
        // having to restate it.
        readonly property string borderSpec: root.sSpec("panel", "border", root.borderActiveSpec)
        readonly property color border: root.sComposed("panel", "border", root.borderActive, 1.0)
    }
    readonly property QtObject tooltip: QtObject {
        readonly property color background: root.sComposed("tooltip", "background", root.surface1, 0.97)
        readonly property color text: root.sCol("tooltip", "text", root.col("ansi.white"))
        readonly property color border: root.sComposed("tooltip", "border", root.col("ansi.white"), 1.0)
    }
    readonly property QtObject notifications: QtObject {
        readonly property color background: root.sComposed("notifications", "background", root.surface2, 1.0)
        readonly property color text: root.sCol("notifications", "text", root.textPrimary)
        readonly property color textMuted: root.sCol("notifications", "text-muted", root.textMuted)
        readonly property color border: root.sComposed("notifications", "border", root.accent, 1.0)
        readonly property color borderError: root.sComposed("notifications", "border-error", root.error, 1.0)
        readonly property color countdown: root.sCol("notifications", "countdown", root.accent)
    }
    // border / border-active / border-error share one alpha companion: the
    // three states are mutually exclusive in time, so one is enough (theirs).
    readonly property QtObject lock: QtObject {
        readonly property color background: root.sComposed("lock", "background", root.surface1, 0.8)
        readonly property color text: root.sCol("lock", "text", root.textPrimary)
        readonly property color placeholder: root.sCol("lock", "placeholder", root.alpha(root.textPrimary, 0.66))
        readonly property color textError: root.sCol("lock", "text-error", root.error)
        readonly property string borderActiveSpec: root.sSpec("lock", "border-active", root.borderActiveSpec)
        readonly property color borderActive: root.sComposed("lock", "border-active", root.borderActive, root.sAlpha("lock", "border", 1.0))
        readonly property color borderError: root.sComposed("lock", "border-error", root.error, root.sAlpha("lock", "border", 1.0))
        readonly property color selection: root.sComposed("lock", "selection", root.accent, 0.45)
    }
    // Omarchy's [polkit] contract (their Commons/Color.qml): the dialog card,
    // its scrim and the justification pill. border / border-error share one
    // alpha companion, exactly as [lock]'s border states do.
    readonly property QtObject polkit: QtObject {
        readonly property color background: root.sComposed("polkit", "background", root.surface1, 1.0)
        readonly property color text: root.sCol("polkit", "text", root.textPrimary)
        readonly property color textError: root.sCol("polkit", "text-error", root.error)
        readonly property color accent: root.sCol("polkit", "accent", root.accent)
        readonly property string borderSpec: root.sSpec("polkit", "border", root.borderActiveSpec)
        readonly property color border: root.sComposed("polkit", "border", root.borderActive, 1.0)
        readonly property color borderError: root.sComposed("polkit", "border-error", root.error, root.sAlpha("polkit", "border", 1.0))
        readonly property color scrim: root.sComposed("polkit", "scrim", root.surface0, 0.5)
    }
    // Defined for themes to target; the Menu and OSD modules themselves still
    // read base tokens (see the migration note in themes/tokyo-night.toml).
    readonly property QtObject menu: QtObject {
        readonly property color background: root.sComposed("menu", "background", root.surface1, 1.0)
        readonly property color text: root.sCol("menu", "text", root.textPrimary)
        readonly property color border: root.sComposed("menu", "border", root.surface3, 1.0)
        readonly property color scrim: root.sComposed("menu", "scrim", root.surface0, 0.5)
        readonly property color selectedBackground: root.sComposed("menu", "selected-background", root.accent, 0.15)
        readonly property color selectedText: root.sCol("menu", "selected-text", root.accent)
    }
    readonly property QtObject osd: QtObject {
        readonly property color background: root.sComposed("osd", "background", root.surface1, 1.0)
        readonly property color text: root.sCol("osd", "text", root.textPrimary)
        readonly property color border: root.sComposed("osd", "border", root.surface3, 1.0)
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

    // Machine-level override, layered over every theme. Absent by default;
    // watching adds the parent directory too, so creating and deleting the
    // file both take effect live. text() is stale inside the change signal,
    // so both paths route through reload() → onLoaded.
    property FileView overrideFile: FileView {
        id: overrideFile
        path: Quickshell.env("HOME") + "/.config/qshell/theme-override.toml"
        watchChanges: true
        printErrors: false
        onLoaded: root.overrideValues = root.parseToml(text())
        onFileChanged: reload()
        onLoadFailed: root.overrideValues = ({})
    }

    // ------------------------------------------------------ font resolution
    // Theirs (Commons/Style.qml): ask fc-match what the generic alias is, and
    // ask again whenever the policy file changes, so editing it lands live
    // instead of needing the shell restart their script performs.
    function resolveFonts() {
        fcMatchMono.running = true;
    }

    property Process fcMatchMono: Process {
        id: fcMatchMono
        command: ["fc-match", "-f", "%{family[0]}", "monospace"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                const name = String(text || "").trim();
                if (name.length > 0)
                    root.resolvedMono = name;
            }
        }
    }

    property FileView fontconfigFile: FileView {
        id: fontconfigFile
        path: Quickshell.env("HOME") + "/.config/fontconfig/conf.d/50-qshell.conf"
        watchChanges: true
        printErrors: false
        onLoaded: root.resolveFonts()
        onFileChanged: reload()
        // The policy file is chezmoi-managed and normally present, but a
        // checkout that has not been applied yet has to ask fc-match anyway or
        // the shell would sit on the builtin token instead of the family the
        // rest of the desktop draws with.
        onLoadFailed: root.resolveFonts()
    }

    // QFileSystemWatcher arms against nothing when ~/.local/state/qshell does
    // not exist yet and never recovers, so the dir is created up front and the
    // watcher re-armed (only reload() re-runs the arming) once it exists.
    property Process stateDirProc: Process {
        command: ["mkdir", "-p", Quickshell.env("HOME") + "/.local/state/qshell"]
        onExited: root.themeFile.reload()
    }

    // FileView stays unloaded until something reads it, and nothing reads a
    // file that is usually absent — without this neither signal ever fires.
    Component.onCompleted: {
        stateDirProc.running = true;
        overrideFile.reload();
        fontconfigFile.reload();
    }
}
