import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: removePopup
    objectName: "RemoveCameraPopup"

    anchors.fill: parent
    z: 1

    signal closeRequested()
    signal cameraRemoved()

    property var popupManager
    property var frigateRef: null
    property string cameraId: ""
    property bool closing: false

    function forceClose() {
        if (closing)
            return
        closing = true

        // Preferred: PopupManager connection
        closeRequested()

        // Fallback: call manager directly
        if (popupManager && typeof popupManager.closePopup === "function")
            popupManager.closePopup()

        // Last resort: hide + destroy self
        visible = false
        Qt.callLater(function() {
            if (removePopup)
                removePopup.destroy()
        })
    }

    Rectangle {
        anchors.fill: parent
        color: "#00000099"
    }

    Rectangle {
        id: container
        width: 360
        height: 280
        radius: 8
        color: "#000000"

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -80

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 20
            spacing: 16

            Text {
                text: "Remove Camera"
                color: "white"
                font.pixelSize: 22
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                text: "Are you sure you want to remove this camera?"
                wrapMode: Text.WordWrap
                color: "#cccccc"
                font.pixelSize: 16
                Layout.fillWidth: true
            }

            Text {
                id: camLabel
                text: removePopup.cameraId
                color: "orange"
                font.pixelSize: 18
                Layout.alignment: Qt.AlignHCenter
            }

            Text {
                id: statusText
                text: ""
                color: "white"
                font.pixelSize: 14
                Layout.alignment: Qt.AlignHCenter
            }

            RowLayout {
                spacing: 12
                Layout.fillWidth: true

                Button {
                    id: removeBtn
                    text: "Remove"
                    Layout.fillWidth: true
                    enabled: !closing
                    onClicked: {
                        statusText.text = "Removing..."
                        statusText.color = "yellow"
                        removeBtn.enabled = false

                        if (frigateRef)
                            frigateRef.removeCamera(removePopup.cameraId)
                        else {
                            statusText.text = "Frigate not ready"
                            statusText.color = "red"
                            removeBtn.enabled = true
                        }
                    }
                }

                Button {
                    text: "Cancel"
                    Layout.fillWidth: true
                    enabled: !closing
                    onClicked: forceClose()
                }
            }
        }
    }

    Connections {
        target: frigateRef
        ignoreUnknownSignals: true

        function onCameraRemoveResult(ok, message) {
            statusText.text = message
            statusText.color = ok ? "lightgreen" : "red"

            // ALWAYS close this popup when the server answers
            forceClose()
            cameraRemoved()
        }
    }
}