import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Rectangle {
    id: root
    anchors.fill: parent
    color: "#111111"

    //
    // Event model provided by FrigateAPI
    //
    property var eventsModel: []

    //
    // Load events when page opens
    //

    Connections {
        target: frigate

        function onEventsLoaded(list) {
            root.eventsModel = list
        }
    }

    //
    // Title
    //
    Text {
        text: "Events"
        font.pixelSize: 26
        color: "white"
        anchors.left: parent.left
        anchors.leftMargin: 20
        anchors.top: parent.top
        anchors.topMargin: 20
    }

    //
    // Event list (NX style)
    //
    ListView {
        id: list
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        anchors.bottom: parent.bottom
        anchors.margins: 20

        spacing: 10
        clip: true

        model: root.eventsModel

        delegate: Rectangle {
            width: parent.width
            height: 90
            radius: 6
            color: "#1e1e1e"
            border.color: "#333"

            Row {
                anchors.fill: parent
                anchors.margins: 12
                spacing: 12

                //
                // Thumbnail (placeholder)
                //
                Rectangle {
                    width: 100
                    height: 60
                    radius: 4
                    color: "#333"

                    Text {
                        anchors.centerIn: parent
                        text: "Thumbnail"
                        color: "#aaa"
                        font.pixelSize: 12
                    }
                }

                //
                // Event info
                //
                Column {
                    spacing: 4

                    Text {
                        text: model.camera
                        color: "white"
                        font.pixelSize: 18
                    }

                    Text {
                        text: model.label
                        color: "#ccc"
                        font.pixelSize: 14
                    }

                    Text {
                        text: model.timestamp
                        color: "#888"
                        font.pixelSize: 12
                    }
                }
            }

            //
            // Hover highlight
            //
            MouseArea {
                anchors.fill: parent

                hoverEnabled: true
                onEntered: parent.color = "#2A4A7A"
                onExited: parent.color = "#1e1e1e"

                //
                // Click → open playback
                //
                onClicked: {
                    mainWindow.eventPlaybackData = model
                    mainWindow.navigate("qrc:/app/resources/qml/EventPlayback.qml")
                }
            }
        }
    }
}
