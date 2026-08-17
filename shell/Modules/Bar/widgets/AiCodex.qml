import QtQuick
import Quickshell
import Quickshell.Io
import "AiModel.js" as Model

// Codex provider — port of omarchy's
// plugins/model-usage/providers/Codex.qml, publishing the same
// property contract as the Claude provider beside it.
//
// Everything comes from one bin/codex-usage-scan run: it walks the local
// session transcripts AND asks `codex app-server` for the rate-limit windows
// over JSON-RPC, so unlike Claude there is no cheaper limits-only path —
// refreshLimits() is refresh(), exactly as upstream.
//
// DELIBERATE difference from upstream: they run that scan every 5 minutes.
// This shell does not poll — refresh() is called when the panel opens and
// from its refresh button.
Item {
    id: provider

    visible: false

    readonly property string providerId: "codex"
    readonly property string providerName: "Codex"
    readonly property url markSource: Qt.resolvedUrl(provider.darkSurface ? "assets/codex.svg" : "assets/codex-light.svg")

    // Codex ships as a white mark; swap to the dark one when the surface
    // behind it is light. (The Claude mark is brand-orange and works on both.)
    property bool darkSurface: true

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

    property string tierLabel: ""
    property string usageStatusText: ""
    property string authHelpText: "Run `codex login` to authenticate."

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

    // Bumped whenever a scan lands; the widget publishes a new sync snapshot
    // off this (omarchy's Main.qml watches the same property).
    property double lastRefreshedAtMs: 0

    function refresh(force) {
        if (!enabled || usageScanner.running)
            return;
        refreshing = true;
        usageScanner.running = true;
    }

    // Codex reports limits and local stats from the same scanner run, and that
    // run has no expensive mode to skip, so there is nothing cheaper to do.
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

            provider.tierLabel = data.tierLabel || "";
            provider.usageStatusText = data.usageStatusText || "";
            provider.authHelpText = data.authHelpText || "Run `codex login` to authenticate.";
        } catch (e) {
            console.warn("model-usage/codex", "Failed to parse scanner output:", e);
            provider.usageStatusText = "Codex scan failed";
            provider.authHelpText = String(e);
            provider.ready = true;
        }
    }

    Process {
        id: usageScanner
        command: [Quickshell.env("HOME") + "/.dotfiles/bin/codex-usage-scan"]
        running: false

        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: provider.parseScannerOutput(text)
        }

        stderr: StdioCollector {
            waitForEnd: true
            onStreamFinished: if (String(text || "").trim() !== "")
                console.warn("model-usage/codex", String(text).trim())
        }

        onExited: {
            provider.refreshing = false;
            provider.lastRefreshedAtMs = Date.now();
        }
    }
}
