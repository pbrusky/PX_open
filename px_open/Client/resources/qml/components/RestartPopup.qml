import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Popup {
    id: restartPopup
    modal: true
    focus: true
    width: 600
    height: 300
    closePolicy: Popup.NoAutoClose

    anchors.centerIn: Overlay.overlay

    background: Rectangle {
        color: "#111"
        radius: 12
        border.color: "#444"
        border.width: 1
    }

    ColumnLayout {
        anchors.fill: parent
        anchors.margins: 30
        spacing: 20

        Text {
            text: "Frigate is restarting…"
            color: "white"
            font.pixelSize: 40      // ⭐ BIGGER
            font.bold: true
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        Text {
            text: "Please wait while Frigate and go2rtc restart.\nCameras will reload automatically."
            color: "#cccccc"
            font.pixelSize: 20
            wrapMode: Text.WordWrap
            horizontalAlignment: Text.AlignHCenter
            Layout.fillWidth: true
        }

        BusyIndicator {
            Layout.alignment: Qt.AlignHCenter
            running: true
            width: 50
            height: 50
        }
    }
}
