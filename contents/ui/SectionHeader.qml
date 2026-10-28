import QtQuick 2.15
import QtQuick.Layouts 1.15
import QtQuick.Controls 2.15 as QQC2
import org.kde.plasma.core 2.0 as PlasmaCore
import org.kde.plasma.components 3.0 as PlasmaComponents

// Fixed-height provider header: [logo] Title … status [⟳]. Both buttons refresh only this provider.
RowLayout {
    id: header

    property var controller
    property url iconSource
    property string title
    property string namePrefix

    objectName: namePrefix + "Header"
    Layout.fillWidth: true
    Layout.minimumHeight: PlasmaCore.Units.gridUnit * 2
    Layout.maximumHeight: Layout.minimumHeight
    spacing: PlasmaCore.Units.smallSpacing

    readonly property string refreshHint: controller.isRefreshing ? i18n("Refreshing…")
        : (controller.serverCooldownSeconds > 0
            ? i18n("Server cooldown: refresh available in %1 seconds", controller.serverCooldownSeconds)
            : i18n("Refresh %1 manually (retry backoff can be overridden)", header.title))

    PlasmaComponents.ToolButton {
        id: titleIcon
        objectName: header.namePrefix + "TitleIcon"
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: PlasmaCore.Units.iconSizes.smallMedium + PlasmaCore.Units.smallSpacing * 2
        Layout.preferredHeight: Layout.preferredWidth
        text: i18n("Refresh %1", header.title)
        enabled: header.controller.canRefresh
        onClicked: header.controller.refreshUsage()

        contentItem: Item {
            implicitWidth: PlasmaCore.Units.iconSizes.smallMedium
            implicitHeight: implicitWidth
            Image {
                anchors.fill: parent
                source: header.iconSource
                sourceSize.width: width * 2
                sourceSize.height: height * 2
                fillMode: Image.PreserveAspectFit
                smooth: true
                mipmap: true
            }
        }

        PlasmaComponents.ToolTip {
            objectName: header.namePrefix + "TitleTooltip"
            text: header.refreshHint
            visible: titleIcon.hovered || titleIcon.activeFocus
        }
    }

    PlasmaComponents.Label {
        objectName: header.namePrefix + "Title"
        text: header.title
        font.bold: true
        Layout.minimumWidth: implicitWidth
    }

    Item {
        id: headerStatus
        objectName: header.namePrefix + "HeaderStatus"
        Layout.fillWidth: true
        Layout.minimumWidth: 0
        Layout.fillHeight: true
        activeFocusOnTab: true
        Accessible.role: Accessible.StaticText
        Accessible.name: header.controller.statusSummary
        Accessible.description: header.controller.statusDetails

        RowLayout {
            objectName: header.namePrefix + "HeaderStatusContent"
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            width: Math.min(parent.width, implicitWidth)
            height: parent.height
            spacing: PlasmaCore.Units.smallSpacing

            PlasmaCore.IconItem {
                Layout.preferredWidth: PlasmaCore.Units.iconSizes.small
                Layout.preferredHeight: Layout.preferredWidth
                source: header.controller.isRefreshing ? "view-refresh"
                    : (header.controller.needsSignIn ? "dialog-password"
                        : (header.controller.status === "offline" ? "network-disconnect"
                            : (header.controller.serverCooldownSeconds > 0 || header.controller.isRetryWaiting ? "chronometer"
                                : (header.controller.status === "ok" && header.controller.hasData ? "dialog-ok-apply" : "dialog-warning"))))
                colorGroup: PlasmaCore.Theme.NormalColorGroup
            }

            PlasmaComponents.Label {
                objectName: header.namePrefix + "StatusSummary"
                text: header.controller.statusSummary
                Layout.fillWidth: true
                Layout.minimumWidth: 0
                font.pointSize: PlasmaCore.Theme.smallestFont.pointSize
                horizontalAlignment: Text.AlignRight
                elide: Text.ElideRight
                maximumLineCount: 1
                color: header.controller.needsSignIn ? "#e74c3c"
                    : (header.controller.isRefreshing ? PlasmaCore.Theme.highlightColor
                        : (header.controller.status !== "ok" || !header.controller.hasData || header.controller.serverCooldownSeconds > 0 ? "#f39c12" : PlasmaCore.Theme.textColor))
            }
        }

        MouseArea {
            id: statusHover
            anchors.fill: parent
            hoverEnabled: true
            acceptedButtons: Qt.NoButton
        }

        PlasmaComponents.ToolTip {
            objectName: header.namePrefix + "StatusTooltip"
            text: header.controller.statusSummary + "\n" + header.controller.statusDetails
            visible: statusHover.containsMouse || headerStatus.activeFocus
        }
    }

    PlasmaComponents.ToolButton {
        id: refreshButton
        objectName: header.namePrefix + "Refresh"
        Layout.alignment: Qt.AlignVCenter
        Layout.preferredWidth: PlasmaCore.Units.iconSizes.small + PlasmaCore.Units.smallSpacing * 2
        Layout.preferredHeight: Layout.preferredWidth
        icon.name: "view-refresh"
        display: QQC2.AbstractButton.IconOnly
        text: i18n("Refresh %1", header.title)
        enabled: header.controller.canRefresh
        onClicked: header.controller.refreshUsage()

        PlasmaComponents.ToolTip {
            objectName: header.namePrefix + "RefreshTooltip"
            text: header.refreshHint
            visible: refreshButton.hovered || refreshButton.activeFocus
        }
    }
}
