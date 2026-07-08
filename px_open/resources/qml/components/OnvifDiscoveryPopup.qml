import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: popup
    modal: true
    width: 720
    height: 520
    focus: true
    background: Rectangle { color: "#0F0F0F"; radius: 8 }

    property var frigateRef: null
    property var addCameraPopupRef: null     // AddCameraPopup OR EditCameraPopup
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

        Button {
            text: "Discover Cameras"
            Layout.fillWidth: true
            font.pixelSize: 16
            onClicked: {
                devices = []
                if (frigateRef)
                    frigateRef.discoverOnvif()
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

                    Text {
                        text: (modelData.manufacturer && modelData.model &&
                               modelData.manufacturer !== "" && modelData.model !== "")
                              ? modelData.manufacturer + " " + modelData.model
                              : (modelData.address || "Unknown")
                        color: "white"
                        font.pixelSize: 20
                        font.bold: true
                    }

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

                                //
                                // ⭐ Auto-fill fields
                                //
                                if (popupRef.cameraId !== undefined)
                                    popupRef.cameraId = modelData.address || ""

                                if (popupRef.ipField)
                                    popupRef.ipField.text = modelData.address || ""

                                if (popupRef.userField)
                                    popupRef.userField.text = modelData.username || ""

                                if (popupRef.passField)
                                    popupRef.passField.text = modelData.password || ""

                                //
                                // ⭐ RTSP handling
                                //
                                let rtsp = modelData.rtsp || ""

                                // If ONVIF RTSP is missing or incomplete, rebuild Hikvision-style RTSP
                                if (!rtsp || !rtsp.startsWith("rtsp://")) {
                                    rtsp = "rtsp://" +
                                           (modelData.username || "") +
                                           (modelData.password ? ":" + modelData.password : "") +
                                           "@" + (modelData.address || "") +
                                           ":554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1"
                                }

                                if (popupRef.rtspField)
                                    popupRef.rtspField.text = rtsp

                                if (popupRef.streamUrl !== undefined)
                                    popupRef.streamUrl = rtsp

                                //
                                // ⭐ Rebuild RTSP if popup has builder
                                //
                                if (popupRef.buildRtspUrl)
                                    popupRef.rtspField.text = popupRef.buildRtspUrl()

                                //
                                // ⭐ Open popup and close ONVIF window
                                //
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

    //
    // ⭐ Backend ONVIF results
    //
    Connections {
        target: frigateRef
        function onOnvifDevicesDiscovered(devList) {
            devices = devList
        }
    }
}
