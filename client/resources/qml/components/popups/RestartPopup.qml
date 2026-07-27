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
    
    property var frigateRef

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
            font.pixelSize: 40
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

        //
        // ⭐ White + larger custom spinner
        //
        Item {
            width: 70
            height: 70
            Layout.alignment: Qt.AlignHCenter

            Canvas {
                id: spinnerCanvas
                anchors.fill: parent

                onPaint: {
                    var ctx = getContext("2d")
                    ctx.reset()

                    ctx.lineWidth = 6
                    ctx.strokeStyle = "white"   // ⭐ WHITE SPINNER

                    ctx.beginPath()
                    ctx.arc(width/2, height/2, width/3, 0, Math.PI * 1.5)
                    ctx.stroke()
                }
            }

            RotationAnimator on rotation {
                from: 0
                to: 360
                duration: 900
                loops: Animation.Infinite
            }
        }
    }
}
