import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents

// Codex section: weekly quota/time card and every reset, driven by the Codex controller.
ColumnLayout {
    id: codexSection

    readonly property var codex: root.codex
    readonly property color themeColor: codex.getStatusColor()
    readonly property real resetRowHeight: Math.max(PlasmaCore.Units.gridUnit * 1.5,
        rowMetrics.height + PlasmaCore.Units.smallSpacing * 1.5)

    Layout.fillWidth: true
    spacing: PlasmaCore.Units.mediumSpacing

    FontMetrics {
        id: rowMetrics
        font: PlasmaCore.Theme.defaultFont
    }

    SectionHeader {
        controller: codexSection.codex
        iconSource: Qt.resolvedUrl("../icons/codex.png")
        title: i18n("Codex Usage")
        namePrefix: "codex"
    }

    // Section header for 7 Days Cycle
    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.Label {
            text: i18n("7 Days Cycle")
            font.bold: true
            font.pointSize: PlasmaCore.Theme.smallestFont.pointSize
            opacity: 0.7
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }
    }

    // 7-Day Cycle & Quota Comparison Card (Option B: Runway Remaining)
    Rectangle {
        objectName: "cycleCard"
        Layout.fillWidth: true
        radius: 6
        color: Qt.rgba(0, 0, 0, 0.08)
        border.color: Qt.rgba(1, 1, 1, 0.08)
        border.width: 1
        implicitHeight: cycleCol.implicitHeight + PlasmaCore.Units.mediumSpacing * 2

        ColumnLayout {
            id: cycleCol
            anchors.fill: parent
            anchors.margins: PlasmaCore.Units.mediumSpacing
            spacing: PlasmaCore.Units.smallSpacing

            // Row 1: Quota Remaining
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.mediumSpacing

                PlasmaComponents.Label {
                    text: i18n("Quota")
                    font.bold: true
                    font.pointSize: PlasmaCore.Theme.defaultFont.pointSize
                    Layout.preferredWidth: PlasmaCore.Units.gridUnit * 3
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: Layout.preferredWidth
                    elide: Text.ElideRight
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    id: quotaTrack
                    objectName: "quotaTrack"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    height: 8
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.12)
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        objectName: "quotaFill"
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: codex.hasData && codex.leftPercent > 0 ? Math.max(parent.height, parent.width * (Math.min(100, codex.leftPercent) / 100.0)) : 0
                        radius: 4
                        color: codexSection.themeColor
                    }
                }

                PlasmaComponents.Label {
                    objectName: "quotaValue"
                    text: codex.hasData ? codex.leftPercent + "% " + i18n("left") : "—"
                    font.bold: true
                    font.pointSize: PlasmaCore.Theme.defaultFont.pointSize
                    color: codex.hasData ? codexSection.themeColor : PlasmaCore.Theme.textColor
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: PlasmaCore.Units.gridUnit * 4.5
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: Layout.preferredWidth
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.alignment: Qt.AlignVCenter
                }
            }

            // Row 2: Time Remaining
            RowLayout {
                Layout.fillWidth: true
                spacing: PlasmaCore.Units.mediumSpacing

                PlasmaComponents.Label {
                    text: i18n("Time")
                    font.bold: true
                    font.pointSize: PlasmaCore.Theme.defaultFont.pointSize
                    opacity: 0.85
                    Layout.preferredWidth: PlasmaCore.Units.gridUnit * 3
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: Layout.preferredWidth
                    elide: Text.ElideRight
                    Layout.alignment: Qt.AlignVCenter
                }

                Rectangle {
                    id: timeTrack
                    objectName: "timeTrack"
                    Layout.fillWidth: true
                    Layout.minimumWidth: 0
                    height: 8
                    radius: 4
                    color: Qt.rgba(1, 1, 1, 0.12)
                    Layout.alignment: Qt.AlignVCenter

                    readonly property real timeRemainingPercent: Math.max(0, Math.min(100, 100.0 - codex.cycleElapsedPercent))

                    Rectangle {
                        objectName: "timeFill"
                        anchors.left: parent.left
                        anchors.top: parent.top
                        anchors.bottom: parent.bottom
                        width: codex.hasData && parent.timeRemainingPercent > 0 ? Math.max(parent.height, parent.width * (parent.timeRemainingPercent / 100.0)) : 0
                        radius: 4
                        color: PlasmaCore.Theme.highlightColor
                    }
                }

                PlasmaComponents.Label {
                    objectName: "timeValue"
                    text: codex.hasData ? i18n("%1d left", codex.cycleRemainingDays) : "—"
                    font.pointSize: PlasmaCore.Theme.defaultFont.pointSize
                    opacity: 0.85
                    horizontalAlignment: Text.AlignRight
                    Layout.preferredWidth: PlasmaCore.Units.gridUnit * 4.5
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: Layout.preferredWidth
                    elide: Text.ElideRight
                    maximumLineCount: 1
                    Layout.alignment: Qt.AlignVCenter
                }
            }
        }
    }

    // Section header for Resets
    RowLayout {
        Layout.fillWidth: true

        PlasmaComponents.Label {
            text: i18n("All Resets")
            font.bold: true
            font.pointSize: PlasmaCore.Theme.smallestFont.pointSize
            opacity: 0.7
            Layout.minimumWidth: 0
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        Rectangle {
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(1, 1, 1, 0.08)
        }
    }

    // Show every reset without scrolling; keep room for the empty state.
    ListView {
        id: resetsView
        objectName: "resetsView"
        Layout.fillWidth: true
        Layout.minimumHeight: codexSection.resetRowHeight * Math.max(1, count) + spacing * Math.max(0, count - 1)
        Layout.preferredHeight: Layout.minimumHeight
        Layout.maximumHeight: Layout.minimumHeight
        Layout.minimumWidth: 0
        spacing: PlasmaCore.Units.smallSpacing
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        interactive: false
        model: codex.hasData ? codex.resetsList : [
            {label: i18n("Weekly Reset"), countdown: "—", kind: "placeholder"},
            {label: i18n("No reset data yet"), countdown: "—", kind: "placeholder"}
        ]

        PlasmaComponents.Label {
            anchors.centerIn: parent
            width: parent.width
            text: i18n("No resets")
            visible: resetsView.count === 0
            horizontalAlignment: Text.AlignHCenter
            opacity: 0.7
            elide: Text.ElideRight
            maximumLineCount: 1
        }

        delegate: Rectangle {
                width: resetsView.width
                height: codexSection.resetRowHeight
                radius: 4
                color: {
                    if (modelData.is_urgent) return Qt.rgba(0.9, 0.3, 0.1, 0.1);
                    if (hoverArea.containsMouse) return Qt.rgba(1, 1, 1, 0.08);
                    return Qt.rgba(0, 0, 0, 0.04);
                }
                border.color: modelData.is_urgent ? Qt.rgba(0.9, 0.5, 0.1, 0.4) : Qt.rgba(1, 1, 1, 0.05)
                border.width: 1

                MouseArea {
                    id: hoverArea
                    anchors.fill: parent
                    hoverEnabled: true
                    acceptedButtons: Qt.NoButton

                    PlasmaComponents.ToolTip {
                        text: {
                            if (!modelData) return "";
                            if (modelData.kind === "placeholder") return "";
                            var detail = modelData.label + ": " + modelData.countdown;
                            if (modelData.kind === "credit") {
                                if (modelData.date === "Available") {
                                    return detail + "\n" + (modelData.detail || i18n("Available credit"));
                                }
                                var isExp = modelData.countdown === "Expired" || (typeof modelData.remaining_seconds === "number" && modelData.remaining_seconds <= 0);
                                if (isExp) {
                                    return detail + "\n" + (modelData.date && modelData.date !== "--" ? i18n("Expired: %1", modelData.date) : i18n("Expired"));
                                }
                                return detail + "\n" + (modelData.date && modelData.date !== "--" ? i18n("Expires: %1", modelData.date) : i18n("Expires"));
                            }
                            if (modelData.kind === "weekly") {
                                return detail + (modelData.date && modelData.date !== "--" ? "\n" + i18n("Resets: %1", modelData.date) : "");
                            }
                            return detail + (modelData.date ? "\n" + modelData.date : "") + (modelData.detail ? "\n" + modelData.detail : "");
                        }
                        visible: hoverArea.containsMouse && text.length > 0
                    }
                }

                RowLayout {
                    id: resetRow
                    anchors.fill: parent
                    anchors.leftMargin: PlasmaCore.Units.mediumSpacing
                    anchors.rightMargin: PlasmaCore.Units.mediumSpacing
                    spacing: PlasmaCore.Units.smallSpacing

                    // Status dot
                    Rectangle {
                        width: 6
                        height: 6
                        radius: 3
                        color: {
                            if (modelData.is_urgent) return "#e67e22";
                            if (modelData.kind === "placeholder") return PlasmaCore.Theme.disabledTextColor;
                            if (modelData.kind === "weekly") return codexSection.themeColor;
                            return PlasmaCore.Theme.highlightColor;
                        }
                        Layout.alignment: Qt.AlignVCenter
                    }

                    // Col 1: Reset Label
                    PlasmaComponents.Label {
                        objectName: "resetLabel"
                        text: modelData.label
                        font.bold: true
                        font.pointSize: PlasmaCore.Theme.defaultFont.pointSize
                        Layout.alignment: Qt.AlignVCenter
                        Layout.fillWidth: true
                        Layout.minimumWidth: 0
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }

                    // Col 2: Countdown
                    PlasmaComponents.Label {
                        objectName: "resetCountdown"
                        text: modelData.countdown
                        font.pointSize: PlasmaCore.Theme.defaultFont.pointSize
                        color: modelData.is_urgent ? "#e67e22" : PlasmaCore.Theme.textColor
                        opacity: modelData.is_urgent ? 1.0 : 0.85
                        Layout.alignment: Qt.AlignRight | Qt.AlignVCenter
                        Layout.minimumWidth: 0
                        Layout.preferredWidth: PlasmaCore.Units.gridUnit * 5
                        Layout.maximumWidth: Layout.preferredWidth
                        horizontalAlignment: Text.AlignRight
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                }
            }
    }
}
