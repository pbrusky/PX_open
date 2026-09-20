import QtQuick 2.15

Item {
    id: root
    height: 36
    width: parent ? parent.width : 0
    z: 30

    property string cameraName: ""
    property bool isPlayback: false
    property bool playbackReady: false
    property bool mainReady: false
    property bool trueMain: false

    signal exitRequested()
    signal returnToLiveRequested()

    Rectangle {
        anchors.fill: parent
        color: "#00000099"

        Row {
            anchors.fill: parent
            anchors.margins: 8
            spacing: 16

            Text {
                text: root.cameraName
                color: "white"
                font.pixelSize: 15
                font.bold: true
            }
            Text {
                text: {
                    if (!root.isPlayback)
                        return "LIVE"
                    if (!root.playbackReady)
                        return "LOADING..."
                    return "PLAYBACK"
                }
                color: root.isPlayback ? "#FFC107" : "#00C853"
                font.pixelSize: 13
                font.bold: true
            }
            Text {
                text: root.playbackReady ? "" : ((root.mainReady && root.trueMain) ? "MAIN" : "SUB")
                color: (root.mainReady && root.trueMain) ? "#FFC107" : "#90CAF9"
                font.pixelSize: 13
                visible: !root.isPlayback
            }
        }
    }

    Rectangle {
        width: 70
        height: 28
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.rightMargin: 90
        anchors.topMargin: 10
        radius: 4
        color: root.playbackReady ? "#1B5E20" : "#00000055"
        border.color: root.playbackReady ? "#00C853" : "#444"
        border.width: 1
        z: 1
        visible: root.isPlayback
        Text {
            anchors.centerIn: parent
            text: "Live"
            color: "white"
            font.pixelSize: 13
        }
        MouseArea {
            anchors.fill: parent
            enabled: root.playbackReady
            preventStealing: true
            onClicked: function(mouse) {
                mouse.accepted = true
                root.returnToLiveRequested()
            }
        }
    }

    Rectangle {
        width: 70
        height: 28
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.margins: 10
        radius: 4
        color: "#000000AA"
        z: 1
        Text {
            anchors.centerIn: parent
            text: "Exit"
            color: "white"
            font.pixelSize: 13
        }
        MouseArea {
            anchors.fill: parent
            onClicked: function(mouse) {
                mouse.accepted = true
                root.exitRequested()
            }
        }
    }
}