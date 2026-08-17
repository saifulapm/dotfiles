// Power panel model — near-verbatim port of omarchy's
// plugins/panels/power/Model.js. Their `parseProfiles` is not
// here: their profile list comes from `powerprofilesctl`, ours from
// quickshell's PowerProfiles service. `parseKeyValue` reads our
// `bin/system-stats` output, which uses their key<TAB>value contract.

function clampIndex(index, length) {
    if (length <= 0)
        return 0;
    return Math.max(0, Math.min(length - 1, index));
}

function selectProfileIndex(index, delta, profiles) {
    const values = Array.isArray(profiles) ? profiles : [];
    if (values.length === 0)
        return 0;
    return clampIndex(index + delta, values.length);
}

function parseKeyValue(raw) {
    const next = {};
    const lines = String(raw || "").split("\n");
    for (let i = 0; i < lines.length; i++) {
        const idx = lines[i].indexOf("\t");
        if (idx <= 0)
            continue;
        next[lines[i].substring(0, idx)] = lines[i].substring(idx + 1).trim();
    }
    return next;
}

function profileIcon(name) {
    if (name === "power-saver")
        return "󰌪";
    if (name === "balanced")
        return "󰊚";
    if (name === "performance")
        return "󰓅";
    return "󰂄";
}

function batteryFraction(device) {
    return device && device.isPresent ? Math.max(0, Math.min(1, device.percentage)) : 0;
}

// True while the machine is on AC but deliberately not charging — a charge
// limit is holding the battery where it is. Reported as its own state rather
// than as "charging" that never finishes.
function chargeThresholdActive(device, onBattery, states) {
    const d = device || {};
    const s = states || {};
    if (!(d && d.isPresent && !onBattery))
        return false;

    const fraction = batteryFraction(d);
    if (d.state === s.Discharging)
        return false;
    if (d.state === s.PendingCharge)
        return true;
    if (d.state === s.FullyCharged && fraction < 0.99)
        return true;
    if (d.state !== s.Charging || fraction >= 0.99)
        return false;

    return Number(d.changeRate || 0) <= 0.2 || Number(d.timeToFull || 0) >= 8 * 60 * 60;
}

function batteryIcon(device, onBattery, states) {
    const d = device || {};
    if (!d.isPresent)
        return "";

    const chargingIcons = ["󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅"];
    const defaultIcons = ["󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹"];
    const index = Math.max(0, Math.min(9, Math.floor(d.percentage * 10)));

    if (chargeThresholdActive(d, onBattery, states))
        return defaultIcons[index];
    if (d.state === states.FullyCharged)
        return "󰂅";
    if (!onBattery)
        return chargingIcons[index];
    return defaultIcons[index];
}

function modeLabel(device, onBattery, states) {
    const d = device || {};
    if (!d.isPresent)
        return "";

    const percentage = d.isPresent ? d.percentage : 0;
    if (chargeThresholdActive(d, onBattery, states))
        return "Threshold";
    if (onBattery)
        return "On battery";
    if (!onBattery && percentage >= 1)
        return "Fully charged";
    return "Charging";
}

// Seconds → their "1h 20m" / "45m" shape. omarchy formats this in
// omarchy-battery-status' awk; UPower gives us the seconds directly.
function formatDuration(seconds) {
    const total = Math.round(Number(seconds || 0) / 60);
    if (total <= 0)
        return "";
    const hours = Math.floor(total / 60);
    const minutes = total % 60;
    if (hours <= 0)
        return minutes + "m";
    return minutes > 0 ? hours + "h " + minutes + "m" : hours + "h";
}

function formatWatts(rate) {
    const n = Number(rate || 0);
    if (!isFinite(n) || n <= 0)
        return "";
    return (Math.round(n * 10) / 10) + "W";
}

function formatCapacity(energyCapacity) {
    const n = Number(energyCapacity || 0);
    if (!isFinite(n) || n <= 0)
        return "";
    return Math.round(n) + "Wh";
}
