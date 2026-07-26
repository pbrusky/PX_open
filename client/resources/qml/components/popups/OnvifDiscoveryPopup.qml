import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: onvifPopup
    objectName: "OnvifDiscoveryPopup"

    anchors.fill: parent
    z: 999999

    signal closeRequested()

    property var frigateRef: null
    property var addCameraPopupRef: null

    property var devices: []
    property bool discoveryRunning: false

    Rectangle {
        anchors.fill: parent
        color: "#000000AA"
    }

    Rectangle {
        id: container
        width: 900
        height: 700
        radius: 10
        color: "#121212"
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 28
            spacing: 16

            Text {
                text: "ONVIF Discovery"
                font.pixelSize: 32
                font.bold: true
                color: "white"
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 12
                rowSpacing: 8

                Text { text: "Username"; color: "#ccc"; font.pixelSize: 16 }
                TextField {
                    id: userField
                    placeholderText: "Optional"
                    color: "white"
                    font.pixelSize: 16
                    background: Rectangle { color: "#1E1E1E"; radius: 6; border.color: "#444" }
                }

                Text { text: "Password"; color: "#ccc"; font.pixelSize: 16 }
                TextField {
                    id: passField
                    placeholderText: "Optional"
                    echoMode: TextInput.Password
                    color: "white"
                    font.pixelSize: 16
                    background: Rectangle { color: "#1E1E1E"; radius: 6; border.color: "#444" }
                }
            }

            Button {
                text: discoveryRunning ? "Scanning..." : "Start Scan"
                Layout.fillWidth: true
                font.pixelSize: 20
                enabled: !discoveryRunning

                onClicked: {
                    devices = []
                    discoveryRunning = true

                    if (frigateRef)
                        frigateRef.discoverOnvif(userField.text, passField.text)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.preferredHeight: 50
                radius: 6
                color: "#1A1A1A"
                border.color: "#333"

                Text {
                    anchors.centerIn: parent
                    text: discoveryRunning
                          ? "Scanning for ONVIF cameras..."
                          : (devices.length > 0 ? "Scan complete" : "Ready to scan")
                    color: "#ccc"
                    font.pixelSize: 18
                }
            }

            ListView {
                id: list
                model: devices
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 16

                delegate: Rectangle {
                    width: list.width
                    height: 160
                    radius: 10
                    color: hovered ? "#2A2A2A" : "#1E1E1E"
                    border.color: "#444"

                    property bool hovered: false

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.hovered = true
                        onExited: parent.hovered = false
                    }

                    Column {
                        anchors.fill: parent
                        anchors.margins: 16
                        spacing: 6

                        Text {
                            text: (modelData.manufacturer && modelData.model)
                                  ? modelData.manufacturer + " " + modelData.model
                                  : modelData.address
                            color: "white"
                            font.pixelSize: 20
                            font.bold: true
                        }

                        Text { text: "IP: " + modelData.address; color: "#bbb"; font.pixelSize: 15 }
                        Text { text: "Protocol: " + modelData.protocol; color: "#bbb"; font.pixelSize: 15 }
                        Text { text: "Firmware: " + modelData.firmware; color: "#bbb"; font.pixelSize: 15 }
                        Text { text: "Serial #: " + modelData.serial; color: "#bbb"; font.pixelSize: 15 }

                        Row {
                            spacing: 12

                            Button {
                                text: "Use"
                                font.pixelSize: 15

                                onClicked: {
                                    if (!addCameraPopupRef || !frigateRef)
                                        return

                                    frigateRef.getRtsp(
                                        modelData.address,
                                        userField.text,
                                        passField.text
                                    )
                                }
                            }
                        }
                    }
                }
            }

            Button {
                text: "Close"
                Layout.fillWidth: true
                font.pixelSize: 18
                onClicked: closeRequested()
            }
        }
    }

    Connections {
        target: frigateRef ? frigateRef : null
        ignoreUnknownSignals: true

        function onOnvifDevicesDiscovered(devicesList) {
            discoveryRunning = false
            devices = devicesList
        }

        function onRtspResolved(rtsp) {

            if (!addCameraPopupRef) {
                console.warn("ONVIF: addCameraPopupRef is undefined")
                closeRequested()
                return
            }

            if (!addCameraPopupRef.rtspField) {
                console.warn("ONVIF: addCameraPopupRef.rtspField is undefined")
                closeRequested()
                return
            }

            addCameraPopupRef.rtspField.text = rtsp
            addCameraPopupRef.streamUrl = rtsp

            closeRequested()
        }

        function onOnvifError(message) {
            discoveryRunning = false
        }
    }
}
