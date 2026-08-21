import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: overlay
    anchors.fill: parent

    property string cameraName: ""
    property string resolution: ""
    property real fps: 0
    property int bitrateKbps: 0
    property string codec: ""

    signal infoRequested()
    signal removeRequested()

    // Qt 6: stays true while over children (buttons) — no flicker
    HoverHandler {
        id: hover
    }

    property bool hovered: hover.hovered

    // Highlight border only — do NOT darken the video
    Rectangle {
        anchors.fill: parent
        radius: 6
        color: "transparent"
        border.width: hovered ? 2 : 0
        border.color: "#5B8CFF"
        opacity: hovered ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        Behavior on border.width { NumberAnimation { duration: 80 } }
        z: 5
    }

    Rectangle {
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 8
        anchors.bottomMargin: 8
        radius: 10
        color: "#000000B0"
        height: 24
        width: nameText.contentWidth + 16
        opacity: cameraName !== "" ? 1.0 : 0.0
        z: 6

        Text {
            id: nameText
            anchors.centerIn: parent
            text: cameraName
            color: "white"
            font.pixelSize: 12
            font.bold: true
        }
    }

    Rectangle {
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        anchors.rightMargin: 8
        anchors.bottomMargin: 8
        radius: 10
        color: "#000000B0"
        height: 24
        width: statsText.contentWidth + 16
        opacity: hovered && (resolution !== "" || fps > 0) ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        z: 6

        Text {
            id: statsText
            anchors.centerIn: parent
            color: "#E0E0E0"
            font.pixelSize: 11
            text: {
                var parts = []
                if (resolution !== "")
                    parts.push(resolution)
                if (fps > 0)
                    parts.push(fps.toFixed(0) + " fps")
                if (bitrateKbps > 0)
                    parts.push(bitrateKbps + " kbps")
                if (codec !== "")
                    parts.push(codec.toUpperCase())
                return parts.join("  ·  ")
            }
        }
    }

    Row {
        spacing: 6
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 8
        anchors.rightMargin: 8
        opacity: hovered ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
        z: 10

        Rectangle {
            width: 28
            height: 28
            radius: 14
            color: infoMa.containsMouse ? "#333333EE" : "#000000B0"

            Text {
                anchors.centerIn: parent
                text: "\u2139"
                color: "white"
                font.pixelSize: 15
            }

            MouseArea {
                id: infoMa
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.LeftButton
                onClicked: overlay.infoRequested()
            }
        }

        Rectangle {
            width: 28
            height: 28
            radius: 14
            color: closeMa.containsMouse ? "#5A1A1AEE" : "#000000B0"

            Text {
                anchors.centerIn: parent
                text: "\u2715"
                color: "white"
                font.pixelSize: 14
            }

            MouseArea {
                id: closeMa
                anchors.fill: parent
                hoverEnabled: true
                preventStealing: true
                acceptedButtons: Qt.LeftButton
                onClicked: overlay.removeRequested()
            }
        }
    }
}