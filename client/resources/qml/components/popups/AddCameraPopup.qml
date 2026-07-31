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
    property string mainStreamUrl: ""
    property string subStreamUrl: ""
    property string username: ""
    property string password: ""
    property bool enableRecording: true

    // Aliases so ONVIF / other popups can fill fields
    property alias ipInput: ipInput
    property alias userInput: userInput
    property alias passInput: passInput
    property alias mainRtspInput: mainRtspInput
    property alias subRtspInput: subRtspInput
    property alias idInput: idInput

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
        width: 540
        height: 640
        radius: 6
        color: "#111"
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 12

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
                onTextChanged: {
                    if (!mainRtspInput.text.startsWith("rtsp://"))
                        mainRtspInput.text = buildMainFromIp()
                    if (!subRtspInput.text.startsWith("rtsp://"))
                        subRtspInput.text = buildSubFromIp()
                }
            }

            Text {
                text: "Main stream (fullscreen / record)"
                color: "#aaa"
                font.pixelSize: 13
            }

            TextField {
                id: mainRtspInput
                Layout.fillWidth: true
                placeholderText: "Main RTSP (Channels/101)"
                onTextChanged: popupRoot.mainStreamUrl = text
            }

            Text {
                text: "Sub stream (grid / multi-view)"
                color: "#aaa"
                font.pixelSize: 13
            }

            TextField {
                id: subRtspInput
                Layout.fillWidth: true
                placeholderText: "Sub RTSP (Channels/102) — optional"
                onTextChanged: popupRoot.subStreamUrl = text
            }

            TextField {
                id: userInput
                Layout.fillWidth: true
                placeholderText: "Username"
                onTextChanged: {
                    popupRoot.username = text
                    if (ipInput.text.length > 0) {
                        mainRtspInput.text = buildMainFromIp()
                        subRtspInput.text = buildSubFromIp()
                    }
                }
            }

            TextField {
                id: passInput
                Layout.fillWidth: true
                placeholderText: "Password"
                echoMode: TextInput.Password
                onTextChanged: {
                    popupRoot.password = text
                    if (ipInput.text.length > 0) {
                        mainRtspInput.text = buildMainFromIp()
                        subRtspInput.text = buildSubFromIp()
                    }
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

                Button {
                    text: "Discover ONVIF"
                    Layout.fillWidth: true
                    onClicked: onvifLoader.active = true
                }

                Button {
                    text: "Test Main"
                    Layout.fillWidth: true
                    onClicked: {
                        var url = mainRtspInput.text.startsWith("rtsp://")
                                   ? mainRtspInput.text
                                   : getMainUrl()

                        if (!url || url === "") {
                            rtspStatus.text = "Main RTSP required"
                            rtspStatus.color = "red"
                            return
                        }

                        rtspStatus.text = "Testing main: " + url
                        rtspStatus.color = "yellow"

                        if (frigateRef)
                            frigateRef.testRtsp(url)
                        else {
                            rtspStatus.text = "Backend not ready"
                            rtspStatus.color = "red"
                        }
                    }
                }

                Button {
                    text: "Test Sub"
                    Layout.fillWidth: true
                    onClicked: {
                        var url = subRtspInput.text.startsWith("rtsp://")
                                   ? subRtspInput.text
                                   : getSubUrl()

                        if (!url || url === "") {
                            rtspStatus.text = "Sub RTSP empty"
                            rtspStatus.color = "red"
                            return
                        }

                        rtspStatus.text = "Testing sub: " + url
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
                font.pixelSize: 14
                wrapMode: Text.Wrap
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

                        var mainUrl = mainRtspInput.text.startsWith("rtsp://")
                                      ? mainRtspInput.text
                                      : getMainUrl()

                        var subUrl = subRtspInput.text.startsWith("rtsp://")
                                     ? subRtspInput.text
                                     : getSubUrl()

                        if (!mainUrl || mainUrl === "") {
                            rtspStatus.text = "Main RTSP required"
                            rtspStatus.color = "red"
                            return
                        }

                        if (!subUrl || subUrl === "")
                            subUrl = mainUrl

                        rtspStatus.text = "Adding camera…"
                        rtspStatus.color = "yellow"
                        saveButton.enabled = false

                        if (frigateRef)
                            frigateRef.addCamera(popupRoot.cameraId, mainUrl, subUrl, popupRoot.enableRecording)
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

        function onCameraAddResult(ok, message) {
            saveButton.enabled = true

            if (ok) {
                rtspStatus.text = "Camera added successfully"
                rtspStatus.color = "lightgreen"

                if (popupRoot.popupManager) {
                    popupRoot.popupManager.closePopup()
                    popupRoot.popupManager.openRestartFrigatePopup()
                } else {
                    popupRoot.visible = false
                }
            } else {
                rtspStatus.text = message
                rtspStatus.color = "red"
            }
        }
    }

    function authPrefix() {
        if (username.length > 0 && password.length > 0)
            return username + ":" + password + "@"
        return ""
    }

    function buildMainFromIp() {
        if (ipInput.text.length === 0)
            return ""
        return "rtsp://" + authPrefix() + ipInput.text +
               ":554/Streaming/Channels/101?transportmode=unicast&profile=Profile_1"
    }

    function buildSubFromIp() {
        if (ipInput.text.length === 0)
            return ""
        return "rtsp://" + authPrefix() + ipInput.text +
               ":554/Streaming/Channels/102?transportmode=unicast&profile=Profile_1"
    }

    function getMainUrl() {
        if (mainStreamUrl.startsWith("rtsp://"))
            return mainStreamUrl
        if (mainRtspInput.text.startsWith("rtsp://"))
            return mainRtspInput.text
        return buildMainFromIp()
    }

    function getSubUrl() {
        if (subStreamUrl.startsWith("rtsp://"))
            return subStreamUrl
        if (subRtspInput.text.startsWith("rtsp://"))
            return subRtspInput.text
        return buildSubFromIp()
    }
}