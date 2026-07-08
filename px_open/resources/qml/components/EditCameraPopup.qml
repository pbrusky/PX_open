import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: popup
    modal: true
    width: 480
    height: 480
    focus: true
    background: Rectangle { color: "#111"; radius: 8 }

    property var frigateRef: null

    property string cameraId: ""
    property string rtspUrl: ""
    property string username: ""
    property string password: ""
    property bool rtspValid: true

    //
    // ⭐ Smart RTSP builder
    //
    function getFinalRtspUrl() {
        // If user typed a full RTSP URL, use it directly
        if (rtspField.text.startsWith("rtsp://"))
            return rtspField.text

        // Otherwise build from fields
        if (ipField.text.length === 0)
            return ""

        let auth = ""
        if (username.length > 0 && password.length > 0)
            auth = username + ":" + password + "@"

        return "rtsp://" + auth + ipField.text +
               ":554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1"
    }

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

        // ⭐ Camera ID (read-only)
        TextField {
            id: idField
            Layout.fillWidth: true
            placeholderText: "Camera ID"
            text: popup.cameraId
            readOnly: true
        }

        // ⭐ IP field (disabled when full RTSP URL is detected)
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

        // ⭐ RTSP field
        TextField {
            id: rtspField
            Layout.fillWidth: true
            placeholderText: "RTSP URL"
            text: popup.rtspUrl
            onTextChanged: popup.rtspUrl = text
        }

        // ⭐ Username (disabled when full RTSP URL is detected)
        TextField {
            id: userField
            Layout.fillWidth: true
            placeholderText: "Username"
            text: popup.username
            enabled: !rtspField.text.startsWith("rtsp://")
            onTextChanged: {
                popup.username = text
                if (!rtspField.text.startsWith("rtsp://"))
                    rtspField.text = getFinalRtspUrl()
            }
        }

        // ⭐ Password (disabled when full RTSP URL is detected)
        TextField {
            id: passField
            Layout.fillWidth: true
            placeholderText: "Password"
            echoMode: TextInput.Password
            text: popup.password
            enabled: !rtspField.text.startsWith("rtsp://")
            onTextChanged: {
                popup.password = text
                if (!rtspField.text.startsWith("rtsp://"))
                    rtspField.text = getFinalRtspUrl()
            }
        }

        // ⭐ Full RTSP URL indicator
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
                    onvifPopup.open()
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

        // ⭐ RTSP status indicator
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

            // ⭐ Save button
            Button {
                text: "Save"
                Layout.fillWidth: true
                onClicked: {
                    if (!frigateRef) {
                        rtspStatus.text = "Frigate not ready"
                        rtspStatus.color = "red"
                        return
                    }

                    if (idField.text.length === 0) {
                        rtspStatus.text = "Camera ID required"
                        rtspStatus.color = "red"
                        return
                    }

                    let url = getFinalRtspUrl()
                    frigateRef.editCamera(idField.text, url)
                }
            }

            // ⭐ Use button (writes RTSP into Frigate + go2rtc)
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
                onClicked: popup.close()
            }
        }
    }

    // ⭐ ONVIF popup
    OnvifDiscoveryPopup {
        id: onvifPopup
        frigateRef: popup.frigateRef
        addCameraPopupRef: popup

        onCameraSelected: function(address, username, password, rtsp) {
            ipField.text = address || ""
            userField.text = username || ""
            passField.text = password || ""
            rtspField.text = rtsp || ""
        }
    }

    // ⭐ RTSP test results
    Connections {
        target: frigate

        function onRtspTestResult(ok, message) {
            popup.rtspValid = ok

            if (ok) {
                rtspStatus.text = "RTSP Test Passed"
                rtspStatus.color = "lightgreen"
            } else {
                rtspStatus.text = "RTSP Test Failed: " + message
                rtspStatus.color = "red"
            }
        }

        // ⭐ Close popup after successful Save or Use
        function onCameraEditResult(ok, message) {
            if (ok)
                popup.close()
        }
    }
}
