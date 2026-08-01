import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: restartPopup
    anchors.fill: parent
    visible: false
    z: 2000000

    property var frigateRef

    function open() {
        visible = true
        z = 2000000
    }

    function close() {
        visible = false
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000DD"
    }

    Rectangle {
        width: 600
        height: 300
        radius: 12
        color: "#111"
        border.color: "#444"
        border.width: 1
        anchors.centerIn: parent

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 30
            spacing: 20

            Text {
                text: "Frigate is restarting…"
                color: "white"
                font.pixelSize: 36
                font.bold: true
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            Text {
                text: "Please wait while Frigate and go2rtc restart.\nCameras will reload automatically."
                color: "#cccccc"
                font.pixelSize: 18
                wrapMode: Text.WordWrap
                horizontalAlignment: Text.AlignHCenter
                Layout.fillWidth: true
            }

            Item {
                width: 70
                height: 70
                Layout.alignment: Qt.AlignHCenter

                Canvas {
                    anchors.fill: parent
                    onPaint: {
                        var ctx = getContext("2d")
                        ctx.reset()
                        ctx.lineWidth = 6
                        ctx.strokeStyle = "white"
                        ctx.beginPath()
                        ctx.arc(width / 2, height / 2, width / 3, 0, Math.PI * 1.5)
                        ctx.stroke()
                    }
                    Component.onCompleted: requestPaint()
                }

                RotationAnimator on rotation {
                    from: 0
                    to: 360
                    duration: 900
                    loops: Animation.Infinite
                    running: restartPopup.visible
                }
            }
        }
    }
}