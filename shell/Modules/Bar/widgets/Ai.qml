import QtQuick
import Quickshell
import Quickshell.Io
import "../components"
import "AiModel.js" as Model

// Claude Code usage — omarchy's model-usage plugin. The widget owns the state
// so the bar glyph can carry the alarm: when the window closest to its limit
// is at 90% or more the glyph turns the attention colour, which is their
// `alarming`.
//
// Rate limits are Anthropic's own numbers, read from the OAuth usage endpoint
// with the token in ~/.claude/.credentials.json (the same request their
// provider makes, over XMLHttpRequest so the bearer token never appears in a
// process command line). Local usage is bin/claude-usage-scan.
//
// DELIBERATE difference from upstream: they poll every 15 minutes in the
// background. This shell does not poll — everything refreshes when the panel
// is opened, plus the manual refresh button in it. The consequence is that
// the bar alarm reflects the last reading rather than the live one.
BarIcon {
    id: rootItem

    glyph: "󰚩" // md-robot

    // ---------------------------------------------------------- credentials
    property var credentials: ({
            accessToken: "",
            expiresAtMs: 0,
            subscriptionType: "",
            rateLimitTier: ""
        })

    // The plan is a label, not a limit: the percentages below are Anthropic's
    // own, so a `plan` in the widget's inline shell.json entry only overrides
    // what the hero calls the subscription (useful when the credentials file
    // carries no tier). Accepts pro / max5x / max20x / team.
    readonly property string planSetting: Model.formatPlanSetting(setting("plan", ""))
    readonly property string tierLabel: planSetting || Model.formatTier(credentials.subscriptionType, credentials.rateLimitTier)

    readonly property bool tokenUsable: credentials.accessToken !== "" && (credentials.expiresAtMs <= 0 || credentials.expiresAtMs > Date.now())

    // ---------------------------------------------------------- limit state
    property var limitWindows: []
    property bool probing: false
    property string limitStatus: ""
    property double lastProbeAtMs: 0

    readonly property var headline: Model.bindingWindow(limitWindows)
    readonly property bool alarming: !!headline && headline.percent >= 0.9

    // ----------------------------------------------------------- local stats
    property var stats: null
    property bool scanning: false

    active: alarming
    tooltipText: {
        if (!headline)
            return "Claude usage";
        return "Claude · " + headline.title.toLowerCase() + " " + Math.round(headline.percent * 100) + "%";
    }

    function refresh() {
        probeLimits();
        if (!scanProc.running) {
            scanning = true;
            scanProc.running = true;
        }
    }

    function probeLimits() {
        if (probing)
            return;
        credentialsFile.reload();
        if (!tokenUsable) {
            limitStatus = credentials.accessToken === "" ? "Waiting for auth" : "Claude session expired";
            limitWindows = [];
            return;
        }

        probing = true;
        lastProbeAtMs = Date.now();
        const xhr = new XMLHttpRequest();
        xhr.open("GET", "https://api.anthropic.com/api/oauth/usage");
        xhr.setRequestHeader("Authorization", "Bearer " + credentials.accessToken);
        xhr.setRequestHeader("anthropic-beta", "oauth-2025-04-20");
        xhr.setRequestHeader("Accept", "application/json");
        xhr.onreadystatechange = function () {
            if (xhr.readyState !== XMLHttpRequest.DONE)
                return;
            rootItem.probing = false;

            if (xhr.status >= 200 && xhr.status < 300) {
                const windows = Model.parseUsagePayload(xhr.responseText);
                if (windows) {
                    rootItem.limitWindows = windows;
                    rootItem.limitStatus = "";
                    return;
                }
            }

            // Keep the last good windows on screen; only say what went wrong.
            // Status 0 is a transport failure — no route, no DNS, no server.
            rootItem.limitStatus = xhr.status === 0 ? "Couldn't reach Anthropic's usage endpoint." : (xhr.status === 429 ? "Anthropic is rate limiting usage checks right now." : "Anthropic's usage endpoint returned status " + xhr.status + ".");
        };
        xhr.send();
    }

    FileView {
        id: credentialsFile
        path: Quickshell.env("HOME") + "/.claude/.credentials.json"
        watchChanges: true
        printErrors: false
        onFileChanged: reload()
        onLoaded: rootItem.credentials = Model.parseCredentials(text())
        onLoadFailed: rootItem.credentials = Model.parseCredentials("")
        Component.onCompleted: reload()
    }

    Process {
        id: scanProc
        command: [Quickshell.env("HOME") + "/.dotfiles/bin/claude-usage-scan"]
        stdout: StdioCollector {
            waitForEnd: true
            onStreamFinished: {
                rootItem.scanning = false;
                try {
                    rootItem.stats = JSON.parse(text);
                } catch (e) {
                    console.warn("Ai: usage scanner parse failed:", e);
                }
            }
        }
    }

    function openPanel() {
        panelLoader.active = true;
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
        if (panelLoader.item.opened)
            refresh();
    }

    onTapped: button => {
        if (button === Qt.MiddleButton)
            refresh();
        else
            openPanel();
    }

    LazyLoader {
        id: panelLoader
        active: false
        component: AiPanel {
            theme: rootItem.theme
            usage: rootItem
        }
    }
}
