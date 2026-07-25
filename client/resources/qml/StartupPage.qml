import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    objectName: "StartupPage"
    anchors.fill: parent
    color: "black"

    property var discovery: null
    property var frigateRef: null

    property var servers: []
    ListModel { id: serverModel }

    property string manualServerIp: ""
    property int manualModulePort: 7001
    property string manualUsername: ""
    property string manualPassword: ""

    property bool serverAssigned: false

    signal serverSelected(string name, string ip, int apiPort, int modulePort)

    Component.onCompleted: {
        // logs removed
    }

    Component.onDestruction: {
        if (discovery) discovery.stopDiscovery()
    }

    onDiscoveryChanged: {
        if (!discovery)
            return

        servers = []
        serverModel.clear()
        discovery.startDiscovery()
    }

    Connections {
        target: discovery

        function onServerFound(name, address, port, container) {
            if (root.serverAssigned)
                return

            for (var i = 0; i < servers.length; i++) {
                var s = servers[i]
                if (s.address === address && s.port === port)
                    return
            }

            servers.push({ name, address, port, container })

            serverModel.append({
                "name": name,
                "address": address,
                "port": port,
                "container": container
            })
        }
    }

    function connectToServer(address, modulePort, username, password) {
        if (!modulePort || modulePort === 0)
            modulePort = 7001

        var auth = ""
        if (username && username.length > 0) {
            auth = encodeURIComponent(username)
            if (password && password.length > 0)
                auth += ":" + encodeURIComponent(password)
            auth += "@"
        }

        var apiPort = 5000
        var apiUrl = "http://" + auth + address + ":" + apiPort
        var moduleUrl = "http://" + auth + address + ":" + modulePort

        if (!frigateRef)
            return

        frigateRef.setServer(apiUrl)
        frigateRef.setModuleServer(moduleUrl)

        frigateRef.loadModuleInformation()
        frigateRef.loadCameras()

        root.serverSelected("Frigate System", address, apiPort, modulePort)
    }

    Column {
        spacing: 20
        width: 420
        anchors.centerIn: parent

        Text {
            width: parent.width
            text: "Discovered Servers"
            font.pixelSize: 26
            color: "white"
            horizontalAlignment: Text.AlignHCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }

        ListView {
            width: parent.width
            height: 300
            model: serverModel

            delegate: Rectangle {
                width: parent.width
                height: 80
                radius: 8
                color: "#0F355C"
                border.color: "#1A4A7A"

                Row {
                    anchors.fill: parent
                    anchors.margins: 12
                    spacing: 12

                    Image {
                        source: "qrc:/app/assets/icons/nx/server.svg"
                        width: 32
                        height: 32
                    }

                    Column {
                        spacing: 2

                        Text { text: name; color: "white"; font.pixelSize: 18 }
                        Text { text: address + ":" + port; color: "#ccc"; font.pixelSize: 14 }
                        Text { text: "Container: " + container; color: "#aaa"; font.pixelSize: 12 }
                    }
                }

                MouseArea {
                    anchors.fill: parent
                    onClicked: {
                        if (root.serverAssigned)
                            return

                        root.serverAssigned = true
                        root.connectToServer(address, port)
                    }
                }
            }
        }

        Button {
            text: "Manual Add Server"
            width: parent.width
            onClicked: manualPopup.open()
        }
    }

    Popup {
        id: manualPopup
        modal: true
        focus: true
        width: 520
        height: 520
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        background: Rectangle {
            color: "#111"
            radius: 8
            border.color: "#444"
            border.width: 1
        }

        anchors.centerIn: parent

        Column {
            spacing: 14
            padding: 24
            width: parent.width
            height: parent.height

            Text {
                text: "Manual Add Server"
                color: "white"
                font.pixelSize: 24
                font.bold: true
            }

            TextField {
                id: manualIpField
                placeholderText: "Server IP (e.g. 10.0.0.5)"
                width: parent.width
                text: root.manualServerIp
                onTextChanged: root.manualServerIp = text
            }

            TextField {
                id: manualPortField
                placeholderText: "Module Port (e.g. 7001)"
                width: parent.width
                inputMethodHints: Qt.ImhDigitsOnly
                text: root.manualModulePort > 0 ? root.manualModulePort.toString() : ""
                onTextChanged: root.manualModulePort = parseInt(text) || 0
            }

            TextField {
                id: manualUserField
                placeholderText: "Username (optional)"
                width: parent.width
                text: root.manualUsername
                onTextChanged: root.manualUsername = text
            }

            TextField {
                id: manualPassField
                placeholderText: "Password (optional)"
                width: parent.width
                echoMode: TextInput.Password
                text: root.manualPassword
                onTextChanged: root.manualPassword = text
            }

            Rectangle {
                width: parent.width
                height: 1
                color: "#444"
            }

            Button {
                text: "Connect"
                width: parent.width
                onClicked: {
                    if (!manualIpField.text || manualIpField.text.length === 0)
                        return

                    if (!manualPortField.text || manualPortField.text.length === 0)
                        return

                    root.serverAssigned = true
                    root.connectToServer(
                        manualIpField.text,
                        parseInt(manualPortField.text) || 7001,
                        manualUserField.text,
                        manualPassField.text
                    )
                    manualPopup.close()
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
