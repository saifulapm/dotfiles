// Model-usage parsing and formatting — port of the limit half of omarchy's
// plugins/model-usage/ (`providers/Claude.qml` and `Panel.qml`, CREDITS.md).
// Their Codex provider, their multi-device sync layer and their local
// stats-cache reader are not here; ours reads the same OAuth usage endpoint
// and the same credentials file, and the local numbers come from
// bin/claude-usage-scan.

// Anthropic's OAuth usage endpoint currently reports percentages (37.0, 1.0);
// older clients used fractions (0.37). A payload carrying any value >= 1 is
// percent-scaled, so 1.0 renders as 1%, not 100%.
function parseNumber(value) {
    if (value === null || value === undefined)
        return NaN;
    return parseFloat(String(value).trim().replace("%", ""));
}

function utilizationPayloadUsesPercentScale(values) {
    for (let i = 0; i < values.length; i++) {
        if (parseNumber(values[i]) >= 1)
            return true;
    }
    return false;
}

function normalizeUtilization(value, percentScale) {
    const n = parseNumber(value);
    if (!(n >= 0))
        return -1;
    if (percentScale === true || n > 1)
        return Math.min(1, n / 100);
    return Math.min(1, n);
}

function normalizeResetAt(value) {
    if (value === null || value === undefined)
        return "";
    const raw = String(value).trim();
    if (raw === "")
        return "";
    if (/^\d+$/.test(raw)) {
        let ts = parseInt(raw, 10);
        if (ts < 1e12)
            ts = ts * 1000;
        const d = new Date(ts);
        if (!isNaN(d.getTime()))
            return d.toISOString();
    }
    const parsed = new Date(raw);
    if (!isNaN(parsed.getTime()))
        return parsed.toISOString();
    return raw;
}

function usageBucket(payload, key) {
    const bucket = payload ? payload[key] : null;
    if (bucket && typeof bucket === "object")
        return bucket;
    return null;
}

// The two windows the endpoint reports, normalized into one record shape.
// Their bucket preference: the OAuth-apps weekly bucket when present, the
// plain seven-day one otherwise.
function parseUsagePayload(raw) {
    let payload = null;
    try {
        payload = JSON.parse(String(raw || "{}"));
    } catch (e) {
        return null;
    }

    const weekly = usageBucket(payload, "seven_day_oauth_apps") || usageBucket(payload, "seven_day");
    const session = usageBucket(payload, "five_hour");
    const percentScale = utilizationPayloadUsesPercentScale([weekly ? weekly.utilization : null, session ? session.utilization : null]);
    const sessionPercent = normalizeUtilization(session ? session.utilization : null, percentScale);
    const weeklyPercent = normalizeUtilization(weekly ? weekly.utilization : null, percentScale);
    if (sessionPercent < 0 && weeklyPercent < 0)
        return null;

    const windows = [];
    if (sessionPercent >= 0)
        windows.push({
            title: "Session",
            subtitle: "5-hour",
            percent: sessionPercent,
            resetAt: normalizeResetAt(session ? session.resets_at : "")
        });
    if (weeklyPercent >= 0)
        windows.push({
            title: "Weekly",
            subtitle: "7-day",
            percent: weeklyPercent,
            resetAt: normalizeResetAt(weekly ? weekly.resets_at : "")
        });
    return windows;
}

// The window that decides how much room is left — the fullest one, since that
// is what stops the next prompt.
function bindingWindow(windows) {
    const list = Array.isArray(windows) ? windows : [];
    let best = null;
    for (let i = 0; i < list.length; i++) {
        if (!best || list[i].percent > best.percent)
            best = list[i];
    }
    return best;
}

function resetMsFor(window, nowMs) {
    if (!window || !window.resetAt)
        return -1;
    const ms = new Date(window.resetAt).getTime();
    return isFinite(ms) ? ms - nowMs : -1;
}

function formatDuration(ms) {
    if (!(ms > 0))
        return "now";
    const minutes = Math.floor(ms / 60000);
    const hours = Math.floor(minutes / 60);
    const days = Math.floor(hours / 24);
    if (days > 0)
        return days + "d " + (hours % 24) + "h";
    if (hours > 0)
        return hours + "h " + (minutes % 60) + "m";
    return Math.max(1, minutes) + "m";
}

// Their plan-label rules, taken from the credentials file: a rateLimitTier
// like `default_claude_max_20x` becomes "Max 20x", otherwise the
// subscriptionType is title-cased.
function formatTier(subscriptionType, rateLimitTier) {
    if (!rateLimitTier)
        return subscriptionType || "";
    const match = String(rateLimitTier).match(/max_(\d+x)/i);
    if (match)
        return "Max " + match[1];
    if (subscriptionType)
        return String(subscriptionType).charAt(0).toUpperCase() + String(subscriptionType).slice(1);
    return "";
}

// The `plan` widget setting, as written in shell.json, rendered as a label.
// Accepts what a person would type: pro, max5x, max-5x, max_20x, team.
function formatPlanSetting(value) {
    const raw = String(value || "").trim();
    if (raw === "")
        return "";
    const match = raw.match(/^max[\s_-]*(\d+)x?$/i);
    if (match)
        return "Max " + match[1] + "x";
    return raw.charAt(0).toUpperCase() + raw.slice(1);
}

function parseCredentials(raw) {
    const empty = {
        accessToken: "",
        expiresAtMs: 0,
        subscriptionType: "",
        rateLimitTier: ""
    };
    try {
        const data = JSON.parse(String(raw || "{}"));
        const oauth = data.claudeAiOauth || {};
        const expires = Number(oauth.expiresAt || 0);
        return {
            accessToken: String(oauth.accessToken || ""),
            expiresAtMs: isFinite(expires) && expires > 0 ? expires : 0,
            subscriptionType: String(oauth.subscriptionType || ""),
            rateLimitTier: String(oauth.rateLimitTier || "")
        };
    } catch (e) {
        return empty;
    }
}

function formatTokenCount(n) {
    if (n === undefined || n === null)
        return "0";
    if (n >= 1e9)
        return (n / 1e9).toFixed(1) + "B";
    if (n >= 1e6)
        return (n / 1e6).toFixed(1) + "M";
    if (n >= 1e3)
        return (n / 1e3).toFixed(1) + "K";
    return String(n);
}

function modelWordCase(word) {
    if (word === "gpt")
        return "GPT";
    return word.charAt(0).toUpperCase() + word.slice(1);
}

// Model ids arrive hyphenated with the version split across segments
// (`claude-opus-4-8`). Rejoin the numeric run into one version and title-case
// the words around it.
function friendlyModelName(id) {
    if (!id)
        return "Unknown";
    const name = String(id).replace(/^claude-/, "").replace(/-\d{8}$/, "");
    const parts = name.split("-");
    const words = [];
    let version = [];
    for (let i = 0; i < parts.length; i++) {
        const part = parts[i];
        if (part === "")
            continue;
        if (/^\d/.test(part)) {
            version.push(part);
            continue;
        }
        if (version.length > 0) {
            words.push(version.join("."));
            version = [];
        }
        words.push(modelWordCase(part));
    }
    if (version.length > 0)
        words.push(version.join("."));
    return words.length > 0 ? words.join(" ") : "Unknown";
}

function dayName(date) {
    const parsed = new Date(String(date || "") + "T00:00:00");
    if (isNaN(parsed.getTime()))
        return String(date || "");
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()];
}
