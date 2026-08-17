// The rclone-remote status envelope — ours, in the shape of the Dropbox
// plugin's model: a tolerant parse of bin/rclone-remote-status's
// one JSON object, where a parse failure stays distinguishable from an honest
// empty answer.
//
// The three size formatters below came from that model file (omarchy's, via
// our DropboxModel.js) and moved here when the daemon-backed Dropbox widget
// was removed (2026-08-10) — the panel's storage row was the only thing still
// reading them.

function parseStatus(raw) {
    var text = String(raw || "").trim();
    if (text === "")
        return defaultStatus();
    try {
        var parsed = JSON.parse(text);
        if (!parsed || typeof parsed !== "object")
            return defaultStatus();
        return parsed;
    } catch (e) {
        var failed = defaultStatus();
        failed.ok = false;
        failed.lastError = "Failed to parse rclone remote status";
        return failed;
    }
}

function defaultStatus() {
    return {
        ok: true,
        installed: false,
        configured: false,
        remote: "",
        remoteType: "",
        mounted: false,
        mountPoint: "",
        mountUnit: "",
        local: true,
        error: ""
    };
}

// Decimal units, as every cloud provider quotes quota (1000, not 1024), and
// the trailing-zero trim that keeps "2.5 GB" from reading "2.50 GB".
function formatBytes(bytes) {
    var value = Number(bytes || 0);
    if (!isFinite(value) || value <= 0)
        return "0 B";
    var units = ["B", "KB", "MB", "GB", "TB"];
    var index = 0;
    while (value >= 1000 && index < units.length - 1) {
        value = value / 1000;
        index++;
    }
    var decimals = value >= 100 || index === 0 ? 0 : (value >= 10 ? 1 : 2);
    return value.toFixed(decimals).replace(/\.0+$/, "").replace(/(\.\d)0$/, "$1") + " " + units[index];
}

function formatPercent(value) {
    var number = Number(value || 0);
    if (!isFinite(number) || number <= 0)
        return "0%";
    if (number >= 10)
        return Math.round(number) + "%";
    return number.toFixed(1).replace(/\.0$/, "") + "%";
}

function usageText(usedBytes, quotaBytes, quotaKnown) {
    if (quotaKnown && Number(quotaBytes || 0) > 0) {
        return formatBytes(usedBytes) + " of " + formatBytes(quotaBytes);
    }
    return formatBytes(usedBytes);
}

if (typeof module !== "undefined") {
    module.exports = {
        parseStatus: parseStatus,
        defaultStatus: defaultStatus,
        formatBytes: formatBytes,
        formatPercent: formatPercent,
        usageText: usageText
    };
}
