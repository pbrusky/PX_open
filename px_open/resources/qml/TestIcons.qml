import QtQuick 2.15

GridView {
    anchors.fill: parent
    cellWidth: 80
    cellHeight: 80
    model: [
        "play", "pause", "camera", "events", "exit_fullscreen",
        "fastforward", "fullscreen", "home", "rewind", "search",
        "server", "settings", "stop", "timeline", "user"
    ]

    delegate: IconButton {
        iconName: modelData
    }
}
