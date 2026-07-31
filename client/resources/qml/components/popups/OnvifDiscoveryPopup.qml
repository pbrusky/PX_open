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

    // Camera chosen while waiting for getRtsp()
    property string pendingAddress: ""
    property string pendingUser: ""
    property string pendingPass: ""

    Rectangle {
        anchors.fill: parent
        color: "#000000CC"
    }

    Rectangle {
        id: container
        width: 940
        height: 740
        radius: 14
        color: "#1A1A1A"
        border.color: "#2F2F2F"
        border.width: 1
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 32
            spacing: 24

            Text {
                text: "ONVIF Discovery"
                font.pixelSize: 36
                font.bold: true
                color: "white"
            }

            GridLayout {
                Layout.fillWidth: true
                columns: 2
                columnSpacing: 18
                rowSpacing: 12

                Text { text: "Username"; color: "#AAAAAA"; font.pixelSize: 16 }
                TextField {
                    id: userField
                    placeholderText: "admin (optional)"
                    color: "white"
                    font.pixelSize: 16
                    background: Rectangle {
                        color: "#252525"
                        radius: 8
                        border.color: userField.activeFocus ? "#4A90E2" : "#444"
                        border.width: userField.activeFocus ? 2 : 1
                    }
                }

                Text { text: "Password"; color: "#AAAAAA"; font.pixelSize: 16 }
                TextField {
                    id: passField
                    placeholderText: "password (optional)"
                    echoMode: TextInput.Password
                    color: "white"
                    font.pixelSize: 16
                    background: Rectangle {
                        color: "#252525"
                        radius: 8
                        border.color: passField.activeFocus ? "#4A90E2" : "#444"
                        border.width: passField.activeFocus ? 2 : 1
                    }

                    onAccepted: {
                        devices = []
                        discoveryRunning = true
                        if (frigateRef)
                            frigateRef.discoverOnvif(userField.text, passField.text)
                    }
                }
            }

            Button {
                id: scanButton
                text: discoveryRunning ? "Scanning..." : "Start Discovery"
                Layout.fillWidth: true
                font.pixelSize: 18
                font.bold: true
                enabled: !discoveryRunning

                background: Rectangle {
                    radius: 8
                    color: scanButton.enabled ? (scanButton.down ? "#3A8EFF" : "#4A90E2") : "#555555"
                }

                contentItem: Text {
                    text: scanButton.text
                    font: scanButton.font
                    color: "white"
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }

                onClicked: {
                    devices = []
                    discoveryRunning = true
                    if (frigateRef)
                        frigateRef.discoverOnvif(userField.text, passField.text)
                }
            }

            Rectangle {
                Layout.fillWidth: true
                height: 54
                radius: 8
                color: "#252525"
                border.color: "#333"

                Text {
                    anchors.centerIn: parent
                    text: discoveryRunning
                          ? "Scanning for ONVIF devices on the network..."
                          : (devices.length > 0
                             ? "Scan completed — " + devices.length + " device(s) found"
                             : "Ready to scan")
                    color: discoveryRunning ? "#FFCC00" : "#AAAAAA"
                    font.pixelSize: 16
                }
            }

            ListView {
                id: list
                Layout.fillWidth: true
                Layout.fillHeight: true
                clip: true
                spacing: 16
                bottomMargin: 30
                model: devices

                delegate: Rectangle {
                    width: ListView.view.width
                    height: 190
                    radius: 12
                    color: hovered ? "#2A2A2A" : "#222222"
                    border.color: "#3F3F3F"

                    property bool hovered: false

                    MouseArea {
                        anchors.fill: parent
                        hoverEnabled: true
                        onEntered: parent.hovered = true
                        onExited: parent.hovered = false
                    }

                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 20
                        spacing: 10

                        Text {
                            text: (modelData.manufacturer && modelData.model)
                                  ? modelData.manufacturer + " " + modelData.model
                                  : modelData.address
                            color: "white"
                            font.pixelSize: 19
                            font.bold: true
                            elide: Text.ElideRight
                        }

                        Text { text: "IP: " + modelData.address; color: "#BBB"; font.pixelSize: 14 }
                        Text { text: "Protocol: " + (modelData.protocol || "ONVIF"); color: "#BBB"; font.pixelSize: 14 }
                        Text { text: "Firmware: " + (modelData.firmware || "Unknown"); color: "#BBB"; font.pixelSize: 14 }
                        Text { text: "Serial: " + (modelData.serial || "N/A"); color: "#BBB"; font.pixelSize: 14 }

                        Item { Layout.fillHeight: true }

                        Button {
                            text: "Use This Camera"
                            Layout.fillWidth: true
                            height: 58
                            font.pixelSize: 16
                            font.bold: true

                            background: Rectangle {
                                radius: 10
                                color: parent.down ? "#3670C0" : "#4A90E2"
                            }

                            contentItem: Text {
                                text: parent.text
                                font: parent.font
                                color: "white"
                                horizontalAlignment: Text.AlignHCenter
                                verticalAlignment: Text.AlignVCenter
                            }

                            onClicked: {
                                if (!addCameraPopupRef || !frigateRef)
                                    return

                                pendingAddress = modelData.address || ""
                                pendingUser = userField.text
                                pendingPass = passField.text

                                // Prefill credentials / IP on Add Camera form immediately
                                applyIdentityToAddPopup(pendingAddress, pendingUser, pendingPass)

                                frigateRef.getRtsp(
                                    pendingAddress,
                                    pendingUser,
                                    pendingPass
                                )
                            }
                        }
                    }
                }
            }

            Button {
                text: "Close"
                Layout.fillWidth: true
                font.pixelSize: 17

                background: Rectangle {
                    radius: 8
                    color: parent.down ? "#444" : "#2A2A2A"
                }

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

            var mainUrl = rtsp || ""
            var subUrl = deriveSubFromMain(mainUrl)

            // New AddCameraPopup fields (main + sub)
            applyStreamsToAddPopup(mainUrl, subUrl)
            applyIdentityToAddPopup(pendingAddress, pendingUser, pendingPass)

            closeRequested()
        }

        function onOnvifError(message) {
            discoveryRunning = false
            console.warn("ONVIF error:", message)
        }
    }

    function applyIdentityToAddPopup(address, user, pass) {
        if (!addCameraPopupRef)
            return

        // Prefer TextField ids if present
        if (addCameraPopupRef.ipInput)
            addCameraPopupRef.ipInput.text = address || ""
        if (addCameraPopupRef.userInput)
            addCameraPopupRef.userInput.text = user || ""
        if (addCameraPopupRef.passInput)
            addCameraPopupRef.passInput.text = pass || ""

        // Also set properties used by helpers
        if (typeof addCameraPopupRef.username !== "undefined")
            addCameraPopupRef.username = user || ""
        if (typeof addCameraPopupRef.password !== "undefined")
            addCameraPopupRef.password = pass || ""
    }

    function applyStreamsToAddPopup(mainUrl, subUrl) {
        if (!addCameraPopupRef)
            return

        // TextFields in new AddCameraPopup
        if (addCameraPopupRef.mainRtspInput)
            addCameraPopupRef.mainRtspInput.text = mainUrl || ""
        if (addCameraPopupRef.subRtspInput)
            addCameraPopupRef.subRtspInput.text = subUrl || mainUrl || ""

        // Properties used by getMainUrl / getSubUrl
        if (typeof addCameraPopupRef.mainStreamUrl !== "undefined")
            addCameraPopupRef.mainStreamUrl = mainUrl || ""
        if (typeof addCameraPopupRef.subStreamUrl !== "undefined")
            addCameraPopupRef.subStreamUrl = subUrl || mainUrl || ""

        // Backward compatibility if old single-field popup still exists
        if (addCameraPopupRef.rtspField)
            addCameraPopupRef.rtspField.text = mainUrl || ""
        if (typeof addCameraPopupRef.streamUrl !== "undefined")
            addCameraPopupRef.streamUrl = mainUrl || ""
    }

    // Best-effort substream from a main RTSP URL
    function deriveSubFromMain(mainUrl) {
        if (!mainUrl || mainUrl.indexOf("rtsp://") !== 0)
            return mainUrl

        var u = mainUrl

        // Hikvision-style
        if (u.indexOf("/Channels/101") >= 0)
            return u.replace("/Channels/101", "/Channels/102")
        if (u.indexOf("/Channels/1") >= 0 && u.indexOf("/Channels/10") < 0)
            return u.replace("/Channels/1", "/Channels/2")

        // Dahua-style
        if (u.indexOf("subtype=0") >= 0)
            return u.replace("subtype=0", "subtype=1")

        // Reolink / others — keep main if unknown
        return u
    }
}