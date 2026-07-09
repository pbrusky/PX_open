import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: removePopup
    modal: true
    focus: true
    width: 360
    height: implicitHeight
    padding: 20

    background: Rectangle {
        color: "#1A1A1A"
        radius: 8
    }

    // Set by ServerView before opening
    property var frigateRef: null
    property string cameraId: ""

    signal cameraRemoved()

    ColumnLayout {
        spacing: 16
        width: parent.width

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
                onClicked: removePopup.close()
            }
        }
    }

    //
    // Modern Connections syntax (Qt 6 safe)
    //
    Connections {
        target: frigate

        function onCameraRemoveResult(ok, message) {
            statusText.text = message
            statusText.color = ok ? "lightgreen" : "red"

            if (ok) {
                removePopup.close()
                removePopup.cameraRemoved()
            }
        }
    }
}

