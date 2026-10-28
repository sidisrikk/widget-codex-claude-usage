import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Window 2.15
import QtTest 1.2
import org.kde.plasma.plasmoid 2.0

TestCase {
    id: test
    name: "ProductionNative"
    // Defer starting until the view is exposed, outside windowShown's binding
    // evaluation: native executable/frame waits reenter the event loop.
    when: false
    onWindowShownChanged: {
        if (windowShown) Qt.callLater(function() { test.when = true; });
    }
    width: 600
    height: 800
    property var applet
    property var compact
    property var full

    Window {
        id: renderWindow
        visible: true
        width: 600
        height: 800
    }

    SignalSpy {
        id: renderedFrame
        target: renderWindow
        signalName: "frameSwapped"
    }

    function render() {
        renderedFrame.clear();
        renderWindow.update();
        renderedFrame.wait(1000);
        verify(renderedFrame.count > 0, "The native window must render the changed layout");
    }

    function geometry() {
        var values = [full.width, full.height, full.Layout.preferredWidth, full.Layout.preferredHeight];
        var names = ["codexHeader", "codexTitleIcon", "codexTitle", "codexHeaderStatus", "codexRefresh", "cycleCard",
                     "quotaTrack", "timeTrack", "resetsView", "claudeSection", "claudeHeader", "claudeTitleIcon",
                     "claudeHeaderStatus", "claudeRefresh"];
        for (var i = 0; i < names.length; ++i) {
            var item = findChild(full, names[i]);
            verify(item !== null, names[i]);
            var position = item.mapToItem(full, 0, 0);
            values.push(position.x, position.y, item.width, item.height);
        }
        return values;
    }

    function verifyGeometry(expected) {
        render();
        compare(JSON.stringify(geometry()), JSON.stringify(expected),
                "Popup size and section positions must remain fixed");
    }

    function labels(item, text) {
        var matches = [];
        if (item.text !== undefined && item.text === text) matches.push(item);
        for (var i = 0; i < item.children.length; ++i)
            matches = matches.concat(labels(item.children[i], text));
        return matches;
    }

    function named(item, name) {
        var matches = [];
        if (item.objectName === name) matches.push(item);
        for (var i = 0; i < item.children.length; ++i)
            matches = matches.concat(named(item.children[i], name));
        return matches;
    }

    function claudeWindow(id, label, left, resetIn, timeText, timePercent) {
        return {id: id, label: label, used_percent: 100 - left, left_percent: left, window_seconds: 604800,
            reset_in: resetIn, reset_formatted: "Fri, 30 Oct 20:00", remaining_seconds: 3600,
            time_left_percent: timePercent, time_left_text: timeText, limit_reached: false};
    }

    function initTestCase() {
        var component = Qt.createComponent("contents/ui/main.qml");
        compare(component.status, Component.Ready, component.errorString());
        applet = component.createObject(renderWindow.contentItem, {width: 600, height: 800});
        verify(applet !== null, component.errorString());
        verify(applet.codex.isRefreshing);
        verify(applet.claude.isRefreshing);
        var source = applet.codex.activeUsageSource;
        verify(source.indexOf("fetch_usage.py") >= 0);
        verify(applet.claude.activeUsageSource.indexOf("fetch_claude_usage.py") >= 0);
        compare(applet.codex.refreshUsage(), false);
        compare(applet.codex.activeUsageSource, source);
        compact = applet.Plasmoid.compactRepresentation.createObject(applet, {width: 100, height: 40});
        full = applet.Plasmoid.fullRepresentation.createObject(applet, {width: 600, height: 700});
        verify(compact !== null);
        verify(full !== null);
        full.width = Qt.binding(function() { return full.Layout.preferredWidth; });
        full.height = Qt.binding(function() { return full.Layout.preferredHeight; });
        tryCompare(applet.codex, "isRefreshing", false, 5000);
        tryCompare(applet.claude, "isRefreshing", false, 5000);
    }

    function test_states_and_bindings() {
        var codex = codex.codex;
        var codexSection = findChild(full, "codexSection");
        render();
        var startupHeight = full.Layout.preferredHeight;
        var fixedGeometry = geometry();
        var quota = findChild(full, "quotaValue");
        var time = findChild(full, "timeValue");
        var resets = findChild(full, "resetsView");
        var header = findChild(full, "codexHeader");
        var status = findChild(full, "codexHeaderStatus");
        var title = findChild(full, "codexTitleIcon");
        var summary = findChild(full, "codexStatusSummary");
        var titleLabel = findChild(full, "codexTitle");
        verify(findChild(full, "codexRefresh") !== null);
        compare(findChild(full, "statusFooter"), null);
        compare(labels(full, "Codex Usage").length, 1);
        verify(findChild(full, "codexTitleTooltip").text.indexOf("Refresh Codex Usage manually") >= 0);
        compare(status.parent, header);
        compare(title.parent, header);
        compare(summary.text, codex.statusSummary);
        verify(titleLabel.x >= title.x + title.width);
        verify(status.x >= titleLabel.x + titleLabel.width);
        verify(Math.abs(status.x + status.width - header.width) < 1);
        compare(quota.text, "—");
        compare(time.text, "—");
        compare(findChild(full, "quotaFill").width, 0);
        compare(findChild(full, "timeFill").width, 0);
        compare(resets.count, 2);
        compare(resets.height, codexSection.resetRowHeight * 2 + resets.spacing);
        compare(codex.status, "no_auth");
        compare(codex.hasData, false);
        compare(compact.displayPercent(codex), 0);
        verify(codex.noticeText.indexOf("Quota unavailable") >= 0);
        verify(codex.statusDetails.indexOf(codex.noticeText) >= 0);
        compare(codex.activeUsageSource, "");
        verify(codex.nextRefreshAt > Date.now());
        var snapshot = {
            status: "ok", retryable: false, has_data: true, cached: false,
            attempted_at: 1000, retry_after_seconds: null, updated_at: 1000,
            updated_formatted: "12:00:00", plan: "Plus", used_percent: 25,
            left_percent: 75, cycle_elapsed_percent: 40, cycle_elapsed_days: 2.8,
            cycle_remaining_days: 4.2, reset_in: "4d", reset_formatted: "Tomorrow",
            allowed: true, limit_reached: false,
            resets: [{id: "weekly", label: "Weekly native", kind: "weekly",
                countdown: "4d", date: "Tomorrow", detail: "", is_urgent: false,
                remaining_seconds: 345600}]
        };
        codex.parseUsageOutput(JSON.stringify(snapshot));
        render();
        verify(full.Layout.preferredHeight < startupHeight,
                "The popup must fit the current reset count");
        fixedGeometry = geometry();
        compare(codex.hasData, true);
        compare(compact.displayPercent(codex), 75);
        verify(labels(full, "75% left").length > 0);
        verify(labels(full, "Weekly native").length > 0);
        compare(resets.count, 1);
        compare(quota.text, "75% left");
        compare(time.text, "4.2d left");
        compare(summary.text, "Up to date");
        var statusContent = findChild(full, "codexHeaderStatusContent");
        compare(summary.horizontalAlignment, Text.AlignRight);
        verify(Math.abs(statusContent.x + statusContent.width - status.width) < 1,
                "The status icon and text must align at the header's right edge");
        verify(statusContent.width < status.width,
                "Short status text must not stretch its icon across the header");
        verify(findChild(full, "codexStatusTooltip").text.indexOf("Quota updated at") >= 0);
        codex.isRefreshing = true;
        verifyGeometry(fixedGeometry);
        verify(codex.statusDetails.indexOf(Qt.formatDateTime(new Date(snapshot.updated_at * 1000),
               "ddd, dd MMM yyyy hh:mm:ss")) >= 0,
               "Refreshing saved quota must expose its full timestamp");
        codex.isRefreshing = false;
        // Every reset must fit without scrolling, including the last delegate.
        for (var count = 0; count <= 6; ++count) {
            var entries = [];
            for (var index = 0; index < count; ++index) {
                entries.push({id: "credit-" + index, label: index === 0 ? "Weekly native" : "Reset credit " + index,
                    kind: index === 0 ? "weekly" : "credit",
                    countdown: index === 1 ? "Available" : (index === 2 ? "Expired" : "5d left"),
                    date: index === 1 ? "Available" : "Tomorrow", detail: "Native credit",
                    is_urgent: index === 2, remaining_seconds: index === 1 ? null : (index === 2 ? -1 : 432000)});
            }
            snapshot.resets = entries;
            codex.parseUsageOutput(JSON.stringify(snapshot));
            render();
            compare(resets.count, count);
            compare(resets.interactive, false);
            verify(resets.contentHeight <= resets.height + 1);
            compare(resets.height, codexSection.resetRowHeight * Math.max(1, count)
                    + resets.spacing * Math.max(0, count - 1));
            for (var row = 0; row < count; ++row) {
                var delegate = resets.itemAtIndex(row);
                verify(delegate !== null, "Every reset delegate must be instantiated");
                verify(delegate.y >= 0 && delegate.y + delegate.height <= resets.height + 1,
                        "Every reset must be visible without scrolling");
            }
            var listPosition = resets.mapToItem(full, 0, 0);
            verify(listPosition.y + resets.height <= full.height,
                    "Every reset row must fit in the popup without a footer");
        }
        fixedGeometry = geometry();
        snapshot.resets[0].label = new Array(201).join("W");
        snapshot.resets[0].countdown = new Array(201).join("9");
        codex.parseUsageOutput(JSON.stringify(snapshot));
        resets.positionViewAtBeginning();
        verifyGeometry(fixedGeometry);
        verify(findChild(full, "resetLabel").truncated);
        verify(findChild(full, "resetCountdown").truncated);
        // The title-icon refresh action and header details remain keyboard accessible.
        renderWindow.requestActivate();
        tryCompare(renderWindow, "active", true);
        title.forceActiveFocus();
        tryCompare(findChild(full, "codexTitleTooltip"), "visible", true);
        status.forceActiveFocus();
        verifyGeometry(fixedGeometry);
        tryCompare(findChild(full, "codexStatusTooltip"), "visible", true);
        title.forceActiveFocus();
        // Long header status elides instead of displacing the widget title.
        summary.text = new Array(201).join("S");
        verifyGeometry(fixedGeometry);
        verify(summary.truncated);
        verify(status.x >= titleLabel.x + titleLabel.width);
        verify(Math.abs(status.x + status.width - header.width) < 1);
        verify(Math.abs(statusContent.x + statusContent.width - status.width) < 1,
                "Long elided status must remain right-aligned");
        summary.text = Qt.binding(function() { return codex.statusSummary; });
        compare(applet.Plasmoid.toolTipMainText, "Codex & Claude Usage");
        verify(applet.Plasmoid.toolTipSubText.indexOf("Codex: 75% left") === 0);
        applet.Plasmoid.configuration.showPercentageLeft = false;
        compare(compact.displayPercent(codex), 25);
        snapshot.status = "offline";
        snapshot.retryable = true;
        snapshot.cached = true;
        snapshot.left_percent = 5;
        codex.parseUsageOutput(JSON.stringify(snapshot));
        codex.scheduleAfterCompletion();
        compare(codex.leftPercent, 75); // Same-age cache must not overwrite live quota.
        compare(codex.isRetryWaiting, true);
        verify(codex.noticeText.indexOf("Showing saved quota") >= 0);
        verify(codex.noticeText.indexOf("Retry in") >= 0);
        verify(codex.statusSummary.indexOf("Offline") >= 0);
        verify(codex.statusSummary.indexOf("saved quota") >= 0);
        verify(codex.statusDetails.indexOf("Showing saved quota") >= 0);
        verifyGeometry(fixedGeometry);
        codex.isRefreshing = true;
        verify(codex.statusSummary.indexOf("Refreshing") >= 0);
        verify(codex.statusSummary.indexOf("saved quota") >= 0);
        compare(title.enabled, false);
        compare(findChild(full, "codexTitleTooltip").text, "Refreshing…");
        mouseClick(title);
        compare(codex.activeUsageSource, "");
        verifyGeometry(fixedGeometry);
        codex.isRefreshing = false;
        snapshot.status = "error";
        snapshot.retry_after_seconds = 120;
        snapshot.error_message = new Array(201).join("E");
        codex.parseUsageOutput(JSON.stringify(snapshot));
        codex.scheduleAfterCompletion();
        verify(codex.statusSummary.indexOf("Server cooldown") >= 0);
        verify(codex.statusDetails.indexOf(snapshot.error_message) >= 0);
        verify(codex.statusDetails.indexOf("Server cooldown") >= 0);
        compare(title.enabled, false);
        verify(findChild(full, "codexTitleTooltip").text.indexOf("Server cooldown") >= 0);
        mouseClick(title);
        compare(codex.activeUsageSource, "");
        compare(codex.refreshUsage(), false);
        verifyGeometry(fixedGeometry);
        snapshot.retry_after_seconds = null;
        codex.parseUsageOutput(JSON.stringify(snapshot));
        codex.scheduleAfterCompletion();
        verify(codex.statusSummary.indexOf("Retry in") >= 0);
        compare(title.enabled, true);
        verifyGeometry(fixedGeometry);
        snapshot.retryable = false;
        codex.parseUsageOutput(JSON.stringify(snapshot));
        codex.scheduleAfterCompletion();
        compare(summary.text, "Update failed · saved quota");
        verifyGeometry(fixedGeometry);
        snapshot.status = "offline";
        codex.parseUsageOutput(JSON.stringify(snapshot));
        codex.scheduleAfterCompletion();
        compare(summary.text, "Offline · saved quota");
        verifyGeometry(fixedGeometry);
        var authStates = ["no_auth", "no_token", "auth_error", "auth_expired"];
        for (var auth = 0; auth < authStates.length; ++auth) {
            snapshot.status = authStates[auth];
            snapshot.retryable = false;
            snapshot.retry_after_seconds = null;
            codex.parseUsageOutput(JSON.stringify(snapshot));
            codex.scheduleAfterCompletion();
            verify(codex.statusSummary.indexOf("Sign-in required") >= 0);
            verify(codex.statusSummary.indexOf("saved quota") >= 0);
            compare(quota.text, "75% left");
            verifyGeometry(fixedGeometry);
        }
        snapshot.status = "ok";
        snapshot.cached = false;
        snapshot.error_message = "";
        snapshot.updated_at = 2000;
        snapshot.left_percent = 65;
        snapshot.used_percent = 35;
        codex.parseUsageOutput(JSON.stringify(snapshot));
        codex.scheduleAfterCompletion();
        compare(quota.text, "65% left");
        verify(codex.statusSummary.indexOf("saved quota") < 0);
        compare(codex.retryCount, 0);
        verifyGeometry(fixedGeometry);
        codex.hasData = false;
        render();
        compare(summary.text, "Quota unavailable");
        codex.isRefreshing = true;
        compare(summary.text, "Refreshing…");
        codex.isRefreshing = false;
        codex.hasData = true;
        verifyGeometry(fixedGeometry);
        codex.status = "offline";
        snapshot.status = "offline";
        compare(findChild(compact, "compactGauge").themeColor, Qt.rgba(243/255, 156/255, 18/255, 1));
        // Clicking the title icon overrides ordinary backoff, but cannot overlap.
        codex.retryable = true;
        codex.scheduleAfterCompletion();
        verify(codex.isRetryWaiting);
        compare(title.enabled, true);
        mouseClick(title);
        verify(codex.isRefreshing);
        compare(codex.refreshUsage(), false);
        tryCompare(applet, "isRefreshing", false, 5000);
        compare(codex.status, "no_auth");
        compare(codex.activeUsageSource, "");
        compare(codex.hasData, true);
        // The native button also supports keyboard activation after completion.
        title.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(codex.isRefreshing);
        tryCompare(applet, "isRefreshing", false, 5000);
        compare(codex.activeUsageSource, "");
        render();
        verifyGeometry(fixedGeometry);
        compare(nativeDiagnostics.warnings().length, 0, nativeDiagnostics.warnings().join("\n"));
    }

    function test_claude_section_and_independent_refresh() {
        var claude = applet.claude;
        var codex = applet.codex;
        tryCompare(codex, "isRefreshing", false, 5000);
        tryCompare(claude, "isRefreshing", false, 5000);
        var repeater = findChild(full, "claudeWindows");
        var claudeRefresh = findChild(full, "claudeRefresh");
        var claudeIcon = findChild(full, "claudeTitleIcon");
        var codexRefresh = findChild(full, "codexRefresh");
        verify(repeater !== null && claudeRefresh !== null && claudeIcon !== null && codexRefresh !== null);
        compare(labels(full, "Claude Usage").length, 1);
        compare(claudeRefresh.parent, findChild(full, "claudeHeader"));
        var claudeStatus = findChild(full, "claudeHeaderStatus");
        verify(claudeRefresh.x >= claudeStatus.x + claudeStatus.width,
               "The refresh button sits after the right-aligned status");
        // Placeholder pairs reserve the live two-window size before quota arrives.
        claude.hasData = false;
        render();
        compare(repeater.count, 2);
        compare(labels(full, "Session (5h)").length, 1);
        var placeholderHeight = full.Layout.preferredHeight;
        var snapshot = {
            status: "ok", retryable: false, has_data: true, cached: false,
            attempted_at: 1000, retry_after_seconds: null, updated_at: 1000,
            updated_formatted: "12:00:00", plan: "Pro", used_percent: 64, left_percent: 36,
            limit_reached: false,
            windows: [claudeWindow("session", "Session (5h)", 36, "3h 12m", "3.2h left", 64),
                      claudeWindow("weekly", "Weekly", 82, "4d 6h 10m", "4.3d left", 60.8)]
        };
        claude.parseUsageOutput(JSON.stringify(snapshot));
        render();
        compare(claude.hasData, true);
        compare(repeater.count, 2);
        compare(full.Layout.preferredHeight, placeholderHeight);
        compare(labels(full, "36% left").length, 1);
        compare(labels(full, "82% left").length, 1);
        compare(labels(full, "resets 3h 12m").length, 1);
        compare(labels(full, "4.3d left").length, 1);
        compare(named(full, "claudeQuotaFill")[0].color, Qt.rgba(243/255, 156/255, 18/255, 1));
        // An optional per-model window adds a pair that still fits in the popup.
        snapshot.windows.push(claudeWindow("weekly_sonnet", "Weekly Sonnet", 95, "4d 6h 10m", "4.3d left", 60.8));
        claude.parseUsageOutput(JSON.stringify(snapshot));
        render();
        compare(repeater.count, 3);
        verify(full.Layout.preferredHeight > placeholderHeight);
        var last = repeater.itemAt(2);
        verify(last.mapToItem(full, 0, 0).y + last.height <= full.height);
        snapshot.windows.pop();
        claude.parseUsageOutput(JSON.stringify(snapshot));
        render();
        compare(full.Layout.preferredHeight, placeholderHeight);
        // A Claude server cooldown disables only Claude's buttons.
        snapshot.status = "error";
        snapshot.retryable = true;
        snapshot.cached = true;
        snapshot.retry_after_seconds = 120;
        claude.parseUsageOutput(JSON.stringify(snapshot));
        claude.scheduleAfterCompletion();
        compare(claudeRefresh.enabled, false);
        compare(claudeIcon.enabled, false);
        verify(claude.statusSummary.indexOf("Server cooldown") >= 0);
        codex.serverCooldownUntil = 0;
        compare(codexRefresh.enabled, true);
        mouseClick(claudeRefresh);
        compare(claude.activeUsageSource, "");
        mouseClick(codexRefresh);
        verify(codex.isRefreshing);
        compare(claude.isRefreshing, false);
        tryCompare(codex, "isRefreshing", false, 5000);
        // Claude's refresh button launches only the Claude backend.
        claude.serverCooldownUntil = 0;
        claude.clockNow = Date.now();
        compare(claudeRefresh.enabled, true);
        mouseClick(claudeRefresh);
        verify(claude.isRefreshing);
        verify(claude.activeUsageSource.indexOf("fetch_claude_usage.py") >= 0);
        compare(codex.isRefreshing, false);
        compare(claudeRefresh.enabled, false);
        tryCompare(claude, "isRefreshing", false, 5000);
        compare(claude.status, "no_auth");
        compare(claude.hasData, true);
        verify(claude.statusSummary.indexOf("Sign-in required") >= 0);
        compare(labels(full, "36% left").length, 1);
        // The panel shows one gauge per provider.
        var gauges = named(compact, "compactGauge");
        compare(gauges.length, 2);
        compare(gauges[1].usage, claude);
        compare(gauges[1].displayPercent, compact.displayPercent(claude));
        compare(nativeDiagnostics.warnings().length, 0, nativeDiagnostics.warnings().join("\n"));
    }

    function cleanupTestCase() {
        if (compact) compact.destroy();
        if (full) full.destroy();
        if (applet) applet.destroy();
    }
}
