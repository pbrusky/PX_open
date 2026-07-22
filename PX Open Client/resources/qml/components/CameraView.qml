import QtQuick 2.15
import QtQuick.Controls 2.15
import QtMultimedia 6.5

Rectangle {
    id: view
    anchors.fill: parent
    color: "black"

    property string streamUrl: ""

    MediaPlayer {
        id: player
        source: streamUrl
        autoPlay: true
    }

    VideoOutput {
        anchors.fill: parent
        source: player
    }
}
