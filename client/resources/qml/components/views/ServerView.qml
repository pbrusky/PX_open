import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 2.15

Item {
    id: serverView
    objectName: "ServerView"

    property var mainWindow
    property var frigate

    ColumnLayout {
        anchors.fill: parent
        spacing: 10

        Text {
            text: "Cameras"
            font.pixelSize: 26
            color: "white"
            Layout.alignment: Qt.AlignHCenter
        }

        ListView {
            id: cameraListView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true

            model: frigate.cameraList

            delegate: Rectangle {
                width: parent.width
                height: 50
                color: "#222"

                Text {
                    anchors.centerIn: parent
                    text: modelData.name
                    color: "white"
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        console.log("ServerView: Selected camera:", modelData.name)
                        mainWindow.loadCamera(modelData.name)
                    }
                }
            }
        }
    }
}
