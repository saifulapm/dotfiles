import QtQuick
import Quickshell
import "../components"
import "AiModel.js" as Model

// Model usage — omarchy's model-usage plugin. This is their Main.qml's job:
// hold every provider, and let through only the ones that are switched on AND
// have actually produced numbers. A CLI that was installed and never run gets
// no tab full of zeroes, and a machine that has run none shows no widget.
//
// Claude and Codex are their two providers; GitHub Copilot is ours, following
// the same contract (see AiCopilot.qml).
//
// The bar glyph carries the alarm: when the selected provider's fullest
// window — the one that stops the next prompt — is at 90% or more, the glyph
// turns the attention colour. That is their `alarming`.
//
// Left click opens the panel, right click refreshes, middle click steps to
// the next provider, exactly as their bar button does.
BarIcon {
    id: rootItem

    glyph: "󱚣" // md-robot_excited, their model-usage glyph

    // Any provider can be switched off through the widget's inline shell.json
    // entry: {"id": "ai", "providers": {"copilot": {"enabled": false}}}
    function providerEnabled(id) {
        const providers = setting("providers", null);
        if (!providers || !providers[id])
            return true;
        return providers[id].enabled !== false;
    }

    readonly property var allProviders: [claudeProvider, codexProvider, copilotProvider]

    // ------------------------------------------------------------- syncing
    // The Sync service owns transport and device identity; the merge rules
    // are model-usage's, in AiModel.js. With sync off there are no snapshots
    // and every provider falls back to its own numbers.
    readonly property var sync: bar && bar.shell ? bar.shell.sync : null
    readonly property var aggregate: Model.aggregateSnapshots(sync ? sync.snapshotsFor("providers") : [])

    // This machine's contribution. Recomputed whenever any provider's counts
    // change; the service debounces the write.
    readonly property var localPayload: Model.localProvidersPayload(allProviders)
    onLocalPayloadChanged: if (sync)
        sync.publish("providers", localPayload)

    // Each provider as the panel should see it: merged counts where sync has
    // them, account-level facts always local.
    readonly property var providers: allProviders.filter(p => p.enabled).map(p => Model.displayProvider(p, aggregate)).filter(Model.providerHasData)

    // The selection follows the provider, not the slot it happens to sit in:
    // a provider whose first scan lands while the panel is open would
    // otherwise shift the list underneath you.
    property string selectedProviderId: ""
    readonly property int providerIndex: {
        for (let i = 0; i < providers.length; i++) {
            if (providers[i].providerId === selectedProviderId)
                return i;
        }
        return 0;
    }
    readonly property var provider: providers.length > 0 ? providers[providerIndex] : null

    readonly property var limits: Model.limitWindows(provider)
    readonly property var headline: Model.bindingWindow(limits)
    readonly property bool alarming: !!headline && headline.percent >= 0.9
    readonly property bool refreshing: allProviders.some(p => p.refreshing)

    function selectProvider(index) {
        if (providers.length === 0)
            return;
        const wrapped = ((index % providers.length) + providers.length) % providers.length;
        selectedProviderId = providers[wrapped].providerId;
    }

    function refresh() {
        for (let i = 0; i < allProviders.length; i++) {
            if (allProviders[i].enabled)
                allProviders[i].refresh(true);
        }
    }

    // Nothing to report, nothing in the bar.
    visible: providers.length > 0
    active: alarming
    tooltipText: {
        if (!provider)
            return "Model usage";
        if (!headline)
            return provider.providerName;
        return provider.providerName + " · " + headline.title.toLowerCase() + " " + Math.round(headline.percent * 100) + "%";
    }

    AiClaude {
        id: claudeProvider
        enabled: rootItem.providerEnabled("claude")
        settings: rootItem.settings
    }

    AiCodex {
        id: codexProvider
        enabled: rootItem.providerEnabled("codex")
        settings: rootItem.settings
        darkSurface: rootItem.theme.mode !== "light"
    }

    AiCopilot {
        id: copilotProvider
        enabled: rootItem.providerEnabled("copilot")
        settings: rootItem.settings
    }

    // Every provider is scanned once at startup so the bar knows whether it
    // has anything to show at all — that is the gate above, and without it a
    // machine with usage would show no widget until its panel was opened.
    // Everything after that is refresh-on-open; this shell does not poll.
    Component.onCompleted: refresh()

    function openPanel() {
        if (panelLoader.status === Loader.Null)
            panelLoader.setSource("AiPanel.qml", {
                theme: rootItem.theme,
                usage: rootItem
            });
        panelLoader.item.anchorItem = rootItem;
        panelLoader.item.toggle();
        if (panelLoader.item.opened)
            refresh();
    }

    onTapped: button => {
        if (button === Qt.RightButton)
            refresh();
        else if (button === Qt.MiddleButton)
            selectProvider(providerIndex + 1);
        else
            openPanel();
    }

    // Source-based: the panel compiles on first open, not with the bar (S1).
    PanelLoader {
        id: panelLoader
    }
}
