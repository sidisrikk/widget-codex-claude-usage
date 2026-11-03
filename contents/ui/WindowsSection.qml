import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents

// Reusable windows section: one quota/time pair per rate-limit window (Claude, Antigravity).
ColumnLayout {
    id: windowsSection

    property var controller
    property url iconSource
    property string title
    property string namePrefix: "claude"
    // Placeholder pairs keep the section's size stable until quota arrives.
    property var placeholderWindows: [
        {id: "session", label: i18n("Session (5h)")},
        {id: "weekly", label: i18n("Weekly")}
    ]

    Layout.fillWidth: true
    spacing: PlasmaCore.Units.mediumSpacing

    SectionHeader {
        controller: windowsSection.controller
        iconSource: windowsSection.iconSource
        title: windowsSection.title
        namePrefix: windowsSection.namePrefix
    }

    Repeater {
        id: windowsRepeater
        objectName: windowsSection.namePrefix + "Windows"
        model: windowsSection.controller.hasData ? windowsSection.controller.windowsList : windowsSection.placeholderWindows

        delegate: ColumnLayout {
            id: pair
            objectName: windowsSection.namePrefix + "Window"
            Layout.fillWidth: true
            spacing: PlasmaCore.Units.smallSpacing

            readonly property bool live: windowsSection.controller.hasData
            readonly property color quotaColor: live
                ? windowsSection.controller.colorFor(modelData.left_percent, modelData.limit_reached)
                : PlasmaCore.Theme.textColor

            // Pair header: label, divider and this window's reset countdown
            RowLayout {
                Layout.fillWidth: true

                PlasmaComponents.Label {
                    objectName: windowsSection.namePrefix + "WindowLabel"
                    text: modelData.label
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

                PlasmaComponents.Label {
                    objectName: windowsSection.namePrefix + "ResetIn"
                    text: !pair.live ? "—"
                        : (modelData.reset_formatted === "--" ? i18n("Not started") : i18n("resets %1", modelData.reset_in))
                    font.pointSize: PlasmaCore.Theme.smallestFont.pointSize
                    opacity: 0.7
                    horizontalAlignment: Text.AlignRight
                    Layout.minimumWidth: 0
                    Layout.maximumWidth: PlasmaCore.Units.gridUnit * 7
                    elide: Text.ElideRight
                    maximumLineCount: 1

                    MouseArea {
                        id: resetHover
                        anchors.fill: parent
                        hoverEnabled: true
                        acceptedButtons: Qt.NoButton
                    }

                    PlasmaComponents.ToolTip {
                        text: pair.live && modelData.reset_formatted !== "--"
                            ? i18n("Resets: %1", modelData.reset_formatted) : ""
                        visible: resetHover.containsMouse && text.length > 0
                    }
                }
            }

            Rectangle {
                objectName: windowsSection.namePrefix + "Card"
                Layout.fillWidth: true
                radius: 6
                color: Qt.rgba(0, 0, 0, 0.08)
                border.color: Qt.rgba(1, 1, 1, 0.08)
                border.width: 1
                implicitHeight: pairCol.implicitHeight + PlasmaCore.Units.mediumSpacing * 2

                ColumnLayout {
                    id: pairCol
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
                            objectName: windowsSection.namePrefix + "QuotaTrack"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            height: 8
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.12)
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                objectName: windowsSection.namePrefix + "QuotaFill"
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: pair.live && modelData.left_percent > 0 ? Math.max(parent.height, parent.width * (Math.min(100, modelData.left_percent) / 100.0)) : 0
                                radius: 4
                                color: pair.quotaColor
                            }
                        }

                        PlasmaComponents.Label {
                            objectName: windowsSection.namePrefix + "QuotaValue"
                            text: pair.live ? modelData.left_percent + "% " + i18n("left") : "—"
                            font.bold: true
                            font.pointSize: PlasmaCore.Theme.defaultFont.pointSize
                            color: pair.quotaColor
                            horizontalAlignment: Text.AlignRight
                            Layout.preferredWidth: PlasmaCore.Units.gridUnit * 4.5
                            Layout.minimumWidth: 0
                            Layout.maximumWidth: Layout.preferredWidth
                            elide: Text.ElideRight
                            maximumLineCount: 1
                            Layout.alignment: Qt.AlignVCenter
                        }
                    }

                    // Row 2: Time Remaining in this window
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
                            objectName: windowsSection.namePrefix + "TimeTrack"
                            Layout.fillWidth: true
                            Layout.minimumWidth: 0
                            height: 8
                            radius: 4
                            color: Qt.rgba(1, 1, 1, 0.12)
                            Layout.alignment: Qt.AlignVCenter

                            Rectangle {
                                objectName: windowsSection.namePrefix + "TimeFill"
                                anchors.left: parent.left
                                anchors.top: parent.top
                                anchors.bottom: parent.bottom
                                width: pair.live && modelData.time_left_percent > 0 ? Math.max(parent.height, parent.width * (Math.min(100, modelData.time_left_percent) / 100.0)) : 0
                                radius: 4
                                color: PlasmaCore.Theme.highlightColor
                            }
                        }

                        PlasmaComponents.Label {
                            objectName: windowsSection.namePrefix + "TimeValue"
                            text: pair.live ? modelData.time_left_text : "—"
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
        }
    }
}
