import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents

MouseArea {
    id: compactRoot

    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property var gauges: [
        {usage: root.codex, icon: Qt.resolvedUrl("../icons/codex.png")},
        {usage: root.claude, icon: Qt.resolvedUrl("../icons/claude.svg")}
    ]
    readonly property bool showNotice: root.providers.some(function(usage) {
        return usage.status !== "ok" || !usage.hasData || usage.isRefreshing;
    })

    function displayPercent(usage) {
        return !usage.hasData ? 0 : (Plasmoid.configuration.showPercentageLeft ? usage.leftPercent : usage.usedPercent);
    }

    hoverEnabled: true
    activeFocusOnTab: true
    cursorShape: Qt.PointingHandCursor

    PlasmaComponents.ToolTip {
        text: root.providers.map(function(usage) { return usage.displayName + ": " + usage.noticeText; }).join("\n")
        visible: compactRoot.containsMouse && compactRoot.showNotice
    }

    onClicked: {
        Plasmoid.expanded = !Plasmoid.expanded
    }

    Layout.minimumWidth: isVertical ? PlasmaCore.Units.gridUnit * 2 : contentGrid.implicitWidth + PlasmaCore.Units.smallSpacing * 2
    Layout.minimumHeight: isVertical ? contentGrid.implicitHeight + PlasmaCore.Units.smallSpacing * 2 : PlasmaCore.Units.gridUnit * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight

    // One ring + percentage per provider: side by side on horizontal panels, stacked on vertical ones.
    GridLayout {
        id: contentGrid
        anchors.centerIn: parent
        flow: compactRoot.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        rows: compactRoot.isVertical ? compactRoot.gauges.length : 1
        columnSpacing: PlasmaCore.Units.smallSpacing * 2
        rowSpacing: PlasmaCore.Units.smallSpacing

        Repeater {
            model: compactRoot.gauges

            delegate: GridLayout {
                id: gauge
                objectName: "compactGauge"
                readonly property var usage: modelData.usage
                readonly property int displayPercent: compactRoot.displayPercent(usage)
                readonly property color themeColor: usage.getStatusColor()
                flow: compactRoot.isVertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
                columnSpacing: PlasmaCore.Units.smallSpacing
                rowSpacing: 2
                Layout.alignment: Qt.AlignCenter

                UsageRing {
                    percent: gauge.displayPercent
                    ringColor: gauge.themeColor
                    iconSource: modelData.icon
                    Layout.alignment: Qt.AlignCenter
                }

                // Percentage text badge (horizontal panels)
                Rectangle {
                    visible: !compactRoot.isVertical && gauge.usage.hasData
                    Layout.alignment: Qt.AlignVCenter
                    implicitWidth: badgeText.implicitWidth + PlasmaCore.Units.smallSpacing * 2
                    implicitHeight: badgeText.implicitHeight + PlasmaCore.Units.smallSpacing / 2
                    radius: height / 2
                    color: Qt.rgba(gauge.themeColor.r, gauge.themeColor.g, gauge.themeColor.b, 0.15)
                    border.color: gauge.themeColor
                    border.width: 1

                    PlasmaComponents.Label {
                        id: badgeText
                        objectName: "compactPercent"
                        anchors.centerIn: parent
                        text: gauge.displayPercent + "%"
                        font.bold: true
                        font.pointSize: PlasmaCore.Theme.smallestFont.pointSize
                        color: PlasmaCore.Theme.textColor
                    }
                }

                // Percentage label (vertical panels)
                PlasmaComponents.Label {
                    visible: compactRoot.isVertical && gauge.usage.hasData
                    text: gauge.displayPercent + "%"
                    font.bold: true
                    font.pointSize: PlasmaCore.Theme.smallestFont.pointSize
                    color: gauge.themeColor
                    Layout.alignment: Qt.AlignHCenter
                }
            }
        }
    }
}
