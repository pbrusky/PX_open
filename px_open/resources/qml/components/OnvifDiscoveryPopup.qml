import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: popup
    modal: true
    width: 720
    height: 520
    focus: true

    background: Rectangle {
        color: "#0F0F0F"
        radius: 8
    }

    property var addCameraPopupRef: null
    property var devices: []

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 24
        spacing: 18

        Text {
            text: "ONVIF Discovery"
            font.pixelSize: 28
            font.bold: true
            color: "white"
        }

        TextField {
            id: usernameField
            placeholderText: "ONVIF Username"
            Layout.fillWidth: true
            font.pixelSize: 16
            color: "white"
            placeholderTextColor: "#888"
            background: Rectangle {
                color: "#1E1E1E"
                radius: 6
                border.color: "#444"
            }
        }

        TextField {
            id: passwordField
            placeholderText: "ONVIF Password"
            echoMode: TextInput.Password
            Layout.fillWidth: true
            font.pixelSize: 16
            color: "white"
            placeholderTextColor: "#888"
            background: Rectangle {
                color: "#1E1E1E"
                radius: 6
                border.color: "#444"
            }
        }

        Button {
            text: "Discover Cameras"
            Layout.fillWidth: true
            font.pixelSize: 16
            onClicked: {
                devices = []
                console.log("OnvifDiscoveryPopup: calling discoverOnvif()")
                frigate.discoverOnvif(usernameField.text, passwordField.text)
            }
        }

        Text {
            visible: devices.length === 0
            text: "No ONVIF cameras found"
            color: "#bbb"
            font.pixelSize: 18
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        ListView {
            id: list
            model: devices
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            spacing: 10

            delegate: Rectangle {
                width: list.width
                height: 120
                radius: 6
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
                    anchors.margins: 14
                    spacing: 8

                    // ------------------------------
                    // Manufacturer + Model + IP
                    // ------------------------------
                    Text {
                        text: (modelData.manufacturer && modelData.manufacturer !== "" &&
                               modelData.model && modelData.model !== "")
                              ? modelData.manufacturer + " " + modelData.model
                              : (modelData.address || "Unknown Device")
                        color: "white"
                        font.pixelSize: 20
                        font.bold: true
                    }

                    // ------------------------------
                    // RTSP URL
                    // ------------------------------
                    Text {
                        text: modelData.rtsp || ""
                        color: "#ccc"
                        font.pixelSize: 16
                        elide: Text.ElideRight
                    }

                    Row {
                        spacing: 12

                        Button {
                            text: "Use"
                            font.pixelSize: 14
                            onClicked: {
                                if (!addCameraPopupRef) {
                                    console.log("OnvifDiscoveryPopup: addCameraPopupRef is null")
                                    return
                                }

                                let popupRef = addCameraPopupRef

                                if (popupRef.cameraId !== undefined)
                                    popupRef.cameraId = modelData.address || ""

                                if (popupRef.ipField)
                                    popupRef.ipField.text = modelData.address || ""

                                if (popupRef.userField)
                                    popupRef.userField.text = modelData.username || ""

                                if (popupRef.passField)
                                    popupRef.passField.text = modelData.password || ""

                                let rtsp = modelData.rtsp || ""

                                if (!rtsp || !rtsp.startsWith("rtsp://")) {
                                    rtsp = "rtsp://" +
                                           (modelData.username || "") +
                                           (modelData.password ? ":" + modelData.password : "") +
                                           "@" + (modelData.address || "") +
                                           ":554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1"
                                }

                                if (popupRef.rtspField)
                                    popupRef.rtspField.text = rtsp

                                popupRef.streamUrl = rtsp
                                popupRef.open()
                                popup.close()
                            }
                        }
                    }
                }
            }
        }

        Button {
            text: "Close"
            Layout.fillWidth: true
            font.pixelSize: 16
            onClicked: popup.close()
        }
    }

    Connections {
        target: frigate

        function onOnvifDevicesDiscovered(devList) {
            console.log("OnvifDiscoveryPopup: received devices:", devList.length)
            devices = devList
        }
    }
}
