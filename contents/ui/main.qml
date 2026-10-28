import QtQuick 2.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root

    // Applet configuration defaults
    property int refreshInterval: Plasmoid.configuration.refreshInterval || 600
    property bool showPercentageLeft: Plasmoid.configuration.showPercentageLeft !== undefined ? Plasmoid.configuration.showPercentageLeft : true
    property int warningThreshold: Plasmoid.configuration.warningThreshold || 20

    // Independent per-provider state; each section refreshes only its own controller.
    readonly property var codex: codexUsage
    readonly property var claude: claudeUsage
    readonly property var providers: [codexUsage, claudeUsage]

    Plasmoid.icon: Qt.resolvedUrl("../icons/codex.png")
    Plasmoid.toolTipMainText: i18n("Codex & Claude Usage")
    Plasmoid.toolTipSubText: providers.map(providerToolTip).join("\n\n")

    Plasmoid.compactRepresentation: CompactRepresentation {}
    Plasmoid.fullRepresentation: FullRepresentation {}

    function providerToolTip(usage) {
        if (usage.status !== "ok" || !usage.hasData || usage.isRefreshing) {
            return usage.displayName + ": " + usage.noticeText;
        }
        var lines = [i18n("%1: %2% left", usage.displayName, usage.leftPercent)];
        var entries = usage.provider === "claude" ? usage.windowsList : usage.resetsList;
        for (var i = 0; i < entries.length; i++) {
            var entry = entries[i];
            lines.push(usage.provider === "claude"
                ? entry.label + ": " + i18n("%1% left · resets %2", entry.left_percent, entry.reset_in)
                : entry.label + ": " + entry.countdown + " (" + entry.date + ")");
        }
        return lines.join("\n");
    }

    function action_refresh() {
        codexUsage.refreshUsage();
        claudeUsage.refreshUsage();
    }

    UsageController {
        id: codexUsage
        provider: "codex"
        scriptName: "fetch_usage.py"
        displayName: i18n("Codex")
        refreshInterval: root.refreshInterval
        warningThreshold: root.warningThreshold
    }

    UsageController {
        id: claudeUsage
        provider: "claude"
        scriptName: "fetch_claude_usage.py"
        displayName: i18n("Claude")
        refreshInterval: root.refreshInterval
        warningThreshold: root.warningThreshold
    }

    Component.onCompleted: {
        Plasmoid.setAction("refresh", i18n("Refresh"), "view-refresh");
    }
}
