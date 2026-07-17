import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: popup
    modal: true
    width: 520
    height: 480
    focus: true
    closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside

    background: Rectangle {
        color: "#111"
        radius: 6
    }

    onClosed: {
        popup.visible = false
        popup.focus = false
    }

    // Backend reference (must be set from ServerView: frigateRef: frigate)
    property var frigateRef: frigate

    property string cameraId: ""
    property string streamUrl: ""
    property string username: ""
    property string password: ""
    property bool enableRecording: true

    property alias ipField: ipInput
    property alias rtspField: rtspInput
    property alias userField: userInput
    property alias passField: passInput

    function getFinalRtspUrl() {
        if (streamUrl.startsWith("rtsp://"))
            return streamUrl

        if (ipInput.text.length === 0)
            return ""

        let auth = ""
        if (username.length > 0 && password.length > 0)
            auth = username + ":" + password + "@"

        return "rtsp://" + auth + ipInput.text +
               ":554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1"
    }

    onOpened: {
        cameraId = ""
        streamUrl = ""
        username = ""
        password = ""
        enableRecording = true

        idInput.text = ""
        ipInput.text = ""
        rtspInput.text = ""
        userInput.text = ""
        passInput.text = ""

        rtspStatus.text = ""
        rtspStatus.color = "white"
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 20
        spacing: 14

        Text {
            text: "Add Camera"
            font.pixelSize: 24
            font.bold: true
            color: "white"
        }

        TextField {
            id: idInput
            Layout.fillWidth: true
            placeholderText: "Camera ID (e.g. driveway)"
            onTextChanged: popup.cameraId = text
        }

        TextField {
            id: ipInput
            Layout.fillWidth: true
            placeholderText: "Camera IP address"
            enabled: !rtspInput.text.startsWith("rtsp://")
            onTextChanged: {
                if (!rtspInput.text.startsWith("rtsp://"))
                    rtspInput.text = getFinalRtspUrl()
            }
        }

        TextField {
            id: rtspInput
            Layout.fillWidth: true
            placeholderText: "RTSP URL"
            onTextChanged: popup.streamUrl = text
        }

        TextField {
            id: userInput
            Layout.fillWidth: true
            placeholderText: "Username"
            enabled: !rtspInput.text.startsWith("rtsp://")
            onTextChanged: {
                popup.username = text
                if (!rtspInput.text.startsWith("rtsp://"))
                    rtspInput.text = getFinalRtspUrl()
            }
        }

        TextField {
            id: passInput
            Layout.fillWidth: true
            placeholderText: "Password"
            echoMode: TextInput.Password
            enabled: !rtspInput.text.startsWith("rtsp://")
            onTextChanged: {
                popup.password = text
                if (!rtspInput.text.startsWith("rtsp://"))
                    rtspInput.text = getFinalRtspUrl()
            }
        }

        CheckBox {
            id: recCheck
            text: "Enable Recording"
            checked: enableRecording
            onCheckedChanged: enableRecording = checked
        }

        Text {
            visible: rtspInput.text.startsWith("rtsp://")
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
                enabled: !rtspInput.text.startsWith("rtsp://")
                onClicked: onvifPopup.open()
            }

            Button {
                text: "Test RTSP"
                Layout.fillWidth: true
                onClicked: {
                    let url = getFinalRtspUrl()

                    if (!url || url === "") {
                        rtspStatus.text = "RTSP URL required to test"
                        rtspStatus.color = "red"
                        return
                    }

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
                    if (popup.cameraId.length === 0) {
                        rtspStatus.text = "Camera ID required"
                        rtspStatus.color = "red"
                        return
                    }

                    let url = getFinalRtspUrl()
                    frigateRef.addCamera(popup.cameraId, url, enableRecording)
                    popup.close()
                }
            }

            Button {
                text: "Cancel"
                Layout.fillWidth: true
                onClicked: popup.close()
            }
        }

        Connections {
            target: frigateRef

            function onRtspTestResult(ok, message) {
                if (ok) {
                    rtspStatus.text = "RTSP Test Passed: " + message
                    rtspStatus.color = "lightgreen"
                } else {
                    rtspStatus.text = "RTSP Test Failed: " + message
                    rtspStatus.color = "red"
                }
            }
        }
    }

    OnvifDiscoveryPopup {
        id: onvifPopup
        frigateRef: popup.frigateRef
        addCameraPopupRef: popup
    }
}
