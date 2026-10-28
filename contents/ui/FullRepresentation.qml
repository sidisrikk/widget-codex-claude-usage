import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore

// Popup: Codex and Claude sections shown together, each with its own header and refresh.
Item {
    id: fullRoot

    Layout.minimumWidth: PlasmaCore.Units.gridUnit * 18
    Layout.minimumHeight: mainCol.implicitHeight + PlasmaCore.Units.largeSpacing * 2
    Layout.preferredWidth: Layout.minimumWidth
    Layout.preferredHeight: Layout.minimumHeight
    implicitWidth: Layout.preferredWidth
    implicitHeight: Layout.preferredHeight

    ColumnLayout {
        id: mainCol
        anchors.fill: parent
        anchors.margins: PlasmaCore.Units.largeSpacing
        spacing: PlasmaCore.Units.largeSpacing

        CodexSection {
            objectName: "codexSection"
        }

        Rectangle {
            objectName: "sectionDivider"
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(1, 1, 1, 0.15)
        }

        ClaudeSection {
            objectName: "claudeSection"
        }
    }
}
