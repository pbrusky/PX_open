import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: item
    width: parent.width
    height: 60
    color: "#222"
    border.color: "#333"

    property string name: ""
    property string address: ""

    Column {
        anchors.centerIn: parent

        Text {
            text: name
            color: "white"
            font.pixelSize: 16
        }

        Text {
            text: address
            color: "#aaa"
            font.pixelSize: 12
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: {
            console.log("Selected server:", name, address)
            frigate.setServer(address)
            sidebar.navigate("CameraGrid.qml")
        }
    }
}
