import QtQuick
import Quickshell
import Quickshell.Io
import "AiModel.js" as Model

// Claude Code provider — port of omarchy's
// plugins/model-usage/providers/Claude.qml (CREDITS.md), publishing the same
// property contract their panel reads.
//
// Limits are Anthropic's own numbers from the OAuth usage endpoint, using the
// token in ~/.claude/.credentials.json. The request goes out over
// XMLHttpRequest as theirs does, which also keeps the bearer token off any
// process command line. Local usage comes from bin/claude-usage-scan.
//
// DELIBERATE difference from upstream: they poll every 15 minutes and retry
// transport failures on a timer. This shell does not poll — refresh() is
// called when the panel opens and from its refresh button.
Item {
    id: provider

    visible: false

    readonly property string providerId: "claude"
    readonly property string providerName: "Claude Code"
    readonly property url markSource: Qt.resolvedUrl("assets/claude.svg")

    property bool enabled: true
    property var settings: ({})

    property bool ready: false
    property bool refreshing: false

    // ------------------------------------------------------------- limits
    property real rateLimitPercent: -1
    property string rateLimitLabel: "Session (5-hour)"
    property string rateLimitResetAt: ""
    property real secondaryRateLimitPercent: -1
    property string secondaryRateLimitLabel: "Weekly (7-day)"
    property string secondaryRateLimitResetAt: ""

    property string usageStatusText: ""
    property string authHelpText: "Run `claude auth login` to restore authoritative usage."

    // ------------------------------------------------------------ local use
    property int todayPrompts: 0
    property int todaySessions: 0
    property real todayTotalTokens: 0
    property var todayTokensByModel: ({})
    property var recentDays: []
    property int totalPrompts: 0
    property int totalSessions: 0
    property int activeDays: 0
    property var modelUsage: ({})

    // ------------------------------------------------------- credentials
    property var credentials: ({
            accessToken: "",
            expiresAtMs: 0,
            subscriptionType: "",
            rateLimitTier: ""
        })

    // The plan is a label, not a limit: the percentages are Anthropic's own,
    // so a `plan` in the widget's inline shell.json entry only overrides what
    // the hero calls the subscription. Accepts pro / max5x / max20x / team.
    readonly property string planSetting: Model.formatPlanSetting(settings && settings.plan ? settings.plan : "")
    readonly property string tierLabel: planSetting || Model.formatTier(credentials.subscriptionType, credentials.rateLimitTier)

    readonly property bool tokenUsable: credentials.accessToken !== "" && (credentials.expiresAtMs <= 0 || credentials.expiresAtMs > Date.now())

    property bool probing: false
    property bool scanning: false

    function refresh(force) {
        if (!enabled)
            return;
        refreshing = true;
        refreshLimits();
        if (!scanProc.running) {
            scanning = true;
            scanProc.running = true;
        }
    }

    // The cheap half of a refresh: Anthropic's numbers without the disk walk.
    function refreshLimits() {
        if (!enabled || probing)
            return;
        credentialsFile.reload();
        if (!tokenUsable) {
            usageStatusText = credentials.accessToken === "" ? "Waiting for auth" : "Claude session expired";
            clearLimits();
            finishRefresh();
            return;
        }

        probing = true;
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", "Bearer " + credentials.accessToken);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            provider.probing = false;

            if (xhr.status >= 200 && xhr.status < 300) {
                const limits = Model.parseClaudeUsagePayload(xhr.responseText);
                if (limits) {
                    provider.rateLimitPercent = limits.rateLimitPercent;
                    provider.rateLimitLabel = limits.rateLimitLabel;
                    provider.rateLimitResetAt = limits.rateLimitResetAt;
                    provider.secondaryRateLimitPercent = limits.secondaryRateLimitPercent;
                    provider.secondaryRateLimitLabel = limits.secondaryRateLimitLabel;
                    provider.secondaryRateLimitResetAt = limits.secondaryRateLimitResetAt;
                    provider.usageStatusText = "";
                    provider.finishRefresh();
                    return;
                }
            }

            // Keep the last good windows on screen; only say what went wrong.
            // Status 0 is a transport failure — no route, no DNS, no server.
            provider.usageStatusText = "Claude limits unavailable";
            provider.authHelpText = xhr.status === 0 ? "Couldn't reach Anthropic's usage endpoint. Local Claude Code stats are still shown." : (xhr.status === 429 ? "Anthropic's usage endpoint is rate limiting checks right now. Local Claude Code stats are still shown." : "Anthropic's usage endpoint returned status " + xhr.status + ". Local Claude Code stats are still shown.");
            provider.finishRefresh();
        };
        xhr.send();
    }

    function clearLimits() {
        rateLimitPercent = -1;
        rateLimitResetAt = "";
        secondaryRateLimitPercent = -1;
        secondaryRateLimitResetAt = "";
    }

    function finishRefresh() {
        refreshing = probing || scanning;
    }

    FileView {
        id: credentialsFile
        path: Quickshell.env("HOME") + "/.claude/.credentials.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: provider.credentials = Model.parseCredentials(text())
        onLoadFailed: provider.credentials = Model.parseCredentials("")
        Component.onCompleted: reload()
    }

    Process {
        id: scanProc
        command: [Quickshell.env("HOME") + "/.dotfiles/bin/claude-usage-scan"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                provider.scanning = false;
                try {
                    const data = JSON.parse(text);
                    provider.todayPrompts = data.todayPrompts || 0;
                    provider.todaySessions = data.todaySessions || 0;
                    provider.todayTotalTokens = data.todayTotalTokens || 0;
                    provider.todayTokensByModel = data.todayTokensByModel || ({});
                    provider.recentDays = data.recentDays || [];
                    provider.totalPrompts = data.totalPrompts || 0;
                    provider.totalSessions = data.totalSessions || 0;
                    provider.activeDays = data.activeDays || 0;
                    provider.modelUsage = data.modelUsage || ({});
                    provider.ready = true;
                } catch (e) {
                    console.warn("model-usage/claude", "Failed to parse scanner output:", e);
                }
                provider.finishRefresh();
            }
        }
    }
}
