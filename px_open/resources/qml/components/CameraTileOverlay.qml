import QtQuick 2.15
import QtQuick.Controls 2.15

Item {
    id: overlay
    anchors.fill: parent

    property string cameraName: ""

    MouseArea {
        id: hoverArea
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.NoButton
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: hoverArea.containsMouse ? 0.25 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }

    Text {
        text: cameraName
        anchors.left: parent.left
        anchors.bottom: parent.bottom
        anchors.leftMargin: 8
        anchors.bottomMargin: 6
        color: "white"
        font.pixelSize: 16
        opacity: hoverArea.containsMouse ? 1.0 : 0.0
        Behavior on opacity { NumberAnimation { duration: 120 } }
    }
}
