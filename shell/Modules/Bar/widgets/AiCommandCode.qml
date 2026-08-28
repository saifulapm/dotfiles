import QtQuick
import Quickshell
import Quickshell.Io
import "AiModel.js" as Model

// Command Code provider. NOT an omarchy port — follows the same property
// contract as the providers beside it (see AiCopilot.qml for the pattern).
//
// Everything comes from one bin/commandcode-usage-scan run, which reads pxy
// and nothing else: Command Code stores no sessions locally, so the local
// counters are pxy's per-model accounting for what it routed to the provider,
// and the meters are the GOAT plan's dollar windows from Command Code's
// billing endpoint. The two enforced windows (5-hour, weekly) fill the flat
// rateLimit pair; the monthly credit pool arrives as a finished extraLimits
// record. Like Codex there is no cheaper limits-only path.
//
// This shell does not poll: refresh() is called when the panel opens and from
// its refresh button.
Item {
    id: provider

    visible: false

    readonly property string providerId: "commandcode"
    readonly property string providerName: "Command"
    // No brand asset; the panel draws `markGlyph` instead (see AiCopilot).
    readonly property url markSource: ""
    readonly property string markGlyph: "󰘳" // md-apple_keyboard_command

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
    // The monthly credit pool the two windows draw from, already titled.
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

            provider.rateLimitPercent = data.rateLimitPercent === undefined || data.rateLimitPercent === null ? -1 : data.rateLimitPercent;
            provider.rateLimitLabel = data.rateLimitLabel || "";
            provider.rateLimitResetAt = data.rateLimitResetAt || "";
            provider.secondaryRateLimitPercent = data.secondaryRateLimitPercent === undefined || data.secondaryRateLimitPercent === null ? -1 : data.secondaryRateLimitPercent;
            provider.secondaryRateLimitLabel = data.secondaryRateLimitLabel || "";
            provider.secondaryRateLimitResetAt = data.secondaryRateLimitResetAt || "";

            provider.extraLimits = data.extraLimits || [];
            provider.tierLabel = data.tierLabel || "";
            provider.usageStatusText = data.usageStatusText || "";
            provider.authHelpText = data.authHelpText || "";
        } catch (e) {
            console.warn("model-usage/commandcode", "Failed to parse scanner output:", e);
            provider.usageStatusText = "Command Code scan failed";
            provider.authHelpText = String(e);
            provider.ready = true;
        }
    }

    Process {
        id: usageScanner
        command: [Quickshell.env("HOME") + "/.dotfiles/bin/commandcode-usage-scan"]
        running: false

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: provider.parseScannerOutput(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (String(text || "").trim() !== "")
                console.warn("model-usage/commandcode", String(text).trim())
        }

        onExited: {
            provider.refreshing = false;
            provider.lastRefreshedAtMs = Date.now();
        }
    }
}
