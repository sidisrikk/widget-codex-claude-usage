import QtQuick 2.15
import QtQuick.Layouts 1.15
import org.kde.plasma.core 2.0 as PlasmaCore

// Mini circular gauge with the provider logo in the middle.
Item {
    id: ring

    property real percent: 0
    property color ringColor: PlasmaCore.Theme.highlightColor
    property url iconSource

    Layout.preferredWidth: PlasmaCore.Units.iconSizes.small + 6
    Layout.preferredHeight: PlasmaCore.Units.iconSizes.small + 6

    Canvas {
        anchors.fill: parent
        antialiasing: true

        property real percent: ring.percent
        property color ringColor: ring.ringColor

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
        source: ring.iconSource
        anchors.centerIn: parent
        width: PlasmaCore.Units.iconSizes.small - 4
        height: PlasmaCore.Units.iconSizes.small - 4
        sourceSize.width: width * 2
        sourceSize.height: height * 2
        fillMode: Image.PreserveAspectFit
        smooth: true
        mipmap: true
    }
}
