import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: timeline
    height: 60
    width: parent.width
    color: "#000000AA"

    //
    // Provided by CameraGrid
    //
    property var frigateRef
    property string cameraId: ""
    property var events: []
    property var recordings: []
    property real position: 0
    property int playbackPositionMs: 0

    //
    // Backend updates
    //
    Connections {
        target: frigateRef
        ignoreUnknownSignals: true

        function onEventsLoaded(camId, ev) {
            if (camId !== cameraId) return
            events = ev
        }

        function onRecordingsLoaded(camId, rec) {
            if (camId !== cameraId) return
            recordings = rec
        }

        function onPlaybackPositionChanged(camId, posMs) {
            if (camId !== cameraId) return
            playbackPositionMs = posMs
            position = posMs   // simple timeline uses raw ms
        }
    }

    //
    // Simple event bar
    //
    Row {
        anchors.fill: parent
        spacing: 4

        Repeater {
            model: events.length

            Rectangle {
                width: 4
                height: parent.height
                color: "red"
            }
        }
    }
}
