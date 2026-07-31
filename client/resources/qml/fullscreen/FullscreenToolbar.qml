import QtQuick 2.15
import QtQuick.Controls 2.15

Rectangle {
    id: toolbar
    height: 48
    width: parent.width
    color: "#000000AA"
    anchors.bottom: parent.bottom
    z: 9999

    property alias playing: playPauseButton.playing
    property var onExitFullscreen
    property var onTogglePlay
    property var onToggleAudio
    property var onSpeedChanged

    opacity: 0.0
    visible: true

    Behavior on opacity {
        NumberAnimation { duration: 200; easing.type: Easing.InOutQuad }
    }

    //
    // Auto-hide logic
    //
    Timer {
        id: hideTimer
        interval: 2000
        repeat: false
        onTriggered: toolbar.opacity = 0.0
    }

    function show() {
        toolbar.opacity = 1.0
        hideTimer.restart()
    }

    MouseArea {
        anchors.fill: parent
        hoverEnabled: true
        onPositionChanged: toolbar.show()
    }

    Row {
        anchors.fill: parent
        anchors.margins: 8
        spacing: 16

        //
        // Play / Pause
        //
        IconButton {
            id: playPauseButton
            property bool playing: true

            icon: playing
                  ? "qrc:/app/assets/icons/nx/pause.svg"
                  : "qrc:/app/assets/icons/nx/play.svg"

            onClicked: {
                playing = !playing
                if (toolbar.onTogglePlay)
                    toolbar.onTogglePlay(playing)
            }
        }

        //
        // Audio toggle
        //
        IconButton {
            id: audioButton
            property bool muted: false

            icon: muted
                  ? "qrc:/app/assets/icons/nx/audio-off.svg"
                  : "qrc:/app/assets/icons/nx/audio-on.svg"

            onClicked: {
                muted = !muted
                if (toolbar.onToggleAudio)
                    toolbar.onToggleAudio(muted)
            }
        }

        //
        // Speed control
        //
        ComboBox {
            id: speedBox
            width: 100
            model: ["0.25x", "0.5x", "1x", "2x", "4x"]

            onCurrentTextChanged: {
                if (toolbar.onSpeedChanged)
                    toolbar.onSpeedChanged(currentText)
            }
        }

        // Simple spacer to push exit button to the right
        Item {
            width: 1
            height: 1
        }

        //
        // Exit fullscreen
        //
        IconButton {
            id: exitButton
            icon: "qrc:/app/assets/icons/nx/close.svg"
            onClicked: {
                if (toolbar.onExitFullscreen)
                    toolbar.onExitFullscreen()
            }
        }
    }
}
