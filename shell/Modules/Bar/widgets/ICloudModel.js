// The iCloud status envelope — ours, in DropboxModel.js's shape: a tolerant
// parse of bin/icloud-status's one JSON object, where a parse failure stays
// distinguishable from an honest empty answer.

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
        failed.lastError = "Failed to parse iCloud status";
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
        mountUnit: "qshell-icloud-mount",
        local: true,
        error: ""
    };
}

if (typeof module !== "undefined") {
    module.exports = {
        parseStatus: parseStatus,
        defaultStatus: defaultStatus
    };
}
