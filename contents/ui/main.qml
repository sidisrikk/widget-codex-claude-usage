import QtQuick 2.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore

Item {
    id: root

    // Applet configuration defaults
    property int refreshInterval: Plasmoid.configuration.refreshInterval || 600
    property bool showPercentageLeft: Plasmoid.configuration.showPercentageLeft !== undefined ? Plasmoid.configuration.showPercentageLeft : true
    property int warningThreshold: Plasmoid.configuration.warningThreshold || 20

    // Live Metrics
    property string status: "loading"
    property string plan: "Loading..."
    property int usedPercent: 0
    property int leftPercent: 100
    property real cycleElapsedPercent: 0.0
    property real cycleElapsedDays: 0.0
    property real cycleRemainingDays: 7.0
    property string resetIn: "--"
    property string resetFormatted: "--"
    property var resetsList: []
    property bool allowed: true
    property bool limitReached: false
    property string errorMessage: ""
    property string lastUpdated: "--:--:--"
    property bool isRefreshing: false
    property bool hasData: false
    property real lastSuccessfulAt: 0
    property real attemptedAt: 0
    property bool cached: false
    property bool retryable: false
    property var retryAfterSeconds: null
    property int retryCount: 0
    property string activeUsageSource: ""
    // Real millisecond deadlines avoid QML int overflow for long Retry-After values.
    property real nextRefreshAt: 0
    property real serverCooldownUntil: 0
    property real clockNow: Date.now()
    readonly property real nextRefreshSeconds: nextRefreshAt > 0 ? Math.max(0, Math.ceil((nextRefreshAt - clockNow) / 1000)) : 0
    readonly property real serverCooldownSeconds: Math.max(0, Math.ceil((serverCooldownUntil - clockNow) / 1000))
    readonly property bool isRetryWaiting: retryable && !isRefreshing && nextRefreshAt > 0
    readonly property string noticeText: buildNoticeText()

    Plasmoid.icon: Qt.resolvedUrl("../icons/codex.png")
    Plasmoid.toolTipMainText: hasData && status === "ok"
        ? i18n("Codex: %1% Weekly Quota Remaining", leftPercent)
        : (!hasData && isRefreshing ? i18n("Codex: Refreshing…") : i18n("Codex: Notice"))

    Plasmoid.toolTipSubText: {
        if (status !== "ok" || !hasData || isRefreshing) {
            return noticeText;
        }
        var lines = [];
        if (resetsList && resetsList.length > 0) {
            for (var i = 0; i < resetsList.length; i++) {
                var r = resetsList[i];
                lines.push(r.label + ": " + r.countdown + " (" + r.date + ")");
            }
        }
        return lines.join("\n");
    }

    Plasmoid.compactRepresentation: CompactRepresentation {}
    Plasmoid.fullRepresentation: FullRepresentation {}

    function getStatusColor() {
        if (status === "auth_error" || status === "auth_expired"
                || status === "no_auth" || status === "no_token" || limitReached) {
            return "#e74c3c"; // Red
        }
        if (status === "offline") {
            return "#f39c12"; // Orange
        }
        if (leftPercent <= root.warningThreshold) {
            return "#e74c3c"; // Red (low quota)
        }
        if (leftPercent <= 40) {
            return "#f39c12"; // Amber / Orange
        }
        return "#2ecc71"; // Green (healthy)
    }

    function action_refresh() {
        root.refreshUsage();
    }

    function buildNoticeText() {
        var parts = [];
        if (!root.hasData) {
            parts.push(i18n("Quota unavailable"));
        } else if (root.status !== "ok") {
            var savedAt = Qt.formatDateTime(new Date(root.lastSuccessfulAt * 1000), "ddd, dd MMM yyyy hh:mm:ss");
            parts.push(i18n("Showing saved quota from %1", savedAt));
        }
        if (root.isRefreshing) {
            parts.push(i18n("Refreshing…"));
        } else if (root.retryable && root.isRetryWaiting) {
            parts.push(i18n("Retry in %1 seconds", root.nextRefreshSeconds));
        }
        if (root.serverCooldownSeconds > 0) {
            parts.push(i18n("Server cooldown: refresh available in %1 seconds", root.serverCooldownSeconds));
        }
        if (root.errorMessage.length > 0) parts.push(root.errorMessage);
        if (parts.length === 0) parts.push(i18n("Click to open dashboard"));
        return parts.join(" • ");
    }

    function refreshUsage() {
        root.clockNow = Date.now();
        if (root.isRefreshing || root.clockNow < root.serverCooldownUntil) {
            return false;
        }
        pollTimer.stop();
        root.nextRefreshAt = 0;
        root.isRefreshing = true;
        var scriptUrl = Qt.resolvedUrl("../scripts/fetch_usage.py").toString();
        // QUrl strings escape spaces and other characters; decode before shell quoting.
        var scriptPath = decodeURIComponent(scriptUrl.replace(/^file:\/\//, ""));
        root.activeUsageSource = "python3 " + root.shellQuote(scriptPath);
        executableSource.connectSource(root.activeUsageSource);
        return true;
    }

    function shellQuote(value) {
        return "'" + String(value).split("'").join("'\\''") + "'";
    }

    function launchCodex() {
        executableSource.connectSource("nohup /usr/lib/chatgpt/ChatGPT >/dev/null 2>&1 &");
    }

    function finiteNumber(value) {
        return typeof value === "number" && isFinite(value);
    }

    function validSnapshot(data) {
        if (typeof data.plan !== "string" || typeof data.reset_in !== "string"
                || typeof data.reset_formatted !== "string" || !Array.isArray(data.resets)
                || typeof data.allowed !== "boolean" || typeof data.limit_reached !== "boolean"
                || !finiteNumber(data.updated_at) || data.updated_at < 0
                || typeof data.updated_formatted !== "string") {
            return false;
        }
        var numbers = ["used_percent", "left_percent", "cycle_elapsed_percent",
                       "cycle_elapsed_days", "cycle_remaining_days"];
        for (var i = 0; i < numbers.length; i++) {
            if (!finiteNumber(data[numbers[i]])) return false;
        }
        for (var j = 0; j < data.resets.length; j++) {
            var reset = data.resets[j];
            if (!reset || typeof reset !== "object") return false;
            var strings = ["id", "label", "kind", "countdown", "date", "detail"];
            for (var k = 0; k < strings.length; k++) {
                if (typeof reset[strings[k]] !== "string") return false;
            }
            if (typeof reset.is_urgent !== "boolean"
                    || !(reset.remaining_seconds === null || finiteNumber(reset.remaining_seconds))) return false;
        }
        return true;
    }

    function parseUsageOutput(raw) {
        try {
            var data = JSON.parse(raw);
            var statuses = ["ok", "no_auth", "no_token", "auth_error", "auth_expired", "error", "offline"];
            if (!data || typeof data !== "object" || statuses.indexOf(data.status) < 0
                    || typeof data.retryable !== "boolean" || typeof data.has_data !== "boolean"
                    || typeof data.cached !== "boolean" || !finiteNumber(data.attempted_at) || data.attempted_at < 0
                    || !(data.retry_after_seconds === null || (finiteNumber(data.retry_after_seconds) && data.retry_after_seconds >= 0))
                    || (data.retry_after_seconds !== null && (!data.retryable || data.status !== "error"))
                    || (data.status === "ok" && (!data.has_data || data.retryable || data.cached))
                    || (data.retryable && data.status !== "offline" && data.status !== "error")
                    || (data.error_message !== undefined && typeof data.error_message !== "string")
                    || (data.has_data ? !validSnapshot(data) : (data.updated_at !== null || data.updated_formatted !== null))) {
                throw new Error("Invalid usage response");
            }
            root.status = data.status;
            root.attemptedAt = data.attempted_at;
            root.cached = data.cached;
            root.retryable = data.retryable;
            root.retryAfterSeconds = data.retry_after_seconds;
            // Live success is authoritative even after a backwards clock change.
            // Failed attempts may only hydrate memory from a strictly newer cache.
            // Same-second cache writes can fail, leaving older quota with equal timestamps.
            if (data.has_data && (data.status === "ok" || !root.hasData
                    || data.updated_at > root.lastSuccessfulAt)) {
                root.hasData = true;
                root.plan = data.plan;
                root.usedPercent = data.used_percent;
                root.leftPercent = data.left_percent;
                root.cycleElapsedPercent = data.cycle_elapsed_percent;
                root.cycleElapsedDays = data.cycle_elapsed_days;
                root.cycleRemainingDays = data.cycle_remaining_days;
                root.resetIn = data.reset_in;
                root.resetFormatted = data.reset_formatted;
                root.resetsList = data.resets;
                root.allowed = data.allowed;
                root.limitReached = data.limit_reached;
                root.lastSuccessfulAt = data.updated_at;
                root.lastUpdated = data.updated_formatted;
            }
            root.errorMessage = data.error_message || "";
            if (data.status === "ok") root.retryCount = 0;
        } catch (err) {
            console.warn("Failed to parse codex usage JSON:", err);
            root.status = "error";
            root.errorMessage = i18n("Invalid usage response");
            root.retryable = false;
            root.retryAfterSeconds = null;
        }
    }

    function armSchedule() {
        root.clockNow = Date.now();
        // Timer.interval is an int; wake in chunks without truncating the deadline.
        pollTimer.interval = Math.max(1, Math.min(2147483647, Math.ceil(root.nextRefreshAt - root.clockNow)));
        pollTimer.restart();
    }

    function scheduleAfterCompletion() {
        root.clockNow = Date.now();
        var waitSeconds = Math.max(60, root.refreshInterval);
        if (root.retryable) {
            var waits = [15, 30, 60, 120, 300, 600];
            waitSeconds = waits[Math.min(root.retryCount, waits.length - 1)];
            root.retryCount = Math.min(root.retryCount + 1, waits.length);
        }
        root.serverCooldownUntil = root.retryAfterSeconds === null ? 0 : root.clockNow + root.retryAfterSeconds * 1000;
        root.nextRefreshAt = Math.max(root.clockNow + waitSeconds * 1000, root.serverCooldownUntil);
        armSchedule();
    }

    // Plasma executable data engine
    PlasmaCore.DataSource {
        id: executableSource
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (!root.isRefreshing || sourceName !== root.activeUsageSource) return;
            root.activeUsageSource = "";
            root.isRefreshing = false;
            if (data["exit code"] !== 0) {
                root.status = "error";
                root.errorMessage = i18n("Usage fetch failed");
                root.retryable = false;
                root.retryAfterSeconds = null;
                root.attemptedAt = Date.now() / 1000;
            } else {
                root.parseUsageOutput(data["stdout"] || "");
            }
            root.scheduleAfterCompletion();
        }
    }

    // Only completions create the next poll/retry deadline.
    Timer {
        id: pollTimer
        repeat: false
        onTriggered: {
            root.clockNow = Date.now();
            if (root.clockNow < root.nextRefreshAt) root.armSchedule();
            else root.refreshUsage();
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: root.clockNow = Date.now()
    }

    Component.onCompleted: {
        Plasmoid.setAction("refresh", i18n("Refresh"), "view-refresh");
        root.refreshUsage();
    }
}
