// Display panel model. The scale math and the brightness mood ladder are a
// near-verbatim port of omarchy's plugins/panels/monitor/Model.js
// (CREDITS.md); their `parseDisplays` is replaced by `parseState`, which
// reads niri's output JSON instead of hyprctl's.

function clampBrightness(value) {
    const n = Number(value);
    if (!isFinite(n))
        return 1;
    return Math.max(1, Math.min(100, Math.round(n)));
}

function normalizeScale(scale) {
    const n = parseFloat(String(scale || ""));
    if (!isFinite(n))
        return "";
    return String(Math.round(n * 100) / 100);
}

// omarchy's `cleanScale` / `availableScales` / `matchingScaleIndex` are NOT
// ported. They exist because Hyprland only accepts scales that divide the
// mode evenly in 1/120ths, so their panel rounds every preset up to the next
// legal divisor and drops the ones that collide. niri has no such rule — it
// applies whatever fractional scale it is given — and running their math here
// actively misreports: on this 2560x1600 panel it renders the "3" preset as
// "3.2x" and leaves the live 1.5 scale matching no pill at all. The preset a
// niri output is on is simply the one whose number it equals.
function matchingScaleIndex(scales, currentScale) {
    const current = Number(currentScale);
    if (!Array.isArray(scales) || !isFinite(current))
        return -1;
    for (let i = 0; i < scales.length; i++) {
        if (Math.abs(Number(scales[i]) - current) < 0.005)
            return i;
    }
    return -1;
}

// Playful mood-name for a brightness percent. Bands intentionally span
// ~10-20 points, so casual tweaks change the label while small nudges within
// one band don't.
function brightnessName(percent) {
    const p = Math.round(percent);
    if (p >= 95)
        return "Sun blast";
    if (p >= 80)
        return "Solar flare";
    if (p >= 65)
        return "Golden hour";
    if (p >= 45)
        return "Even day";
    if (p >= 30)
        return "Soft glow";
    if (p >= 20)
        return "Lamp light";
    if (p >= 10)
        return "Candlelit";
    return "Night owl";
}

function isInternalOutput(name) {
    return /^(eDP|LVDS|DSI|DP-?[0-9]*-?internal)/i.test(String(name || ""));
}

// One state snapshot, as emitted by the panel's probe: marker lines
// separating `niri msg --json outputs`, `niri msg --json focused-output`,
// `brightnessctl -lm --class=backlight` and the wlsunset probe.
function parseState(raw) {
    const sections = {};
    let current = "";
    const lines = String(raw || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
        const line = lines[i];
        if (line.indexOf("##") === 0) {
            current = line.substring(2).trim();
            sections[current] = [];
            continue;
        }
        if (current && line !== "")
            sections[current].push(line);
    }

    let outputs = [];
    try {
        const map = JSON.parse((sections.outputs || []).join("\n") || "{}");
        outputs = Object.keys(map).sort().map(k => map[k]);
    } catch (e) {
        outputs = [];
    }

    let focused = "";
    try {
        const parsed = JSON.parse((sections.focused || []).join("\n") || "null");
        focused = parsed && parsed.name ? String(parsed.name) : "";
    } catch (e) {
        focused = "";
    }

    // brightnessctl -lm: device,class,current,percent%,max
    const backlights = [];
    const backlightLines = sections.backlights || [];
    for (let i = 0; i < backlightLines.length; i++) {
        const parts = backlightLines[i].split(",");
        if (parts.length < 5)
            continue;
        const percent = parseInt(String(parts[3]).replace("%", ""), 10);
        const max = parseInt(parts[4], 10);
        if (!isFinite(max) || max <= 1)
            continue;
        backlights.push({
            device: parts[0],
            percent: isFinite(percent) ? percent : 0
        });
    }

    // "connector percent" lines from bin/brightness-display-ddc — external
    // displays with working DDC/CI, probed only when ddcutil exists.
    const ddc = [];
    const ddcLines = sections.ddc || [];
    for (let i = 0; i < ddcLines.length; i++) {
        const parts = ddcLines[i].trim().split(/\s+/);
        if (parts.length < 2)
            continue;
        const percent = parseInt(parts[1], 10);
        if (!isFinite(percent))
            continue;
        ddc.push({
            output: parts[0],
            percent: percent
        });
    }

    return {
        outputs: outputs,
        focused: focused,
        backlights: backlights,
        ddc: ddc,
        nightLight: (sections.nightlight || []).join("").trim() === "yes"
    };
}

// Backlight control is a panel-local thing: brightnessctl drives the internal
// panel's backlight, and an external monitor needs DDC/CI, which is a
// different mechanism entirely. Give each internal output the next device in
// the list; everything else gets none.
function backlightForOutput(name, outputs, backlights) {
    if (!Array.isArray(outputs) || !Array.isArray(backlights) || backlights.length === 0)
        return null;

    let seen = 0;
    for (let i = 0; i < outputs.length; i++) {
        const output = outputs[i];
        if (!output || !isInternalOutput(output.name))
            continue;
        if (output.name === name)
            return seen < backlights.length ? backlights[seen] : null;
        seen++;
    }
    return null;
}

function modeLine(output) {
    if (!output || output.current_mode === null || output.current_mode === undefined)
        return "off";
    const mode = (output.modes || [])[output.current_mode];
    if (!mode)
        return "on";
    const scale = output.logical ? output.logical.scale : 1;
    return mode.width + "×" + mode.height + " @ " + Math.round(mode.refresh_rate / 1000) + " Hz · scale " + normalizeScale(scale);
}

function isEnabled(output) {
    return !!(output && output.current_mode !== null && output.current_mode !== undefined);
}

function enabledCount(outputs) {
    if (!Array.isArray(outputs))
        return 0;
    let count = 0;
    for (let i = 0; i < outputs.length; i++) {
        if (isEnabled(outputs[i]))
            count++;
    }
    return count;
}
