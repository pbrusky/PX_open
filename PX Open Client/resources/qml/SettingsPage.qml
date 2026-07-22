import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    anchors.fill: parent
    color: "black"        // ⭐ Full black background

    property var servers: []
    property bool autoConnectEnabled: true

    Component.onCompleted: {
        console.log("StartupPage loaded, starting discovery")
        discovery.startDiscovery()
    }

    Connections {
        target: discovery

        function onServerFound(name, address) {
            console.log("QML received server:", name, address)

            for (var i = 0; i < servers.length; i++) {
                if (servers[i].address === address)
                    return
            }

            servers.push({ name: name, address: address })
            serverModel.append({ name: name, address: address })

            if (autoConnectEnabled && servers.length === 1) {
                console.log("Auto-connecting to:", name, address)
                root.connectToServer(address)
            }
        }
    }

    function connectToServer(address) {
        console.log("Connecting to server:", address)
    }

    Column {
        id: content
        spacing: 20
        width: 420
        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        Text {
            text: "Discovered Servers"
            font.pixelSize: 26
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            width: parent.width
        }

        ListView {
            id: serverList
            width: parent.width
            height: 300
            model: ListModel { id: serverModel }

            delegate: Rectangle {
                width: parent.width
                height: 70
                radius: 8
                color: "#0F355C"        // ⭐ Blue tile background
                border.color: "#1A4A7A"
                border.width: 1

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Image {
                        source: "qrc:/pxclient/resources/assets/icons/server.svg"
                        width: 32
                        height: 32
                        fillMode: Image.PreserveAspectFit
                    }

                    Column {
                        spacing: 2

                        Text {
                            text: name
                            color: "white"
                            font.pixelSize: 18
                        }

                        Text {
                            text: address
                            color: "#cccccc"
                            font.pixelSize: 14
                        }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        console.log("Server clicked:", name, address)
                        root.connectToServer(address)
                    }
                }
            }
        }

        Button {
            text: "Manual Connect"
            width: parent.width
            onClicked: manualPopup.open()
        }
    }

    Popup {
        id: manualPopup
        modal: true
        focus: true
        width: 350
        background: Rectangle {
            color: "#0F355C"      // ⭐ Blue popup background
            radius: 8
        }

        anchors.centerIn: parent

        Column {
            spacing: 12
            padding: 20
            width: parent.width

            Text {
                text: "Manual Connect"
                color: "white"
                font.pixelSize: 20
            }

            TextField {
                id: ipField
                placeholderText: "Server IP (e.g. 10.0.0.5)"
                width: parent.width
            }

            TextField {
                id: portField
                placeholderText: "Port (e.g. 7001)"
                width: parent.width
                inputMethodHints: Qt.ImhDigitsOnly
            }

            Button {
                text: "Connect"
                width: parent.width
                onClicked: {
                    var addr = "http://" + ipField.text + ":" + portField.text
                    console.log("Manual connect to:", addr)
                    manualPopup.close()
                    root.connectToServer(addr)
                }
            }

            Button {
                text: "Cancel"
                width: parent.width
                onClicked: manualPopup.close()
            }
        }
    }
}
