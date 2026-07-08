import QtQuick 2.15
import QtQuick.Controls 2.15
import QtMultimedia 6.5

Rectangle {
    id: root
    anchors.fill: parent
    color: "black"

    //
    // Event data provided by MainWindow
    //
    property var eventData: mainWindow.eventPlaybackData

    //
    // Auto-hide UI timer (NX style)
    //
    property bool uiVisible: true

    Timer {
        id: hideTimer
        interval: 2500
        repeat: false
        onTriggered: root.uiVisible = false
    }

    //
    // Media Player
    //
    MediaPlayer {
        id: player
        source: eventData ? eventData.clipUrl : ""
        videoOutput: videoOut
        audioOutput: AudioOutput {}
    }

    Component.onCompleted: {
        if (eventData && eventData.clipUrl) {
            console.log("EventPlayback: starting clip:", eventData.clipUrl)
            player.play()
        } else {
            console.log("EventPlayback: NO CLIP URL")
        }
    }

    //
    // Video Output
    //
    VideoOutput {
        id: videoOut
        anchors.fill: parent
        fillMode: VideoOutput.PreserveAspectFit
    }

    //
    // Mouse interaction (show UI)
    //
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true

        onClicked: {
            // NX behavior: click exits playback
            mainWindow.navigate("qrc:/app/resources/qml/components/ServerView.qml")
        }

        onPositionChanged: {
            root.uiVisible = true
            hideTimer.restart()
        }
    }

    //
    // ESC key exits playback
    //
    Keys.onEscapePressed: mainWindow.navigate("qrc:/app/resources/qml/components/ServerView.qml")

    //
    // Top Bar (NX style)
    //
    Rectangle {
        id: topBar
        height: 50
        width: parent.width
        color: "#00000088"
        anchors.top: parent.top
        opacity: root.uiVisible ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 200 } }

        Row {
            anchors.fill: parent
            anchors.margins: 10
            spacing: 20

            // NX-style close icon
            Rectangle {
                width: 32
                height: 32
                radius: 4
                color: "#00000088"

                Image {
                    anchors.centerIn: parent
                    source: "qrc:/app/assets/icons/nx/exit_fullscreen.svg"
                    width: 22
                    height: 22
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: mainWindow.navigate("qrc:/app/resources/qml/components/ServerView.qml")
                }
            }

            Column {
                spacing: 2

                Text {
                    text: eventData ? eventData.camera : "Unknown Camera"
                    color: "white"
                    font.pixelSize: 20
                }

                Text {
                    text: eventData ? eventData.timestamp : ""
                    color: "#ccc"
                    font.pixelSize: 14
                }
            }
        }
    }

    //
    // Bottom Timeline Placeholder (NX style)
    //
    Rectangle {
        id: timelineBar
        height: 60
        width: parent.width
        anchors.bottom: parent.bottom
        color: "#00000088"
        opacity: root.uiVisible ? 1 : 0

        Behavior on opacity { NumberAnimation { duration: 200 } }

        Text {
            anchors.centerIn: parent
            text: "Event Timeline Coming Soon"
            color: "white"
            font.pixelSize: 14
        }
    }
}
