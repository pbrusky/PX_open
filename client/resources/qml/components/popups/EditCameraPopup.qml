import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: editPopup
    objectName: "EditCameraPopup"

    anchors.fill: parent
    z: 999999

    signal closeRequested()

    property var frigateRef: null

    property string cameraId: ""
    property string rtspUrl: ""
    property string username: ""
    property string password: ""
    property bool rtspValid: true

    Rectangle {
        anchors.fill: parent
        color: "#000000AA"
    }

    Rectangle {
        id: container
        width: 480
        height: 480
        radius: 8
        color: "#111"
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 14

            Text {
                text: "Edit Camera"
                font.pixelSize: 24
                font.bold: true
                color: "white"
            }

            TextField {
                id: idField
                Layout.fillWidth: true
                placeholderText: "Camera ID"
                text: editPopup.cameraId
                readOnly: true
            }

            TextField {
                id: ipField
                Layout.fillWidth: true
                placeholderText: "Camera IP address"
                enabled: !rtspField.text.startsWith("rtsp://")
                onTextChanged: {
                    if (!rtspField.text.startsWith("rtsp://"))
                        rtspField.text = getFinalRtspUrl()
                }
            }

            TextField {
                id: rtspField
                Layout.fillWidth: true
                placeholderText: "RTSP URL"
                text: editPopup.rtspUrl
                onTextChanged: editPopup.rtspUrl = text
            }

            TextField {
                id: userField
                Layout.fillWidth: true
                placeholderText: "Username"
                text: editPopup.username
                enabled: !rtspField.text.startsWith("rtsp://")
                onTextChanged: {
                    editPopup.username = text
                    if (!rtspField.text.startsWith("rtsp://"))
                        rtspField.text = getFinalRtspUrl()
                }
            }

            TextField {
                id: passField
                Layout.fillWidth: true
                placeholderText: "Password"
                echoMode: TextInput.Password
                text: editPopup.password
                enabled: !rtspField.text.startsWith("rtsp://")
                onTextChanged: {
                    editPopup.password = text
                    if (!rtspField.text.startsWith("rtsp://"))
                        rtspField.text = getFinalRtspUrl()
                }
            }

            Text {
                visible: rtspField.text.startsWith("rtsp://")
                text: "Full RTSP URL detected — IP/username/password not required"
                color: "#66CC66"
                font.pixelSize: 14
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    text: "Discover ONVIF"
                    Layout.fillWidth: true
                    enabled: !rtspField.text.startsWith("rtsp://")
                    onClicked: {
                        onvifPopup.visible = true
                        if (frigateRef)
                            frigateRef.discoverOnvif()
                    }
                }

                Button {
                    text: "Test RTSP"
                    Layout.fillWidth: true
                    onClicked: {
                        if (!frigateRef) {
                            rtspStatus.text = "Frigate not ready"
                            rtspStatus.color = "red"
                            return
                        }

                        let url = getFinalRtspUrl()
                        rtspStatus.text = "Testing: " + url
                        rtspStatus.color = "yellow"

                        frigateRef.testRtsp(url)
                    }
                }
            }

            Text {
                id: rtspStatus
                Layout.fillWidth: true
                text: ""
                color: "white"
                font.pixelSize: 16
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    text: "Save"
                    Layout.fillWidth: true
                    onClicked: {
                        if (!frigateRef) {
                            rtspStatus.text = "Frigate not ready"
                            rtspStatus.color = "red"
                            return
                        }

                        let url = getFinalRtspUrl()
                        frigateRef.editCamera(idField.text, url)
                    }
                }

                Button {
                    text: "Use"
                    Layout.fillWidth: true
                    onClicked: {
                        if (!frigateRef) {
                            rtspStatus.text = "Frigate not ready"
                            rtspStatus.color = "red"
                            return
                        }

                        let url = getFinalRtspUrl()
                        frigateRef.applyNewCameraRtsp(idField.text, url)
                    }
                }

                Button {
                    text: "Cancel"
                    Layout.fillWidth: true
                    onClicked: closeRequested()
                }
            }
        }
    }

    OnvifDiscoveryPopup {
        id: onvifPopup
        visible: false
        frigateRef: editPopup.frigateRef
        addCameraPopupRef: editPopup

        onCameraSelected: function(address, username, password, rtsp) {
            ipField.text = address || ""
            userField.text = username || ""
            passField.text = password || ""
            rtspField.text = rtsp || ""
        }
    }

    Connections {
        target: frigateRef

        function onRtspTestResult(ok, message) {
            editPopup.rtspValid = ok

            if (ok) {
                rtspStatus.text = "RTSP Test Passed"
                rtspStatus.color = "lightgreen"
            } else {
                rtspStatus.text = "RTSP Test Failed: " + message
                rtspStatus.color = "red"
            }
        }

        function onCameraEditResult(ok, message) {
            if (ok)
                closeRequested()
        }
    }

    function getFinalRtspUrl() {
        if (rtspField.text.startsWith("rtsp://"))
            return rtspField.text

        if (ipField.text.length === 0)
            return ""

        let auth = ""
        if (username.length > 0 && password.length > 0)
            auth = username + ":" + password + "@"

        return "rtsp://" + auth + ipField.text +
               ":554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1"
    }
}
