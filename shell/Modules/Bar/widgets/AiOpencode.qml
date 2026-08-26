import QtQuick
import Quickshell
import Quickshell.Io
import "AiModel.js" as Model

// OpenCode provider. NOT an omarchy port — follows the same property contract
// as the providers beside it (see AiCopilot.qml for the pattern).
//
// Everything comes from one bin/opencode-usage-scan run: local usage from
// OpenCode's own session store PLUS pxy's per-model accounting (pxy is what
// resolves the "auto" model, so only it knows which model actually answered),
// and the two opencode Go accounts' dollar-window percentages from
// `pxy status --remote`. Those arrive as finished extraLimits records — six
// meters (GitHub/Google × 5-hour/7-day/30-day) — so the flat rateLimit pair
// stays unused here. Like Codex there is no cheaper limits-only path.
//
// This shell does not poll: refresh() is called when the panel opens and from
// its refresh button.
Item {
    id: provider

    visible: false

    readonly property string providerId: "opencode"
    readonly property string providerName: "OpenCode"
    // No brand asset; the panel draws `markGlyph` instead (see AiCopilot).
    readonly property url markSource: ""
    readonly property string markGlyph: "󰆍" // md-console

    property bool enabled: true
    property var settings: ({})

    property bool ready: false
    property bool refreshing: false

    // ------------------------------------------------------------- limits
    property real rateLimitPercent: -1
    property string rateLimitLabel: ""
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: -1
    property string secondaryRateLimitLabel: ""
    property string secondaryRateLimitResetAt: ""
    // Per-account windows from the Go usage endpoint, already titled.
    property var extraLimits: []

    property string tierLabel: ""
    property string usageStatusText: ""
    property string authHelpText: ""

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

            provider.extraLimits = data.extraLimits || [];
            provider.tierLabel = data.tierLabel || "";
            provider.usageStatusText = data.usageStatusText || "";
            provider.authHelpText = data.authHelpText || "";
        } catch (e) {
            console.warn("model-usage/opencode", "Failed to parse scanner output:", e);
            provider.usageStatusText = "OpenCode scan failed";
            provider.authHelpText = String(e);
            provider.ready = true;
        }
    }

    Process {
        id: usageScanner
        command: [Quickshell.env("HOME") + "/.dotfiles/bin/opencode-usage-scan"]
        running: false

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: provider.parseScannerOutput(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (String(text || "").trim() !== "")
                console.warn("model-usage/opencode", String(text).trim())
        }

        onExited: {
            provider.refreshing = false;
            provider.lastRefreshedAtMs = Date.now();
        }
    }
}
