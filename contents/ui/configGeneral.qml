import QtQuick 2.15
import QtQuick.Controls 2.15
import org.kde.kirigami 2.5 as Kirigami
import org.kde.plasma.core 2.0 as PlasmaCore

Kirigami.FormLayout {
    id: root

    property alias cfg_refreshInterval: intervalSpinBox.value
    property alias cfg_showPercentageLeft: showLeftCheckBox.checked
    property alias cfg_warningThreshold: warningSpinBox.value

    anchors {
        left: parent.left
        right: parent.right
    }

    CheckBox {
        id: showLeftCheckBox
        Kirigami.FormData.label: i18n("Display:")
        text: i18n("Show percentage remaining (uncheck to show percentage used)")
    }

    SpinBox {
        id: intervalSpinBox
        Kirigami.FormData.label: i18n("Refresh interval (seconds):")
        from: 60
        to: 86400
        stepSize: 60
        editable: true
    }

    Label {
        text: i18n("Default: 600s (10 minutes). Minimum: 60s.")
        font: PlasmaCore.Theme.smallestFont
        opacity: 0.7
    }

    SpinBox {
        id: warningSpinBox
        Kirigami.FormData.label: i18n("Low quota alert threshold (%):")
        from: 1
        to: 50
        stepSize: 5
        editable: true
    }

    Label {
        text: i18n("Highlights the badge in red when remaining weekly % drops below this value.")
        font: PlasmaCore.Theme.smallestFont
        opacity: 0.7
    }
}
