import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore

// Popup: Codex, Claude and Antigravity sections shown together, each with its own header and refresh.
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

        WindowsSection {
            objectName: "claudeSection"
            namePrefix: "claude"
            controller: root.claude
            iconSource: Qt.resolvedUrl("../icons/claude.svg")
            title: i18n("Claude Usage")
            placeholderWindows: [
                {id: "session", label: i18n("Session (5h)")},
                {id: "weekly", label: i18n("Weekly")}
            ]
        }

        Rectangle {
            objectName: "agyDivider"
            Layout.fillWidth: true
            height: 1
            color: Qt.rgba(1, 1, 1, 0.15)
        }

        WindowsSection {
            objectName: "agySection"
            namePrefix: "agy"
            controller: root.agy
            iconSource: Qt.resolvedUrl("../icons/antigravity.svg")
            title: i18n("Antigravity Usage")
            placeholderWindows: [
                {id: "gemini_5h", label: i18n("Gemini · 5h")},
                {id: "gemini_weekly", label: i18n("Gemini · Weekly")},
                {id: "argon_weekly", label: i18n("Argon · Weekly")}
            ]
        }
    }
}
