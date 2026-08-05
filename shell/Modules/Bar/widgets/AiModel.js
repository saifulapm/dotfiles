// Model-usage parsing and formatting — port of the limit and presentation
// layer of omarchy's plugins/model-usage/ (`Main.qml`, `Panel.qml`,
// `providers/Claude.qml`, CREDITS.md), lifted out of QML into one file that
// both providers and the panel share.
//
// Providers publish the same six rate-limit properties omarchy's do
// (rateLimitPercent/Label/ResetAt plus the secondary trio) and the panel
// normalizes them into window records here, because the two providers word
// their windows differently: Claude spells them out ("Session (5-hour)"),
// Codex abbreviates ("5h window", "30m window", "Monthly (30-day)").

// ------------------------------------------------------------ scale parsing
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

// ------------------------------------------------------------ Claude probe
function usageBucket(payload, key) {
    const bucket = payload ? payload[key] : null;
    if (bucket && typeof bucket === "object")
        return bucket;
    return null;
}

// Their bucket preference: the OAuth-apps weekly bucket when present, the
// plain seven-day one otherwise. Returns the provider-property shape so the
// Claude provider can assign it straight across.
function parseClaudeUsagePayload(raw) {
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

    return {
        rateLimitPercent: sessionPercent,
        rateLimitLabel: "Session (5-hour)",
        rateLimitResetAt: sessionPercent >= 0 ? normalizeResetAt(session ? session.resets_at : "") : "",
        secondaryRateLimitPercent: weeklyPercent,
        secondaryRateLimitLabel: "Weekly (7-day)",
        secondaryRateLimitResetAt: weeklyPercent >= 0 ? normalizeResetAt(weekly ? weekly.resets_at : "") : ""
    };
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

// ------------------------------------------------------------- limit windows
// Claude spells its windows out, Codex abbreviates them; both have to land on
// the same record.
function windowIsLong(text) {
    return text.indexOf("week") >= 0 || text.indexOf("7-day") >= 0 || text.indexOf("seven") >= 0 || text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0;
}

function windowSpanMs(label) {
    const text = String(label || "").toLowerCase();
    if (text.indexOf("month") >= 0 || text.indexOf("30-day") >= 0)
        return 30 * 24 * 3600 * 1000;
    if (windowIsLong(text))
        return 7 * 24 * 3600 * 1000;
    const hours = text.match(/(\d+)\s*-?\s*h(?:our)?\b/);
    if (hours)
        return Number(hours[1]) * 3600 * 1000;
    const minutes = text.match(/(\d+)\s*-?\s*m(?:in(?:ute)?s?)?\b/);
    if (minutes)
        return Number(minutes[1]) * 60 * 1000;
    return 0;
}

function windowTitle(label) {
    const text = String(label || "").toLowerCase();
    if (text.indexOf("month") >= 0)
        return "Monthly";
    if (windowIsLong(text))
        return "Weekly";
    if (text.indexOf("session") >= 0 || windowSpanMs(label) > 0)
        return "Session";
    const plain = String(label || "").replace(/\s*\(.*\)\s*/, "").trim();
    return plain === "" ? "Limit" : plain;
}

// The parenthetical or the abbreviation itself, shown beside the title:
// "5-hour", "7-day", "30-day", "30m window".
function windowSubtitle(label) {
    const raw = String(label || "");
    const paren = raw.match(/\(([^)]+)\)/);
    if (paren)
        return paren[1];
    const plain = raw.replace(/\s*window\s*$/i, "").trim();
    return plain === windowTitle(label) ? "" : plain;
}

function limitWindow(label, percent, resetAt) {
    return {
        title: windowTitle(label),
        subtitle: windowSubtitle(label),
        percent: Number(percent),
        resetAt: String(resetAt || "")
    };
}

function limitWindows(p) {
    if (!p)
        return [];
    const out = [];
    if (p.rateLimitPercent >= 0)
        out.push(limitWindow(p.rateLimitLabel, p.rateLimitPercent, p.rateLimitResetAt));
    if (p.secondaryRateLimitPercent >= 0)
        out.push(limitWindow(p.secondaryRateLimitLabel, p.secondaryRateLimitPercent, p.secondaryRateLimitResetAt));
    return out;
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

// ------------------------------------------------------------------ providers
// A subscription earns a place in the bar and the panel by having actually
// produced numbers. Presence on disk is not enough: a box that installed a CLI
// and never ran it would get a tab full of zeroes.
function providerHasData(p) {
    if (!p)
        return false;
    return Number(p.totalPrompts || 0) > 0 || Number(p.totalSessions || 0) > 0 || Number(p.activeDays || 0) > 0 || Number(p.rateLimitPercent) >= 0 || Number(p.secondaryRateLimitPercent) >= 0;
}

// The plan you pay for, under the name of the tool it pays for.
function heroMeta(p) {
    if (!p)
        return "";
    if (String(p.usageStatusText || "") !== "")
        return p.usageStatusText;
    const tier = String(p.tierLabel || "");
    if (tier === "")
        return "Subscription";
    return tier.charAt(0).toUpperCase() + tier.slice(1);
}

// Claude's tier rules, taken from the credentials file: a rateLimitTier like
// `default_claude_max_20x` becomes "Max 20x", otherwise the subscriptionType
// is title-cased.
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

// ----------------------------------------------------------------- formatting
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
// (`claude-opus-4-8`, `gpt-5.6-sol`). Rejoin the numeric run into one version
// and title-case the words around it.
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

function modelTotal(bucket) {
    const b = bucket || {};
    return Number(b.inputTokens || 0) + Number(b.outputTokens || 0) + Number(b.cacheReadInputTokens || 0) + Number(b.cacheCreationInputTokens || 0);
}

// Top four models by total tokens, each scaled to the heaviest — the same
// scale-to-peak the day chart uses for its busiest day.
function modelRows(p) {
    const usageByModel = p ? (p.modelUsage || {}) : {};
    const rows = [];
    for (const id in usageByModel) {
        rows.push({
            name: friendlyModelName(id),
            total: modelTotal(usageByModel[id])
        });
    }
    rows.sort((a, b) => b.total - a.total);
    const top = rows.slice(0, 4);
    const peak = Math.max(1, top.length > 0 ? top[0].total : 1);
    for (let i = 0; i < top.length; i++)
        top[i].share = top[i].total / peak;
    return top;
}

function weekPeak(p) {
    const days = p ? (p.recentDays || []) : [];
    let peak = 0;
    for (let i = 0; i < days.length; i++)
        peak = Math.max(peak, Number(days[i].messageCount || 0));
    return peak;
}

function dayName(date) {
    const parsed = new Date(String(date || "") + "T00:00:00");
    if (isNaN(parsed.getTime()))
        return String(date || "");
    return ["Sun", "Mon", "Tue", "Wed", "Thu", "Fri", "Sat"][parsed.getDay()];
}
