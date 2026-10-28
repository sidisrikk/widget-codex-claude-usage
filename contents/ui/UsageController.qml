import QtQuick 2.15
import org.kde.plasma.core 2.0 as PlasmaCore

// One provider's fetch state and completion-based scheduler; main.qml owns one per provider.
Item {
    id: controller

    // Provider identity and shared settings, bound by main.qml
    property string provider: "codex"
    property string scriptName: "fetch_usage.py"
    property string displayName: "Codex"
    property int refreshInterval: 600
    property int warningThreshold: 20

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
    property var windowsList: []
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
    readonly property bool needsSignIn: ["no_auth", "no_token", "auth_error", "auth_expired"].indexOf(status) >= 0
    readonly property bool showingSavedQuota: hasData && (status !== "ok" || isRefreshing)
    readonly property bool canRefresh: !isRefreshing && serverCooldownSeconds <= 0
    readonly property string noticeText: buildNoticeText()
    readonly property string statusSummary: buildStatusSummary()
    readonly property string statusDetails: buildStatusDetails()

    // Status-aware gauge color for any quota percentage owned by this provider.
    function colorFor(percent, reached) {
        if (controller.status === "auth_expired" || controller.status === "auth_error" || reached) {
            return "#e74c3c"; // Red
        }
        if (controller.status === "offline") {
            return "#f39c12"; // Orange
        }
        if (percent <= controller.warningThreshold) {
            return "#e74c3c"; // Red (low quota)
        }
        if (percent <= 40) {
            return "#f39c12"; // Amber / Orange
        }
        return "#2ecc71"; // Green (healthy)
    }

    function getStatusColor() {
        return colorFor(controller.leftPercent, controller.limitReached);
    }

    function buildNoticeText() {
        var parts = [];
        if (!controller.hasData) {
            parts.push(i18n("Quota unavailable"));
        } else if (controller.status !== "ok") {
            var savedAt = Qt.formatDateTime(new Date(controller.lastSuccessfulAt * 1000), "ddd, dd MMM yyyy hh:mm:ss");
            parts.push(i18n("Showing saved quota from %1", savedAt));
        }
        if (controller.isRefreshing) {
            parts.push(i18n("Refreshing…"));
        } else if (controller.retryable && controller.isRetryWaiting) {
            parts.push(i18n("Retry in %1 seconds", controller.nextRefreshSeconds));
        }
        if (controller.serverCooldownSeconds > 0) {
            parts.push(i18n("Server cooldown: refresh available in %1 seconds", controller.serverCooldownSeconds));
        }
        if (controller.errorMessage.length > 0) parts.push(controller.errorMessage);
        if (parts.length === 0) parts.push(i18n("Click to open dashboard"));
        return parts.join(" • ");
    }

    function buildStatusSummary() {
        var summary;
        if (controller.isRefreshing) summary = i18n("Refreshing…");
        else if (controller.serverCooldownSeconds > 0) summary = i18n("Server cooldown · %1s", controller.serverCooldownSeconds);
        else if (controller.needsSignIn) summary = i18n("Sign-in required");
        else if (controller.status === "offline") summary = controller.isRetryWaiting
            ? i18n("Offline · retry in %1s", controller.nextRefreshSeconds) : i18n("Offline");
        else if (controller.isRetryWaiting) summary = i18n("Retry in %1s", controller.nextRefreshSeconds);
        else if (controller.status === "error") summary = i18n("Update failed");
        else if (!controller.hasData) summary = i18n("Quota unavailable");
        else summary = i18n("Up to date");
        return controller.showingSavedQuota ? i18n("%1 · saved quota", summary) : summary;
    }

    function buildStatusDetails() {
        if (controller.status === "ok" && controller.hasData) {
            var savedAt = Qt.formatDateTime(new Date(controller.lastSuccessfulAt * 1000), "ddd, dd MMM yyyy hh:mm:ss");
            return controller.isRefreshing
                ? i18n("Showing saved quota from %1", savedAt) + "\n" + controller.noticeText
                : i18n("Quota updated at %1", savedAt);
        }
        return controller.noticeText;
    }

    function refreshUsage() {
        controller.clockNow = Date.now();
        if (controller.isRefreshing || controller.clockNow < controller.serverCooldownUntil) {
            return false;
        }
        pollTimer.stop();
        controller.nextRefreshAt = 0;
        controller.isRefreshing = true;
        var scriptUrl = Qt.resolvedUrl("../scripts/" + controller.scriptName).toString();
        var scriptPath = scriptUrl.replace(/^file:\/\//, "");
        controller.activeUsageSource = "python3 '" + scriptPath + "'";
        executableSource.connectSource(controller.activeUsageSource);
        return true;
    }

    function launchCodex() {
        executableSource.connectSource("nohup /usr/lib/chatgpt/ChatGPT >/dev/null 2>&1 &");
    }

    function finiteNumber(value) {
        return typeof value === "number" && isFinite(value);
    }

    function validCodexSnapshot(data) {
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

    function validClaudeSnapshot(data) {
        if (typeof data.plan !== "string" || typeof data.limit_reached !== "boolean"
                || !finiteNumber(data.used_percent) || !finiteNumber(data.left_percent)
                || !finiteNumber(data.updated_at) || data.updated_at < 0
                || typeof data.updated_formatted !== "string"
                || !Array.isArray(data.windows) || data.windows.length === 0) {
            return false;
        }
        for (var j = 0; j < data.windows.length; j++) {
            var entry = data.windows[j];
            if (!entry || typeof entry !== "object") return false;
            var strings = ["id", "label", "reset_in", "reset_formatted", "time_left_text"];
            for (var k = 0; k < strings.length; k++) {
                if (typeof entry[strings[k]] !== "string") return false;
            }
            var numbers = ["used_percent", "left_percent", "window_seconds", "time_left_percent"];
            for (var n = 0; n < numbers.length; n++) {
                if (!finiteNumber(entry[numbers[n]])) return false;
            }
            if (typeof entry.limit_reached !== "boolean"
                    || !(entry.remaining_seconds === null || finiteNumber(entry.remaining_seconds))) return false;
        }
        return true;
    }

    function validSnapshot(data) {
        return controller.provider === "claude" ? validClaudeSnapshot(data) : validCodexSnapshot(data);
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
            controller.status = data.status;
            controller.attemptedAt = data.attempted_at;
            controller.cached = data.cached;
            controller.retryable = data.retryable;
            controller.retryAfterSeconds = data.retry_after_seconds;
            // Live success is authoritative even after a backwards clock change.
            // Failed attempts may only hydrate memory from a strictly newer cache.
            // Same-second cache writes can fail, leaving older quota with equal timestamps.
            if (data.has_data && (data.status === "ok" || !controller.hasData
                    || data.updated_at > controller.lastSuccessfulAt)) {
                controller.hasData = true;
                controller.plan = data.plan;
                controller.usedPercent = data.used_percent;
                controller.leftPercent = data.left_percent;
                controller.limitReached = data.limit_reached;
                if (controller.provider === "claude") {
                    controller.windowsList = data.windows;
                } else {
                    controller.cycleElapsedPercent = data.cycle_elapsed_percent;
                    controller.cycleElapsedDays = data.cycle_elapsed_days;
                    controller.cycleRemainingDays = data.cycle_remaining_days;
                    controller.resetIn = data.reset_in;
                    controller.resetFormatted = data.reset_formatted;
                    controller.resetsList = data.resets;
                    controller.allowed = data.allowed;
                }
                controller.lastSuccessfulAt = data.updated_at;
                controller.lastUpdated = data.updated_formatted;
            }
            controller.errorMessage = data.error_message || "";
            if (data.status === "ok") controller.retryCount = 0;
        } catch (err) {
            console.warn("Failed to parse " + controller.provider + " usage JSON:", err);
            controller.status = "error";
            controller.errorMessage = i18n("Invalid usage response");
            controller.retryable = false;
            controller.retryAfterSeconds = null;
        }
    }

    function armSchedule() {
        controller.clockNow = Date.now();
        // Timer.interval is an int; wake in chunks without truncating the deadline.
        pollTimer.interval = Math.max(1, Math.min(2147483647, Math.ceil(controller.nextRefreshAt - controller.clockNow)));
        pollTimer.restart();
    }

    function scheduleAfterCompletion() {
        controller.clockNow = Date.now();
        var waitSeconds = Math.max(60, controller.refreshInterval);
        if (controller.retryable) {
            var waits = [15, 30, 60, 120, 300, 600];
            waitSeconds = waits[Math.min(controller.retryCount, waits.length - 1)];
            controller.retryCount = Math.min(controller.retryCount + 1, waits.length);
        }
        controller.serverCooldownUntil = controller.retryAfterSeconds === null ? 0 : controller.clockNow + controller.retryAfterSeconds * 1000;
        controller.nextRefreshAt = Math.max(controller.clockNow + waitSeconds * 1000, controller.serverCooldownUntil);
        armSchedule();
    }

    // Plasma executable data engine
    PlasmaCore.DataSource {
        id: executableSource
        engine: "executable"
        connectedSources: []

        onNewData: (sourceName, data) => {
            disconnectSource(sourceName);
            if (!controller.isRefreshing || sourceName !== controller.activeUsageSource) return;
            controller.activeUsageSource = "";
            controller.isRefreshing = false;
            if (data["exit code"] !== 0) {
                controller.status = "error";
                controller.errorMessage = i18n("Usage fetch failed");
                controller.retryable = false;
                controller.retryAfterSeconds = null;
                controller.attemptedAt = Date.now() / 1000;
            } else {
                controller.parseUsageOutput(data["stdout"] || "");
            }
            controller.scheduleAfterCompletion();
        }
    }

    // Only completions create the next poll/retry deadline.
    Timer {
        id: pollTimer
        repeat: false
        onTriggered: {
            controller.clockNow = Date.now();
            if (controller.clockNow < controller.nextRefreshAt) controller.armSchedule();
            else controller.refreshUsage();
        }
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: controller.clockNow = Date.now()
    }

    Component.onCompleted: {
        controller.refreshUsage();
    }
}
