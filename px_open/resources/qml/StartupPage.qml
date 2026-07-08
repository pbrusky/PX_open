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
    function connectToServer(address, modulePort) {
        console.log("StartupPage: connecting to server", address, modulePort)

        //
        // Frigate API is ALWAYS port 5000
        //
        var apiPort = 5000
        var apiUrl = "http://" + address + ":" + apiPort
        var moduleUrl = "http://" + address + ":" + modulePort

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
            text: "Discovered Servers"
            font.pixelSize: 26
            color: "white"
            horizontalAlignment: Text.AlignHCenter
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
    }
}
