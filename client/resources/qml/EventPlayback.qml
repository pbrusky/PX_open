import QtQuick 2.15
import QtQuick.Controls 2.15
import QtMultimedia 6.5

Rectangle {
    id: root
    anchors.fill: parent
    color: "black"
    objectName: "EventPlayback"
    focus: true

    property var eventData: mainWindow.eventPlaybackData
    property bool uiVisible: true
    property string statusMessage: "Loading clip…"

    function exitPlayback() {
        if (player.playbackState === MediaPlayer.PlayingState
                || player.playbackState === MediaPlayer.PausedState)
            player.stop()
        if (mainWindow && typeof mainWindow.closeEventPlayback === "function")
            mainWindow.closeEventPlayback()
        else if (mainWindow && typeof mainWindow.goToServerView === "function")
            mainWindow.goToServerView()
        else if (mainWindow && mainWindow.contentLoader)
            mainWindow.contentLoader.source = "qrc:/app/resources/qml/components/ServerView.qml"
    }

    function fallbackFfmpegPlayback() {
        if (!eventData || !mainWindow || !mainWindow.frigateRef)
            return
        var cam = eventData.camera || ""
        var startSec = Number(eventData.start || 0)
        if (!cam.length || startSec <= 0)
            return

        statusMessage = "MediaPlayer failed — using FFmpeg…"
        if (typeof mainWindow.frigateRef.startPlayback === "function")
            mainWindow.frigateRef.startPlayback(cam, Math.floor(startSec * 1000))

        if (mainWindow.fullscreenManager) {
            var q = null
            if (typeof mainWindow.frigateRef.getQueue === "function")
                q = mainWindow.frigateRef.getQueue(cam)
            mainWindow.fullscreenManager.open(cam, q)
        }
        // leave EventPlayback page after opening fullscreen
        Qt.callLater(exitPlayback)
    }

    Timer {
        id: hideTimer
        interval: 2500
        repeat: false
        onTriggered: root.uiVisible = false
    }

    MediaPlayer {
        id: player
        source: (eventData && eventData.clipUrl) ? eventData.clipUrl : ""
        videoOutput: videoOut
        audioOutput: AudioOutput {}

        // formal function — avoids the "Parameter source is not declared" warning
        onSourceChanged: function() {
            if (source && source.toString().length) {
                console.log("EventPlayback: source =", source)
                statusMessage = "Loading clip…"
                play()
            }
        }

        onErrorOccurred: function(error, errorString) {
            console.log("EventPlayback error:", error, errorString)
            statusMessage = "Could not open clip (MediaPlayer). Falling back…"
            fallbackFfmpegPlayback()
        }

        onPlaybackStateChanged: function() {
            if (playbackState === MediaPlayer.PlayingState)
                statusMessage = "Playing event clip"
            else if (playbackState === MediaPlayer.PausedState)
                statusMessage = "Paused"
        }
    }

    Component.onCompleted: {
        forceActiveFocus()
        hideTimer.restart()
        if (eventData && eventData.clipUrl) {
            console.log("EventPlayback: starting clip:", eventData.clipUrl)
            player.play()
        } else {
            statusMessage = "No clip URL"
            console.log("EventPlayback: NO CLIP URL")
        }
    }

    VideoOutput {
        id: videoOut
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onClicked: root.exitPlayback()
        onPositionChanged: {
            root.uiVisible = true
            hideTimer.restart()
        }
    }

    Keys.onEscapePressed: root.exitPlayback()

    Rectangle {
        id: topBar
        height: 50
        width: parent.width
        color: "#00000088"
        anchors.top: parent.top
        opacity: root.uiVisible ? 1 : 0
        z: 10
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 20

            Rectangle {
                width: 32
                height: 32
                radius: 4
                color: closeArea.containsMouse ? "#444" : "#00000088"
                Image {
                    anchors.centerIn: parent
                    source: "qrc:/app/assets/icons/nx/exit_fullscreen.svg"
                    width: 22
                    height: 22
                }
                MouseArea {
                    id: closeArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: root.exitPlayback()
                }
            }

            Column {
                spacing: 2
                anchors.verticalCenter: parent.verticalCenter
                Text {
                    text: {
                        if (!eventData) return "Unknown Camera"
                        var cam = eventData.camera || "Unknown Camera"
                        var lab = eventData.label || ""
                        return lab.length ? (cam + "  ·  " + lab) : cam
                    }
                    color: "white"
                    font.pixelSize: 18
                    font.bold: true
                }
                Text {
                    text: eventData ? (eventData.timestamp || "") : ""
                    color: "#ccc"
                    font.pixelSize: 13
                }
            }
        }
    }

    Rectangle {
        height: 56
        width: parent.width
        anchors.bottom: parent.bottom
        color: "#00000088"
        opacity: root.uiVisible ? 1 : 0
        z: 10
        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.centerIn: parent
            text: root.statusMessage
            color: "white"
            font.pixelSize: 13
        }
    }
}