import QtQuick 2.15
import QtQuick.Controls 2.15
import "qrc:/app/resources/qml/components"

Item {
    id: segments

    signal refreshRequested()

    property var recordings: []
    property var timeline: null
    property real viewStart: 0
    property real viewEnd: 0
    property real contentWidth: 1
    // In live-follow mode the last cached segment can lag the live edge while
    // a refresh is in flight. Extend it visually to "now" and mark that tail
    // as estimated rather than as confirmed recording data.
    property bool fillToNow: false
    property real nowSec: 0
    property real iconPulse: 0.5

    readonly property bool hasValidView: viewStart >= 0 && viewEnd > viewStart
    readonly property real barHeight: Math.max(8, segments.height * 0.35)
    readonly property real barY: segments.height - barHeight - 2

    readonly property real realEndSec: {
        var list = recordings || []
        var maxEnd = 0
        for (var i = 0; i < list.length; i++) {
            var e = Number(list[i].end)
            if (isFinite(e) && e > maxEnd)
                maxEnd = e
        }
        return maxEnd
    }

    readonly property bool projecting: fillToNow && nowSec > 0 && realEndSec > 0
                                       && realEndSec >= viewStart && realEndSec < nowSec

    Timer {
        interval: 5000
        repeat: true
        running: segments.fillToNow
        onTriggered: segments.nowSec = Date.now() / 1000
    }

    NumberAnimation on iconPulse {
        from: 0.65
        to: 1.0
        duration: 900
        loops: Animation.Infinite
        running: segments.projecting
    }

    Component.onCompleted: nowSec = Date.now() / 1000

    function mapX(tsMs) {
        var s = viewStart
        var e = viewEnd
        var w = Math.max(1, contentWidth)
        if (!hasValidView)
            return 0
        var ratio = (tsMs - s * 1000) / ((e - s) * 1000)
        return Math.max(0, Math.min(w, ratio * w))
    }

    Repeater {
        model: segments.recordings

        Rectangle {
            id: segment
            property real recordingStart: {
                var start = Number(modelData.start)
                return isFinite(start) && start >= 0 ? start : 0
            }
            property real recordingEnd: {
                var end = Number(modelData.end)
                if (!isFinite(end) || end <= 0)
                    return recordingStart
                if (segments.fillToNow && segments.nowSec > 0
                        && end >= segments.viewStart && end < segments.nowSec)
                    end = segments.nowSec
                return end
            }
            property real segmentX1: segments.mapX(recordingStart * 1000)
            property real segmentX2: segments.mapX(recordingEnd * 1000)

            height: segments.barHeight
            y: segments.barY
            width: Math.max(2, segmentX2 - segmentX1)
            x: segmentX1
            radius: 1
            color: NxStyle.recording
            opacity: 0.85
            visible: segments.hasValidView && recordingEnd > recordingStart && segmentX2 >= segmentX1
        }
    }

    // Estimated tail: hatched, tinted, with a pulsing refresh icon.
    Rectangle {
        visible: segments.projecting && segments.hasValidView
        x: segments.mapX(segments.realEndSec * 1000)
        y: segments.barY
        width: Math.max(0, segments.mapX(segments.nowSec * 1000) - x)
        height: segments.barHeight
        radius: 1
        color: "#2E7D3244"
        border.color: "#81C784"
        border.width: 1
        z: 2

        Canvas {
            anchors.fill: parent
            opacity: 0.55
            onPaint: {
                var ctx = getContext("2d")
                ctx.reset()
                ctx.strokeStyle = "#A5D6A7"
                ctx.lineWidth = 1
                for (var x = -height; x < width + height; x += 8) {
                    ctx.beginPath()
                    ctx.moveTo(x, height)
                    ctx.lineTo(x + height, 0)
                    ctx.stroke()
                }
            }
            onWidthChanged: requestPaint()
            onHeightChanged: requestPaint()
        }

        // Badge sits at the start of the estimated tail so it is never
        // clipped by the right edge of the timeline.
        Rectangle {
            anchors.left: parent.left
            anchors.leftMargin: 2
            anchors.verticalCenter: parent.verticalCenter
            width: 24
            height: 18
            radius: 2
            color: "#1B5E20"
            border.color: "#A5D6A7"
            border.width: 1
            visible: parent.width > 30
            z: 3

            Image {
                anchors.centerIn: parent
                width: 14
                height: 14
                fillMode: Image.PreserveAspectFit
                source: "qrc:/app/assets/icons/nx/refresh.svg"
                opacity: segments.iconPulse
            }

            ToolTip.visible: badgeMouse.containsMouse
            ToolTip.text: "Estimated end — click to refresh recording data"
            ToolTip.delay: 300

            MouseArea {
                id: badgeMouse
                anchors.fill: parent
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: segments.refreshRequested()
            }
        }
    }
}
