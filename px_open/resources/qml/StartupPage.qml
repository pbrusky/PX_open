import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: root
    objectName: "StartupPage"
    anchors.fill: parent
    color: "black"

    //
    // Backend references
    //
    property var discovery: null
    property var frigate: null

    //
    // Discovered servers
    //
    property var servers: []
    ListModel { id: serverModel }

    property string manualServerIp: ""
    property int manualModulePort: 7001
    property string manualUsername: ""
    property string manualPassword: ""

    //
    // Prevent double‑connect
    //
    property bool serverAssigned: false

    //
    // Signal to MainWindow
    //
    signal serverSelected(string name, string ip, int apiPort, int modulePort)

    Component.onCompleted: {
        console.log("StartupPage: waiting for discovery assignment…")
    }

    Component.onDestruction: {
        console.log("StartupPage: stopping discovery")
        if (discovery) discovery.stopDiscovery()
    }

    //
    // When discovery object is assigned
    //
    onDiscoveryChanged: {
        if (!discovery) {
            console.log("StartupPage: discovery still null")
            return
        }

        console.log("StartupPage: discovery assigned, starting discovery…")
        servers = []
        serverModel.clear()
        discovery.startDiscovery()
    }

    //
    // ⭐ DISCOVERY LISTENER
    //
    Connections {
        target: discovery

        function onServerFound(name, address, port, container) {
            console.log("StartupPage: server found:", name, address, port)

            if (root.serverAssigned)
                return

            // Avoid duplicates
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

    //
    // ⭐ BACKEND SIGNALS
    //
    Connections {
        target: frigate

        function onModuleInformationReceived(name, version, status, systemId, moduleId) {
            console.log("StartupPage: module info received")
        }

        function onCameraOffline(id) {
            console.log("StartupPage: camera offline:", id)
        }

        function onCameraOnline(id) {
            console.log("StartupPage: camera online:", id)
        }
    }

    //
    // ⭐ CONNECT TO SERVER
    //
    function connectToServer(address, modulePort, username, password) {
        console.log("StartupPage: connecting to server", address, modulePort)

        if (!modulePort || modulePort === 0) {
            modulePort = 7001
            console.log("StartupPage: module port not provided, defaulting to", modulePort)
        }

        var auth = ""
        if (username && username.length > 0) {
            auth = encodeURIComponent(username)
            if (password && password.length > 0)
                auth += ":" + encodeURIComponent(password)
            auth += "@"
        }

        //
        // Frigate API is ALWAYS port 5000
        //
        var apiPort = 5000
        var apiUrl = "http://" + auth + address + ":" + apiPort
        var moduleUrl = "http://" + auth + address + ":" + modulePort

        frigate.setServer(apiUrl)
        frigate.setModuleServer(moduleUrl)

        console.log("StartupPage: Frigate API =", apiUrl)
        console.log("StartupPage: Module Server =", moduleUrl)

        //
        // Load module info + cameras
        //
        frigate.loadModuleInformation()
        frigate.loadCameras()

        //
        // Notify MainWindow
        //
        root.serverSelected("Frigate System", address, apiPort, modulePort)
    }

    //
    // UI
    //
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

                        console.log("StartupPage: selected server", name, address, port)
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
                    if (!manualIpField.text || manualIpField.text.length === 0) {
                        console.log("Manual connect requires IP address")
                        return
                    }

                    if (!manualPortField.text || manualPortField.text.length === 0) {
                        console.log("Manual connect requires port")
                        return
                    }

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
