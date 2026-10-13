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
        var names = ["popupHeader", "titleIcon", "widgetTitle", "headerStatus", "cycleCard", "quotaTrack", "timeTrack", "resetsView"];
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

    function initTestCase() {
        var component = Qt.createComponent("contents/ui/main.qml");
        compare(component.status, Component.Ready, component.errorString());
        applet = component.createObject(renderWindow.contentItem, {width: 600, height: 800});
        verify(applet !== null, component.errorString());
        verify(applet.isRefreshing);
        var source = applet.activeUsageSource;
        verify(source.length > 0);
        compare(applet.refreshUsage(), false);
        compare(applet.activeUsageSource, source);
        compact = applet.Plasmoid.compactRepresentation.createObject(applet, {width: 100, height: 40});
        full = applet.Plasmoid.fullRepresentation.createObject(applet, {width: 600, height: 700});
        verify(compact !== null);
        verify(full !== null);
        full.width = Qt.binding(function() { return full.Layout.preferredWidth; });
        full.height = Qt.binding(function() { return full.Layout.preferredHeight; });
        tryCompare(applet, "isRefreshing", false, 5000);
    }

    function test_states_and_bindings() {
        render();
        var startupHeight = full.Layout.preferredHeight;
        var fixedGeometry = geometry();
        var quota = findChild(full, "quotaValue");
        var time = findChild(full, "timeValue");
        var resets = findChild(full, "resetsView");
        var header = findChild(full, "popupHeader");
        var status = findChild(full, "headerStatus");
        var title = findChild(full, "titleIcon");
        var summary = findChild(full, "statusSummary");
        var titleLabel = findChild(full, "widgetTitle");
        compare(findChild(full, "refreshButton"), null);
        compare(findChild(full, "statusFooter"), null);
        compare(labels(full, "Codex Usage").length, 1);
        verify(findChild(full, "titleTooltip").text.indexOf("Refresh Codex Usage manually") >= 0);
        compare(status.parent, header);
        compare(title.parent, header);
        compare(summary.text, full.statusSummary);
        verify(titleLabel.x >= title.x + title.width);
        verify(status.x >= titleLabel.x + titleLabel.width);
        verify(Math.abs(status.x + status.width - header.width) < 1);
        compare(quota.text, "—");
        compare(time.text, "—");
        compare(findChild(full, "quotaFill").width, 0);
        compare(findChild(full, "timeFill").width, 0);
        compare(resets.count, 2);
        compare(resets.height, full.resetRowHeight * 2 + resets.spacing);
        compare(applet.status, "no_auth");
        compare(applet.hasData, false);
        compare(compact.displayPercent, 0);
        verify(applet.noticeText.indexOf("Quota unavailable") >= 0);
        verify(full.statusDetails.indexOf(applet.noticeText) >= 0);
        compare(applet.activeUsageSource, "");
        verify(applet.nextRefreshAt > Date.now());
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
        applet.parseUsageOutput(JSON.stringify(snapshot));
        render();
        verify(full.Layout.preferredHeight < startupHeight,
                "The popup must fit the current reset count");
        fixedGeometry = geometry();
        compare(applet.hasData, true);
        compare(compact.displayPercent, 75);
        compare(full.displayPercent, 75);
        verify(labels(full, "75% left").length > 0);
        verify(labels(full, "Weekly native").length > 0);
        compare(resets.count, 1);
        compare(quota.text, "75% left");
        compare(time.text, "4.2d left");
        compare(summary.text, "Up to date");
        var statusContent = findChild(full, "headerStatusContent");
        compare(summary.horizontalAlignment, Text.AlignRight);
        verify(Math.abs(statusContent.x + statusContent.width - status.width) < 1,
                "The status icon and text must align at the header's right edge");
        verify(statusContent.width < status.width,
                "Short status text must not stretch its icon across the header");
        verify(findChild(full, "statusTooltip").text.indexOf("Quota updated at") >= 0);
        applet.isRefreshing = true;
        verifyGeometry(fixedGeometry);
        verify(full.statusDetails.indexOf(Qt.formatDateTime(new Date(snapshot.updated_at * 1000),
               "ddd, dd MMM yyyy hh:mm:ss")) >= 0,
               "Refreshing saved quota must expose its full timestamp");
        applet.isRefreshing = false;
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
            applet.parseUsageOutput(JSON.stringify(snapshot));
            render();
            compare(resets.count, count);
            compare(resets.interactive, false);
            verify(resets.contentHeight <= resets.height + 1);
            compare(resets.height, full.resetRowHeight * Math.max(1, count)
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
        applet.parseUsageOutput(JSON.stringify(snapshot));
        resets.positionViewAtBeginning();
        verifyGeometry(fixedGeometry);
        verify(findChild(full, "resetLabel").truncated);
        verify(findChild(full, "resetCountdown").truncated);
        // The title-icon refresh action and header details remain keyboard accessible.
        renderWindow.requestActivate();
        tryCompare(renderWindow, "active", true);
        title.forceActiveFocus();
        tryCompare(findChild(full, "titleTooltip"), "visible", true);
        status.forceActiveFocus();
        verifyGeometry(fixedGeometry);
        tryCompare(findChild(full, "statusTooltip"), "visible", true);
        title.forceActiveFocus();
        // Long header status elides instead of displacing the widget title.
        summary.text = new Array(201).join("S");
        verifyGeometry(fixedGeometry);
        verify(summary.truncated);
        verify(status.x >= titleLabel.x + titleLabel.width);
        verify(Math.abs(status.x + status.width - header.width) < 1);
        verify(Math.abs(statusContent.x + statusContent.width - status.width) < 1,
                "Long elided status must remain right-aligned");
        summary.text = Qt.binding(function() { return full.statusSummary; });
        compare(applet.Plasmoid.toolTipMainText, "Codex: 75% Weekly Quota Remaining");
        applet.Plasmoid.configuration.showPercentageLeft = false;
        compare(compact.displayPercent, 25);
        compare(full.displayPercent, 25);
        snapshot.status = "offline";
        snapshot.retryable = true;
        snapshot.cached = true;
        snapshot.left_percent = 5;
        applet.parseUsageOutput(JSON.stringify(snapshot));
        applet.scheduleAfterCompletion();
        compare(applet.leftPercent, 75); // Same-age cache must not overwrite live quota.
        compare(applet.isRetryWaiting, true);
        verify(applet.noticeText.indexOf("Showing saved quota") >= 0);
        verify(applet.noticeText.indexOf("Retry in") >= 0);
        verify(full.statusSummary.indexOf("Offline") >= 0);
        verify(full.statusSummary.indexOf("saved quota") >= 0);
        verify(full.statusDetails.indexOf("Showing saved quota") >= 0);
        verifyGeometry(fixedGeometry);
        applet.isRefreshing = true;
        verify(full.statusSummary.indexOf("Refreshing") >= 0);
        verify(full.statusSummary.indexOf("saved quota") >= 0);
        compare(title.enabled, false);
        compare(findChild(full, "titleTooltip").text, "Refreshing…");
        mouseClick(title);
        compare(applet.activeUsageSource, "");
        verifyGeometry(fixedGeometry);
        applet.isRefreshing = false;
        snapshot.status = "error";
        snapshot.retry_after_seconds = 120;
        snapshot.error_message = new Array(201).join("E");
        applet.parseUsageOutput(JSON.stringify(snapshot));
        applet.scheduleAfterCompletion();
        verify(full.statusSummary.indexOf("Server cooldown") >= 0);
        verify(full.statusDetails.indexOf(snapshot.error_message) >= 0);
        verify(full.statusDetails.indexOf("Server cooldown") >= 0);
        compare(title.enabled, false);
        verify(findChild(full, "titleTooltip").text.indexOf("Server cooldown") >= 0);
        mouseClick(title);
        compare(applet.activeUsageSource, "");
        compare(applet.refreshUsage(), false);
        verifyGeometry(fixedGeometry);
        snapshot.retry_after_seconds = null;
        applet.parseUsageOutput(JSON.stringify(snapshot));
        applet.scheduleAfterCompletion();
        verify(full.statusSummary.indexOf("Retry in") >= 0);
        compare(title.enabled, true);
        verifyGeometry(fixedGeometry);
        snapshot.retryable = false;
        applet.parseUsageOutput(JSON.stringify(snapshot));
        applet.scheduleAfterCompletion();
        compare(summary.text, "Update failed · saved quota");
        verifyGeometry(fixedGeometry);
        snapshot.status = "offline";
        applet.parseUsageOutput(JSON.stringify(snapshot));
        applet.scheduleAfterCompletion();
        compare(summary.text, "Offline · saved quota");
        verifyGeometry(fixedGeometry);
        var authStates = ["no_auth", "no_token", "auth_error", "auth_expired"];
        for (var auth = 0; auth < authStates.length; ++auth) {
            snapshot.status = authStates[auth];
            snapshot.retryable = false;
            snapshot.retry_after_seconds = null;
            applet.parseUsageOutput(JSON.stringify(snapshot));
            applet.scheduleAfterCompletion();
            verify(full.statusSummary.indexOf("Sign-in required") >= 0);
            verify(full.statusSummary.indexOf("saved quota") >= 0);
            compare(quota.text, "75% left");
            verifyGeometry(fixedGeometry);
        }
        snapshot.status = "ok";
        snapshot.cached = false;
        snapshot.error_message = "";
        snapshot.updated_at = 2000;
        snapshot.left_percent = 65;
        snapshot.used_percent = 35;
        applet.parseUsageOutput(JSON.stringify(snapshot));
        applet.scheduleAfterCompletion();
        compare(quota.text, "65% left");
        verify(full.statusSummary.indexOf("saved quota") < 0);
        compare(applet.retryCount, 0);
        verifyGeometry(fixedGeometry);
        applet.hasData = false;
        render();
        compare(summary.text, "Quota unavailable");
        applet.isRefreshing = true;
        compare(summary.text, "Refreshing…");
        applet.isRefreshing = false;
        applet.hasData = true;
        verifyGeometry(fixedGeometry);
        applet.status = "offline";
        snapshot.status = "offline";
        compare(compact.themeColor, Qt.rgba(243/255, 156/255, 18/255, 1));
        // Clicking the title icon overrides ordinary backoff, but cannot overlap.
        applet.retryable = true;
        applet.scheduleAfterCompletion();
        verify(applet.isRetryWaiting);
        compare(title.enabled, true);
        mouseClick(title);
        verify(applet.isRefreshing);
        compare(applet.refreshUsage(), false);
        tryCompare(applet, "isRefreshing", false, 5000);
        compare(applet.status, "no_auth");
        compare(applet.activeUsageSource, "");
        compare(applet.hasData, true);
        // The native button also supports keyboard activation after completion.
        title.forceActiveFocus();
        keyClick(Qt.Key_Space);
        verify(applet.isRefreshing);
        tryCompare(applet, "isRefreshing", false, 5000);
        compare(applet.activeUsageSource, "");
        render();
        verifyGeometry(fixedGeometry);
        compare(nativeDiagnostics.warnings().length, 0, nativeDiagnostics.warnings().join("\n"));
    }

    function cleanupTestCase() {
        if (compact) compact.destroy();
        if (full) full.destroy();
        if (applet) applet.destroy();
    }
}
