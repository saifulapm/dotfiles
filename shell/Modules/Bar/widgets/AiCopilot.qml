import QtQuick
import Quickshell
import Quickshell.Io
import "AiModel.js" as Model

// GitHub Copilot provider. NOT an omarchy port — their model-usage plugin
// ships Claude and Codex only; this follows the same property contract so it
// drops into the panel beside them.
//
// Everything comes from one bin/copilot-usage-scan run: the monthly quota
// from GitHub's copilot_internal user endpoint (authenticated with the token
// the CLI stores in ~/.copilot/config.json) and the local token counts from
// the CLI's own SQLite session store. Like Codex there is no cheaper
// limits-only path, so refreshLimits() is refresh().
//
// This shell does not poll: refresh() is called when the panel opens and from
// its refresh button.
Item {
    id: provider

    visible: false

    readonly property string providerId: "copilot"
    readonly property string providerName: "GitHub Copilot"
    // No brand asset ships with omarchy for Copilot, so the hero falls back to
    // a glyph: the panel draws `markGlyph` whenever a provider has one instead
    // of a mark. Material Design's goggles stand in for Copilot's — the
    // Codicon range has a real cod-copilot glyph, but that range does not
    // render under our Nerd Font fallback (nor does FontAwesome's).
    readonly property url markSource: ""
    readonly property string markGlyph: "󰴰" // md-safety_goggles

    property bool enabled: true
    property var settings: ({})

    property bool ready: false
    property bool refreshing: false
    // False when the scanner could not read the session-store DB — the local
    // counters are then absent, not genuinely zero, and the panel must not
    // present them as real numbers.
    property bool hasLocalStats: true

    // ------------------------------------------------------------- limits
    property real rateLimitPercent: -1
    property string rateLimitLabel: ""
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: -1
    property string secondaryRateLimitLabel: ""
    property string secondaryRateLimitResetAt: ""

    property string tierLabel: ""
    property string usageStatusText: ""
    property string authHelpText: "Run `copilot login` to authenticate."

    // ------------------------------------------------------------ local use
    property int todayPrompts: 0
    property int todaySessions: 0
    property real todayTotalTokens: 0
    property var todayTokensByModel: ({})
    property var recentDays: []
    property int totalPrompts: 0
    property int totalSessions: 0
    property int activeDays: 0
    property var activeDates: []
    property var modelUsage: ({})

    property double lastRefreshedAtMs: 0

    function refresh(force) {
        if (!enabled || usageScanner.running)
            return;
        refreshing = true;
        usageScanner.running = true;
    }

    function refreshLimits() {
        refresh();
    }

    function parseScannerOutput(output) {
        const raw = String(output || "").trim();
        if (raw === "")
            return;

        try {
            const data = JSON.parse(raw.split("\n").pop());
            provider.ready = !!data.ready;
            provider.hasLocalStats = data.hasLocalStats !== false;
            if (!provider.hasLocalStats && !data.usageStatusText)
                provider.usageStatusText = "Local usage unavailable (session store unreadable)";

            provider.todayPrompts = data.todayPrompts || 0;
            provider.todaySessions = data.todaySessions || 0;
            provider.todayTotalTokens = data.todayTotalTokens || 0;
            provider.todayTokensByModel = data.todayTokensByModel || ({});
            provider.recentDays = data.recentDays || [];
            provider.totalPrompts = data.totalPrompts || 0;
            provider.totalSessions = data.totalSessions || 0;
            provider.activeDays = data.activeDays || 0;
            provider.activeDates = data.activeDates || [];
            provider.modelUsage = data.modelUsage || ({});

            provider.rateLimitPercent = data.rateLimitPercent === undefined || data.rateLimitPercent === null ? -1 : data.rateLimitPercent;
            provider.rateLimitLabel = data.rateLimitLabel || "";
            provider.rateLimitResetAt = data.rateLimitResetAt || "";
            provider.secondaryRateLimitPercent = data.secondaryRateLimitPercent === undefined || data.secondaryRateLimitPercent === null ? -1 : data.secondaryRateLimitPercent;
            provider.secondaryRateLimitLabel = data.secondaryRateLimitLabel || "";
            provider.secondaryRateLimitResetAt = data.secondaryRateLimitResetAt || "";

            provider.tierLabel = data.tierLabel || "";
            provider.usageStatusText = data.usageStatusText || "";
            provider.authHelpText = data.authHelpText || "Run `copilot login` to authenticate.";
        } catch (e) {
            console.warn("model-usage/copilot", "Failed to parse scanner output:", e);
            provider.usageStatusText = "Copilot scan failed";
            provider.authHelpText = String(e);
            provider.ready = true;
        }
    }

    Process {
        id: usageScanner
        command: [Quickshell.env("HOME") + "/.dotfiles/bin/copilot-usage-scan"]
        running: false

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: provider.parseScannerOutput(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (String(text || "").trim() !== "")
                console.warn("model-usage/copilot", String(text).trim())
        }

        onExited: {
            provider.refreshing = false;
            provider.lastRefreshedAtMs = Date.now();
        }
    }
}
