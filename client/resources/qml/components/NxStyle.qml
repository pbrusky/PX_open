pragma Singleton
import QtQuick 2.15

QtObject {
    readonly property color background: "#111315"
    readonly property color panel: "#1b1e21"
    readonly property color panelAlt: "#22262a"
    readonly property color surface: "#272c31"
    readonly property color surfaceAlt: "#22262a"
    readonly property color hover: "#303840"
    readonly property color selected: "#173e5e"
    readonly property color border: "#3a4149"
    readonly property color borderStrong: "#4b545e"
    readonly property color text: "#f1f3f5"
    readonly property color textMuted: "#a7afb7"
    readonly property color accent: "#0c79c3"
    readonly property color accentHover: "#2395df"
    readonly property color recording: "#23a55a"
    readonly property color event: "#f5b82e"
    readonly property color motion: "#ff7a1a"
    readonly property color playhead: "#68b5f0"
    readonly property color online: "#2fb344"
    readonly property color offline: "#d94a4a"
    readonly property color warning: "#f5b82e"
    readonly property color danger: "#d94a4a"
    readonly property color ghostBg: "#272c31dd"
    readonly property color ghostBorder: "#2395df"
    readonly property color surfaceHover: "#303840"
    readonly property color selectedLegacy: "#173e5e"

    readonly property int barHeight: 48
    readonly property int sidebarWidth: 260
    readonly property int timelineHeight: 150
    readonly property int radius: 4
    readonly property int smallRadius: 3
    readonly property int controlHeight: 32
    readonly property int spacing: 8
}
