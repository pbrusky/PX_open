import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: removePopup
    objectName: "RemoveCameraPopup"

    anchors.fill: parent
    z: 999999

    signal closeRequested()
    signal cameraRemoved()

    property var popupManager
    property var frigateRef: null
    property string cameraId: ""

    // Background overlay (not fullscreen popup)
    Rectangle {
        anchors.fill: parent
        color: "#00000088"
    }

    // Centered popup box, moved slightly upward
    Rectangle {
        id: container
        width: 360
        radius: 8
        color: "#000000"

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter

        // ⭐ Move popup upward
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
                    text: "Remove"
                    Layout.fillWidth: true
                    onClicked: {
                        statusText.text = "Removing..."
                        statusText.color = "yellow"

                        if (frigateRef)
                            frigateRef.removeCamera(removePopup.cameraId)
                        else {
                            statusText.text = "Frigate not ready"
                            statusText.color = "red"
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
        target: frigateRef

        function onCameraRemoveResult(ok, message) {
            statusText.text = message
            statusText.color = ok ? "lightgreen" : "red"

            if (ok) {
                closeRequested()
                removePopup.cameraRemoved()
            }
        }
    }
}
