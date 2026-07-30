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

    // Centered popup box - solid black
    Rectangle {
        id: container
        width: 360
        height: 280          // Optional: give it a fixed height for better look
        radius: 8
        color: "#000000"     // Solid black

        anchors.horizontalCenter: parent.horizontalCenter
        anchors.verticalCenter: parent.verticalCenter
        anchors.verticalCenterOffset: -80   // Moved slightly upward (as before)

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

    // Optional: Click outside the popup to close (nice UX)
    MouseArea {
        anchors.fill: parent
        onClicked: closeRequested()
        z: -1   // Behind the popup
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