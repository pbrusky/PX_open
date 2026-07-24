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

    property bool hovered: false

    // Hover detection
    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
        onEntered: overlay.hovered = true
        onExited: overlay.hovered = false
    }

    // NX-style dark tint
    Rectangle {
        anchors.fill: parent
        radius: 6
        color: "#000000"
        opacity: hovered ? 0.28 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    // Camera name pill (bottom-left)
    Rectangle {
        id: namePill
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 10
        anchors.bottomMargin: 10
        radius: 12
        color: "#000000AA"
        opacity: hovered ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        height: 26
        width: textName.contentWidth + 20

        Text {
            id: textName
            anchors.centerIn: parent
            text: cameraName
            color: "white"
            font.pixelSize: 14
        }
    }

    // Top-right button row
    Row {
        id: buttonRow
        spacing: 8
        anchors.top: parent.top
        anchors.right: parent.right
        anchors.topMargin: 10
        anchors.rightMargin: 10

        opacity: hovered ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }

        // Info button
        Rectangle {
            id: infoBtn
            width: 26
            height: 26
            radius: 13
            color: "#000000AA"

            scale: hovered ? 1.0 : 0.85
            Behavior on scale { NumberAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: "\u2139"
                color: "white"
                font.pixelSize: 16
            }

            MouseArea {
                anchors.fill: parent
                onClicked: overlay.infoRequested()
            }
        }

        // Close button
        Rectangle {
            id: closeBtn
            width: 26
            height: 26
            radius: 13
            color: "#000000AA"

            scale: hovered ? 1.0 : 0.85
            Behavior on scale { NumberAnimation { duration: 120 } }

            Text {
                anchors.centerIn: parent
                text: "\u2715"
                color: "white"
                font.pixelSize: 16
            }

            MouseArea {
                anchors.fill: parent
                onClicked: overlay.removeRequested()
            }
        }
    }
}
