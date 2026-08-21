import QtQuick 2.15
import "qrc:/app/resources/qml/components/timeline"

Rectangle {
    id: trackBg
    height: 40
    color: "#1A1A1A"
    radius: 3
    border.color: "#333"
    border.width: 1
    clip: true

    property var timeline: null
    property real minMotion: 15

    signal seekRequested(real tsMs)
    signal hoverTimeChanged(real tsMs)
    property alias panActive: panHandler.active

    TimelineSegments {
        anchors.fill: parent
        recordings: timeline ? timeline.recordings : []
        startTs: timeline ? timeline.effectiveStartTs() : 0
        endTs: timeline ? timeline.effectiveEndTs() : 0
        zoom: 1.0
        pan: 0
        timelineWidth: trackBg.width
        timestampToX: timeline ? timeline.timestampToX : function(t) { return 0 }
        z: 1
    }

    Repeater {
        model: timeline ? timeline.motionPoints : []
        z: 5

        Rectangle {
            property real sec: {
                var t = 0
                if (typeof start !== "undefined" && start)
                    t = Number(start)
                else if (modelData)
                    t = Number(modelData.start || modelData.start_time || 0)
                if (t > 100000000000)
                    t = t / 1000
                return t
            }
            property real mot: {
                if (typeof motion !== "undefined" && motion)
                    return Number(motion)
                if (modelData)
                    return Number(modelData.motion || 0)
                return 0
            }

            width: 3
            height: Math.min(parent.height - 4, 14 + Math.min(22, mot / 8.0))
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 2
            color: "#FF6D00"
            x: timeline ? timeline.timestampToX(sec * 1000) - 1 : 0
            visible: timeline && sec > 0 && mot >= minMotion
                     && sec >= timeline.effectiveStartTs()
                     && sec <= timeline.effectiveEndTs()
        }
    }

    Repeater {
        model: timeline ? timeline.events : []
        z: 6

        Rectangle {
            property real sec: {
                var t = 0
                if (typeof start !== "undefined" && start)
                    t = Number(start)
                else if (modelData)
                    t = Number(modelData.start || 0)
                if (t > 100000000000)
                    t = t / 1000
                return t
            }

            width: 3
            height: 18
            y: 2
            radius: 1
            color: "#FFC107"
            x: timeline ? timeline.timestampToX(sec * 1000) - 1 : 0
            visible: timeline && sec > 0
                     && sec >= timeline.effectiveStartTs()
                     && sec <= timeline.effectiveEndTs()
        }
    }

    Rectangle {
        width: 3
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        x: timeline ? timeline.timestampToX(timeline.playheadTsMs) - width / 2 : 0
        color: (timeline && timeline.isPlayback) ? "#FFFFFF" : "#90CAF9"
        border.color: "#000000"
        border.width: 1
        visible: timeline && timeline.playheadTsMs > 0
        z: 80
    }

    WheelHandler {
        acceptedDevices: PointerDevice.Mouse | PointerDevice.TouchPad
        onWheel: function(event) {
            if (!timeline)
                return
            var factor = event.angleDelta.y > 0 ? 1.25 : 0.8
            timeline.zoomAt(event.x, factor)
            event.accepted = true
        }
    }

    DragHandler {
        id: panHandler
        acceptedButtons: Qt.LeftButton
        acceptedModifiers: Qt.ShiftModifier
        target: null
        property real lastX: 0
        onActiveChanged: {
            if (active)
                lastX = centroid.position.x
        }
        onTranslationChanged: {
            if (!active || !timeline)
                return
            var dx = centroid.position.x - lastX
            lastX = centroid.position.x
            if (Math.abs(dx) > 0.5)
                timeline.panByPixels(dx)
        }
    }

    TapHandler {
        acceptedButtons: Qt.LeftButton
        onDoubleTapped: {
            if (timeline)
                timeline.resetZoom()
        }
    }

    TimelineMouseHandler {
        anchors.fill: parent
        z: 50
        scrubber: null
        hoverPreview: null
        pan: 0
        xToTimestamp: function(x) {
            return timeline ? timeline.xToTimestamp(x) : 0
        }
        trackHeight: trackBg.height
        enabled: !panHandler.active

        onSeekRequested: function(tsMs) {
            trackBg.seekRequested(tsMs)
        }
        onHoverTimeChanged: function(tsMs) {
            trackBg.hoverTimeChanged(tsMs)
        }
    }
}