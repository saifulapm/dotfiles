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
// `systemInfo` is optional and was added later: with it, a cap that is switched
// OFF settles the question outright instead of leaving the guesswork below to
// mistake a genuinely slow charge for a held one. Without it the original
// heuristic stands, which is what the tooltip path and the bar icon still use.
function chargeThresholdActive(device, onBattery, states, systemInfo) {
    const d = device || {};
    const s = states || {};
    if (!(d && d.isPresent && !onBattery))
        return false;

    if (systemInfo && String(systemInfo.charge_limit_supported || "") === "1" && String(systemInfo.charge_limit_enabled || "") !== "1")
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

// ------------------------------------------------------------- charge cap
// The cap's real state, from bin/system-stats rather than inferred. `enabled`
// is what the panel's switch reflects and what battery-limit toggles;
// `supported` is what decides whether the section exists at all, which is the
// whole MacBook-only gate — a machine whose battery cannot cap simply has no
// charge-limit UI, with no hostname test anywhere.
function chargeLimit(systemInfo) {
    const info = systemInfo || {};
    const supported = String(info.charge_limit_supported || "") === "1";
    if (!supported)
        return {
            supported: false,
            enabled: false,
            text: ""
        };
    const enabled = String(info.charge_limit_enabled || "") === "1";
    const end = parseInt(info.charge_limit_end, 10);
    const start = parseInt(info.charge_limit_start, 10);
    // `threshold` is already formatted by system-stats as "75-80%" or "80%".
    // Off, it reads "100%", which is true but says nothing worth a row.
    return {
        supported: true,
        enabled: enabled,
        text: enabled ? String(info.threshold || "") : "",
        // The two ends separately, so the panel never has to pick a display
        // string apart to say "stopping at 80%" and "resumes below 75%".
        end: isFinite(end) ? end : 0,
        // 0 when the hardware caps without a resume band — then there is no
        // hysteresis to describe and the panel says nothing about one.
        start: isFinite(start) ? start : 0
    };
}

// ---------------------------------------------------------- health history
// "<total>|<date>,<health>,<cycles> …" from bin/system-stats. Malformed rows
// are dropped rather than throwing: this string comes off a daily log that a
// person may have edited, and one bad line must not blank the whole section.
function parseHealthHistory(raw) {
    const text = String(raw || "");
    const bar = text.indexOf("|");
    if (bar < 0)
        return {
            total: 0,
            samples: []
        };
    const total = parseInt(text.substring(0, bar), 10);
    const body = text.substring(bar + 1).trim();
    const samples = [];
    if (body !== "") {
        const parts = body.split(" ");
        for (let i = 0; i < parts.length; i++) {
            const f = parts[i].split(",");
            if (f.length < 3)
                continue;
            const t = Date.parse(f[0] + "T00:00:00Z");
            const health = parseFloat(f[1]);
            const cycles = parseInt(f[2], 10);
            if (!isFinite(t) || !isFinite(health))
                continue;
            samples.push({
                date: f[0],
                time: t,
                health: health,
                cycles: isFinite(cycles) ? cycles : 0
            });
        }
    }
    return {
        total: isFinite(total) ? total : samples.length,
        samples: samples
    };
}

// "6 months" / "3 weeks" / "12 days" — the span a trend covers, in the
// coarsest unit that still says something true.
function formatSpan(days) {
    const d = Math.round(Number(days) || 0);
    if (d <= 0)
        return "";
    if (d < 14)
        return d + (d === 1 ? " day" : " days");
    if (d < 60) {
        const w = Math.round(d / 7);
        return w + (w === 1 ? " week" : " weeks");
    }
    if (d < 730) {
        const m = Math.round(d / 30.44);
        return m + (m === 1 ? " month" : " months");
    }
    const y = Math.round(d / 365.25 * 10) / 10;
    return y + (y === 1 ? " year" : " years");
}

// "−2.1% health over 6 months · +180 cycles", or the honest alternative while
// there is not yet enough log to say anything. TWO samples is the minimum for
// a delta, and a single day's pair is still noise — charge_full is a running
// gauge estimate that swings on its own — so the trend stays quiet until the
// log spans a week.
function healthTrend(history) {
    const h = history || {};
    const s = Array.isArray(h.samples) ? h.samples : [];
    if (s.length === 0)
        return {
            ready: false,
            text: "No history yet"
        };
    const first = s[0];
    const last = s[s.length - 1];
    const days = (last.time - first.time) / 86400000;
    if (s.length < 2 || days < 7)
        return {
            ready: false,
            text: "Tracking since " + first.date
        };

    const healthDelta = Math.round((last.health - first.health) * 10) / 10;
    const cycleDelta = last.cycles - first.cycles;
    // A minus sign, not a hyphen: this sits next to a percentage in a panel
    // that uses real typography everywhere else.
    const healthText = (healthDelta > 0 ? "+" : healthDelta < 0 ? "−" : "±") + Math.abs(healthDelta) + "% health";
    let text = healthText + " over " + formatSpan(days);
    if (cycleDelta > 0)
        text += " · +" + cycleDelta + " cycles";
    return {
        ready: true,
        text: text,
        days: days,
        healthDelta: healthDelta,
        cycleDelta: cycleDelta
    };
}

// Normalised 0..1 points for the sparkline, x plotted against REAL TIME so a
// month the machine was off reads as a flat gap rather than being compressed
// away. y is scaled to the observed range with a floor of one percentage
// point, because a pack that lost 0.3% over a year should draw as the flat
// line it is, not as a dramatic cliff filling the whole box.
function sparklinePoints(history) {
    const h = history || {};
    const s = Array.isArray(h.samples) ? h.samples : [];
    if (s.length < 2)
        return [];
    const t0 = s[0].time;
    const span = s[s.length - 1].time - t0;
    if (span <= 0)
        return [];

    let lo = s[0].health;
    let hi = s[0].health;
    for (let i = 1; i < s.length; i++) {
        if (s[i].health < lo)
            lo = s[i].health;
        if (s[i].health > hi)
            hi = s[i].health;
    }
    const mid = (lo + hi) / 2;
    if (hi - lo < 1) {
        lo = mid - 0.5;
        hi = mid + 0.5;
    }
    const range = hi - lo;

    const points = [];
    for (let i = 0; i < s.length; i++) {
        points.push({
            x: (s[i].time - t0) / span,
            // Inverted: QML's y grows downward, so a HIGHER health must sit
            // nearer the top of the box.
            y: 1 - (s[i].health - lo) / range
        });
    }
    return points;
}

if (typeof module !== "undefined") {
    module.exports = {
        chargeLimit: chargeLimit,
        parseHealthHistory: parseHealthHistory,
        formatSpan: formatSpan,
        healthTrend: healthTrend,
        sparklinePoints: sparklinePoints,
        parseKeyValue: parseKeyValue,
        formatDuration: formatDuration,
        formatWatts: formatWatts,
        formatCapacity: formatCapacity,
        chargeThresholdActive: chargeThresholdActive,
        batteryFraction: batteryFraction
    };
}
