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
    property var popupManager: null

    property string cameraId: ""
    property string cameraName: ""
    property string rtspUrl: ""
    property string username: ""
    property string password: ""

    Component.onCompleted: {
        nameField.text = cameraName
        rtspField.text = rtspUrl
        userField.text = username
        passField.text = password

        // Auto-fill IP field if RTSP contains host
        if (rtspUrl.startsWith("rtsp://")) {
            let withoutPrefix = rtspUrl.split("rtsp://")[1]
            let hostPart = withoutPrefix.includes("@")
                ? withoutPrefix.split("@")[1]
                : withoutPrefix

            let ip = hostPart.split("/")[0]
            ipField.text = ip
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#00000080"
    }

    Rectangle {
        id: container
        width: 480
        height: 520
        radius: 8
        color: "#202020"
        border.color: "#404040"
        border.width: 1

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

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
                id: nameField
                Layout.fillWidth: true
                placeholderText: "Camera Name"
                onTextChanged: editPopup.cameraName = text
            }

            TextField {
                id: ipField
                Layout.fillWidth: true
                placeholderText: "Camera IP address"
                onTextChanged: {
                    rtspField.text = getFinalRtspUrl()
                }
            }

            TextField {
                id: rtspField
                Layout.fillWidth: true
                placeholderText: "RTSP URL"
                onTextChanged: editPopup.rtspUrl = text
            }

            TextField {
                id: userField
                Layout.fillWidth: true
                placeholderText: "Username"
                onTextChanged: {
                    editPopup.username = text
                    rtspField.text = getFinalRtspUrl()
                }
            }

            TextField {
                id: passField
                Layout.fillWidth: true
                placeholderText: "Password"
                echoMode: TextInput.Password
                onTextChanged: {
                    editPopup.password = text
                    rtspField.text = getFinalRtspUrl()
                }
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    text: "Discover ONVIF"
                    Layout.fillWidth: true
                    onClicked: onvifLoader.active = true
                }

                Button {
                    text: "Test RTSP"
                    Layout.fillWidth: true
                    onClicked: {
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
                        frigateRef.editCamera(
                            editPopup.cameraId,
                            getFinalRtspUrl()
                        )
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

    Loader {
        id: onvifLoader
        active: false
        source: "qrc:/app/resources/qml/components/popups/OnvifDiscoveryPopup.qml"

        onLoaded: {
            item.visible = true
            item.frigateRef = editPopup.frigateRef
            item.addCameraPopupRef = editPopup

            item.cameraSelected.connect(function(address, username, password, rtsp) {
                ipField.text = address || ""
                userField.text = username || ""
                passField.text = password || ""
                rtspField.text = rtsp || ""
            })
        }
    }

    Connections {
        target: frigateRef

        function onRtspTestResult(ok, message) {
            rtspStatus.text = message
            rtspStatus.color = ok ? "#66CC66" : "red"
        }

        function onCameraEditResult(ok, message) {
            if (ok)
                closeRequested()
            else {
                rtspStatus.text = message
                rtspStatus.color = "red"
            }
        }
    }

    function getFinalRtspUrl() {
        // If user manually typed a full RTSP, use it
        if (rtspField.text.startsWith("rtsp://"))
            return rtspField.text

        if (ipField.text.length === 0)
            return ""

        let auth = ""
        if (userField.text.length > 0 && passField.text.length > 0)
            auth = userField.text + ":" + passField.text + "@"

        return "rtsp://" + auth + ipField.text +
               ":554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1"
    }
}
