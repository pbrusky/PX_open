import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: popupRoot
    objectName: "AddCameraPopup"

    anchors.fill: parent
    z: 999999

    signal closeRequested()

    property var popupManager
    property var frigateRef

    property string cameraId: ""
    property string streamUrl: ""
    property string username: ""
    property string password: ""
    property bool enableRecording: true

    property alias ipField: ipInput
    property alias rtspField: rtspInput
    property alias userField: userInput
    property alias passField: passInput

    //
    // ⭐ ONVIF CHILD POPUP (NOT PopupManager)
    //
    Loader {
        id: onvifLoader
        active: false
        anchors.fill: parent
        z: 1000000
        source: "qrc:/app/resources/qml/components/popups/OnvifDiscoveryPopup.qml"

        onLoaded: {
            item.frigateRef = popupRoot.frigateRef
            item.addCameraPopupRef = popupRoot

            item.closeRequested.connect(function() {
                onvifLoader.active = false
            })
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000AA"
    }

    Rectangle {
        id: container
        width: 520
        height: 480
        radius: 6
        color: "#111"
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

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
                onTextChanged: popupRoot.cameraId = text
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
                onTextChanged: popupRoot.streamUrl = text
            }

            TextField {
                id: userInput
                Layout.fillWidth: true
                placeholderText: "Username"
                enabled: !rtspInput.text.startsWith("rtsp://")
                onTextChanged: {
                    popupRoot.username = text
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
                    popupRoot.password = text
                    if (!rtspInput.text.startsWith("rtsp://"))
                        rtspInput.text = getFinalRtspUrl()
                }
            }

            CheckBox {
                id: recCheck
                text: "Enable Recording"
                checked: popupRoot.enableRecording
                onCheckedChanged: popupRoot.enableRecording = checked
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                //
                // ⭐ ONVIF opens inside AddCameraPopup (always enabled)
                //
                Button {
                    text: "Discover ONVIF"
                    Layout.fillWidth: true
                    enabled: true
                    onClicked: onvifLoader.active = true
                }

                Button {
                    text: "Test RTSP"
                    Layout.fillWidth: true
                    onClicked: {
                        let url = getFinalRtspUrl()

                        if (!url || url === "") {
                            rtspStatus.text = "RTSP URL required"
                            rtspStatus.color = "red"
                            return
                        }

                        rtspStatus.text = "Testing: " + url
                        rtspStatus.color = "yellow"

                        if (frigateRef)
                            frigateRef.testRtsp(url)
                        else {
                            rtspStatus.text = "Backend not ready"
                            rtspStatus.color = "red"
                        }
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
                    id: saveButton
                    text: "Save"
                    Layout.fillWidth: true

                    onClicked: {
                        if (popupRoot.cameraId.length === 0) {
                            rtspStatus.text = "Camera ID required"
                            rtspStatus.color = "red"
                            return
                        }

                        let url = getFinalRtspUrl()

                        rtspStatus.text = "Adding camera…"
                        rtspStatus.color = "yellow"
                        saveButton.enabled = false

                        if (frigateRef)
                            frigateRef.addCamera(popupRoot.cameraId, url, popupRoot.enableRecording)
                        else {
                            rtspStatus.text = "Backend not ready"
                            rtspStatus.color = "red"
                            saveButton.enabled = true
                        }
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

    Connections {
        target: popupRoot.frigateRef
        ignoreUnknownSignals: true

        function onRtspTestResult(ok, message) {
            rtspStatus.text = message
            rtspStatus.color = ok ? "lightgreen" : "red"
        }
    }

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
}
