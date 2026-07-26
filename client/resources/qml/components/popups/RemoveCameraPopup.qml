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

    // ⭐ REQUIRED — MainWindow passes popupManager into this popup
    property var popupManager

    property var frigateRef: null
    property string cameraId: ""

    Rectangle {
        anchors.fill: parent
        color: "#000000AA"
    }

    Rectangle {
        id: container
        width: 360
        radius: 8
        color: "#1A1A1A"
        x: (parent.width - width) / 2
        y: (parent.height - implicitHeight) / 2

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

                if (mainWindow && mainWindow.restartPopup) {
                    mainWindow.restartPopup.visible = true
                    mainWindow.frigatePollTimer.start()
                }
            }
        }
    }
}
