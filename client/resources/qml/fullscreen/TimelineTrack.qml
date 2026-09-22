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

    property bool panActive: false

    TimelineSegments {
        anchors.fill: parent
        recordings: timeline ? timeline.recordings : []
        startTs: timeline ? timeline.effectiveStartTs() : 0
        endTs: timeline ? timeline.effectiveEndTs() : 0
        zoom: 1.0
        pan: 0
        timelineWidth: timeline ? Math.max(1, timeline.width - 8) : width
        timestampToX: timeline ? timeline.timestampToX : function(t) { return 0 }
        z: 1
    }

    Repeater {
        model: timeline ? timeline.motionPoints : []
        z: 5
        Rectangle {
            property real sec: {
                var t = 0
                if (modelData)
                    t = Number(modelData.start || modelData.start_time || 0)
                if (t > 100000000000)
                    t = t / 1000
                return t
            }
            property real mot: modelData ? Number(modelData.motion || 0) : 0
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
                var t = modelData ? Number(modelData.start || 0) : 0
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

    // Export selection highlight
    Rectangle {
        z: 15
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        color: "#3A6AFF55"
        border.color: "#6A8AFF"
        border.width: 1
        visible: timeline && timeline.exportStartMs > 0
                 && timeline.exportEndMs > timeline.exportStartMs
        x: visible ? timeline.timestampToX(timeline.exportStartMs) : 0
        width: visible
               ? Math.max(2, timeline.timestampToX(timeline.exportEndMs)
                            - timeline.timestampToX(timeline.exportStartMs))
               : 0
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

    // Single mouse area: click = seek, drag = export range, Shift+drag = pan
    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton
        preventStealing: true
        z: 50

        property real pressX: 0
        property real lastX: 0
        property bool dragging: false
        property bool panning: false
        property real dragThreshold: 6

        onPositionChanged: function(event) {
            if (!timeline)
                return

            var ts = timeline.xToTimestamp(event.x)
            trackBg.hoverTimeChanged(ts)

            if (!(event.buttons & Qt.LeftButton))
                return

            var dx = event.x - pressX

            // Shift held → pan
            if (event.modifiers & Qt.ShiftModifier) {
                panning = true
                dragging = false
                trackBg.panActive = true
                var step = event.x - lastX
                lastX = event.x
                if (Math.abs(step) > 0.5)
                    timeline.panByPixels(step)
                return
            }

            // Drag far enough → range select
            if (!dragging && Math.abs(dx) >= dragThreshold) {
                dragging = true
                var startTs = timeline.xToTimestamp(pressX)
                timeline.exportStartMs = startTs
                timeline.exportEndMs = startTs
            }

            if (dragging) {
                timeline.exportEndMs = timeline.xToTimestamp(event.x)
            }
        }

        onPressed: function(event) {
            pressX = event.x
            lastX = event.x
            dragging = false
            panning = false
            trackBg.panActive = false
        }

        onReleased: function(event) {
            if (!timeline) {
                dragging = false
                panning = false
                trackBg.panActive = false
                return
            }

            if (panning) {
                panning = false
                trackBg.panActive = false
                return
            }

            if (dragging) {
                // Normalize start/end
                if (timeline.exportEndMs < timeline.exportStartMs) {
                    var tmp = timeline.exportStartMs
                    timeline.exportStartMs = timeline.exportEndMs
                    timeline.exportEndMs = tmp
                }
                // Tiny drag = ignore
                if (timeline.exportEndMs - timeline.exportStartMs < 2000) {
                    timeline.exportStartMs = -1
                    timeline.exportEndMs = -1
                }
                dragging = false
                return
            }

            // Click = seek
            var ts = timeline.xToTimestamp(event.x)
            if (ts > 0)
                trackBg.seekRequested(ts)
        }

        onExited: {
            trackBg.hoverTimeChanged(-1)
        }

        onDoubleClicked: {
            if (timeline)
                timeline.resetZoom()
        }
    }
}