import QtQuick 2.15

Item {
    id: root
    anchors.fill: parent
    z: 50
    visible: active

    property bool active: false
    property int loadSecs: 0

    Rectangle {
        anchors.centerIn: parent
        width: Math.min(parent.width * 0.7, 440)
        height: 80
        radius: 10
        color: "#CC000000"
        border.color: "#FFC107"
        border.width: 1

        Column {
            anchors.centerIn: parent
            spacing: 8
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "LOADING CLIP... " + root.loadSecs + "s"
                color: "#FFC107"
                font.pixelSize: 20
                font.bold: true
            }
            Text {
                anchors.horizontalCenter: parent.horizontalCenter
                text: "Opening recording…"
                color: "#FF8888"
                font.pixelSize: 13
            }
        }
    }
}