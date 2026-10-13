import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.plasmoid 2.0
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents
import org.kde.kirigami 2.5 as Kirigami

MouseArea {
    id: compactRoot

    readonly property bool isVertical: Plasmoid.formFactor === PlasmaCore.Types.Vertical
    readonly property int displayPercent: !root.hasData ? 0 : (Plasmoid.configuration.showPercentageLeft ? root.leftPercent : root.usedPercent)
    readonly property color themeColor: root.getStatusColor()

    hoverEnabled: true
    activeFocusOnTab: true
    cursorShape: Qt.PointingHandCursor

    PlasmaComponents.ToolTip {
        text: root.noticeText
        visible: compactRoot.containsMouse && (root.status !== "ok" || !root.hasData || root.isRefreshing)
    }

    onClicked: {
        Plasmoid.expanded = !Plasmoid.expanded
    }

    Layout.minimumWidth: isVertical ? PlasmaCore.Units.gridUnit * 2 : contentRow.implicitWidth + PlasmaCore.Units.smallSpacing * 2
    Layout.minimumHeight: isVertical ? contentCol.implicitHeight + PlasmaCore.Units.smallSpacing * 2 : PlasmaCore.Units.gridUnit * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight

    // Horizontal panel representation
    RowLayout {
        id: contentRow
        visible: !compactRoot.isVertical
        anchors.centerIn: parent
        spacing: PlasmaCore.Units.smallSpacing

        // Mini Circular Gauge Meter
        Item {
            Layout.preferredWidth: PlasmaCore.Units.iconSizes.small + 6
            Layout.preferredHeight: PlasmaCore.Units.iconSizes.small + 6
            Layout.alignment: Qt.AlignVCenter

            Canvas {
                id: miniRingH
                anchors.fill: parent
                antialiasing: true

                property real percent: compactRoot.displayPercent
                property color ringColor: compactRoot.themeColor

                onPercentChanged: requestPaint()
                onRingColorChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();

                    var cx = width / 2;
                    var cy = height / 2;
                    var r = Math.min(width, height) / 2 - 2;

                    // Background track
                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI, false);
                    ctx.lineWidth = 2.5;
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15);
                    ctx.stroke();

                    // Progress arc
                    var startAngle = -0.5 * Math.PI;
                    var fraction = Math.max(0, Math.min(100, percent)) / 100.0;
                    if (fraction > 0) {
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, startAngle, startAngle + (2 * Math.PI * fraction), false);
                        ctx.lineWidth = 2.5;
                        ctx.strokeStyle = ringColor;
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }
                }
            }

            Image {
                source: Qt.resolvedUrl("../icons/codex.png")
                anchors.centerIn: parent
                width: PlasmaCore.Units.iconSizes.small - 4
                height: PlasmaCore.Units.iconSizes.small - 4
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }

        // Percentage text badge
        Rectangle {
            visible: root.hasData
            Layout.alignment: Qt.AlignVCenter
            implicitWidth: textH.implicitWidth + PlasmaCore.Units.smallSpacing * 2
            implicitHeight: textH.implicitHeight + PlasmaCore.Units.smallSpacing / 2
            radius: height / 2
            color: Qt.rgba(compactRoot.themeColor.r, compactRoot.themeColor.g, compactRoot.themeColor.b, 0.15)
            border.color: compactRoot.themeColor
            border.width: 1

            PlasmaComponents.Label {
                id: textH
                anchors.centerIn: parent
                text: compactRoot.displayPercent + "%"
                font.bold: true
                font.pointSize: PlasmaCore.Theme.smallestFont.pointSize
                color: PlasmaCore.Theme.textColor
            }
        }
    }

    // Vertical panel representation
    ColumnLayout {
        id: contentCol
        visible: compactRoot.isVertical
        anchors.centerIn: parent
        spacing: 2

        Item {
            Layout.preferredWidth: PlasmaCore.Units.iconSizes.small + 6
            Layout.preferredHeight: PlasmaCore.Units.iconSizes.small + 6
            Layout.alignment: Qt.AlignHCenter

            Canvas {
                id: miniRingV
                anchors.fill: parent
                antialiasing: true

                property real percent: compactRoot.displayPercent
                property color ringColor: compactRoot.themeColor

                onPercentChanged: requestPaint()
                onRingColorChanged: requestPaint()

                onPaint: {
                    var ctx = getContext("2d");
                    ctx.reset();

                    var cx = width / 2;
                    var cy = height / 2;
                    var r = Math.min(width, height) / 2 - 2;

                    ctx.beginPath();
                    ctx.arc(cx, cy, r, 0, 2 * Math.PI, false);
                    ctx.lineWidth = 2.5;
                    ctx.strokeStyle = Qt.rgba(1, 1, 1, 0.15);
                    ctx.stroke();

                    var startAngle = -0.5 * Math.PI;
                    var fraction = Math.max(0, Math.min(100, percent)) / 100.0;
                    if (fraction > 0) {
                        ctx.beginPath();
                        ctx.arc(cx, cy, r, startAngle, startAngle + (2 * Math.PI * fraction), false);
                        ctx.lineWidth = 2.5;
                        ctx.strokeStyle = ringColor;
                        ctx.lineCap = "round";
                        ctx.stroke();
                    }
                }
            }

            Image {
                source: Qt.resolvedUrl("../icons/codex.png")
                anchors.centerIn: parent
                width: PlasmaCore.Units.iconSizes.small - 4
                height: PlasmaCore.Units.iconSizes.small - 4
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }

        PlasmaComponents.Label {
            visible: root.hasData
            text: compactRoot.displayPercent + "%"
            font.bold: true
            font.pointSize: PlasmaCore.Theme.smallestFont.pointSize
            color: compactRoot.themeColor
            Layout.alignment: Qt.AlignHCenter
        }
    }
}
