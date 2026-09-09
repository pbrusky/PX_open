import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15

Item {
    id: popupRoot
    objectName: "ConfigEditorPopup"
    anchors.fill: parent
    z: 999999

    signal closeRequested()

    property var popupManager
    property var frigateRef

    property string configType: "frigate"
    property string filePath: ""
    property string statusText: ""
    property bool loading: false
    property bool saving: false

    property bool yamlValid: false
    property string yamlMessage: ""

    function titleText() {
        return configType === "go2rtc" ? "Edit go2rtc config" : "Edit Frigate config.yml"
    }

    // Lightweight YAML checks (not a full parser — catches common mistakes)
    function validateYaml(text) {
        if (text === undefined || text === null)
            return { ok: false, msg: "No content" }

        var s = "" + text
        if (!s.trim())
            return { ok: false, msg: "Empty document" }

        var lines = s.split("\n")
        var i
        for (i = 0; i < lines.length; i++) {
            var line = lines[i]
            var lineNo = i + 1

            if (line.indexOf("\t") >= 0)
                return { ok: false, msg: "Line " + lineNo + ": tabs not allowed (use spaces)" }

            // Strip comments for quote checks on this line
            var code = line
            var hash = line.indexOf("#")
            if (hash >= 0) {
                // crude: ignore # inside quotes later; good enough for Frigate configs
                var before = line.substring(0, hash)
                var sq = (before.split("'").length - 1)
                var dq = (before.split('"').length - 1)
                if ((sq % 2 === 0) && (dq % 2 === 0))
                    code = before
            }

            // Odd number of unescaped quotes on a line is suspicious
            var doubleQuotes = code.split('"').length - 1
            var singleQuotes = code.split("'").length - 1
            if (doubleQuotes % 2 !== 0)
                return { ok: false, msg: "Line " + lineNo + ": unbalanced double quote" }
            if (singleQuotes % 2 !== 0)
                return { ok: false, msg: "Line " + lineNo + ": unbalanced single quote" }
        }

        // Whole-doc quote balance (simple)
        function countUnescaped(str, ch) {
            var n = 0
            for (var j = 0; j < str.length; j++) {
                if (str[j] === ch && (j === 0 || str[j - 1] !== "\\"))
                    n++
            }
            return n
        }
        // Skip full-doc quote check on multi-line; line checks are enough

        // Indentation: only spaces, consistent steps of 2
        var indents = []
        for (i = 0; i < lines.length; i++) {
            var L = lines[i]
            if (!L.trim() || L.trim().charAt(0) === "#")
                continue
            var m = L.match(/^( *)/)
            var ind = m ? m[1].length : 0
            if (ind % 2 !== 0)
                return { ok: false, msg: "Line " + (i + 1) + ": indent should be multiples of 2 spaces" }
            indents.push(ind)
        }

        return { ok: true, msg: "YAML looks valid" }
    }

    function revalidate() {
        var r = validateYaml(editor.text)
        yamlValid = r.ok
        yamlMessage = r.msg
        if (!loading && !saving)
            statusText = r.msg
    }

    function loadConfig() {
        if (!frigateRef)
            return
        loading = true
        statusText = "Loading..."
        if (configType === "go2rtc")
            frigateRef.loadGo2rtcConfig()
        else
            frigateRef.loadFrigateConfig()
    }

    function saveConfig(doRestart) {
        if (!frigateRef)
            return
        revalidate()
        if (!yamlValid) {
            statusText = "Fix YAML errors before saving: " + yamlMessage
            return
        }
        saving = true
        statusText = doRestart ? "Saving and restarting..." : "Saving..."
        var text = editor.text
        if (configType === "go2rtc")
            frigateRef.saveGo2rtcConfig(text, doRestart)
        else
            frigateRef.saveFrigateConfig(text, doRestart)
    }

    Component.onCompleted: loadConfig()

    Connections {
        target: frigateRef
        ignoreUnknownSignals: true

        function onFrigateConfigLoaded(ok, content, path, message) {
            if (popupRoot.configType !== "frigate")
                return
            loading = false
            filePath = path || ""
            if (ok) {
                editor.text = content
                revalidate()
                statusText = (path ? ("Loaded: " + path + " — ") : "") + yamlMessage
            } else {
                statusText = message || "Load failed"
                yamlValid = false
            }
        }

        function onFrigateConfigSaved(ok, message) {
            if (popupRoot.configType !== "frigate")
                return
            saving = false
            statusText = message || (ok ? "Saved" : "Save failed")
        }

        function onGo2rtcConfigLoaded(ok, content, path, message) {
            if (popupRoot.configType !== "go2rtc")
                return
            loading = false
            filePath = path || ""
            if (ok) {
                editor.text = content
                revalidate()
                statusText = (path ? ("Loaded: " + path + " — ") : "") + yamlMessage
            } else {
                statusText = message || "Load failed"
                yamlValid = false
            }
        }

        function onGo2rtcConfigSaved(ok, message) {
            if (popupRoot.configType !== "go2rtc")
                return
            saving = false
            statusText = message || (ok ? "Saved" : "Save failed")
        }
    }

    Rectangle {
        anchors.fill: parent
        color: "#000000AA"
    }

    Rectangle {
        id: container
        width: Math.min(parent.width - 40, 900)
        height: Math.min(parent.height - 40, 700)
        radius: 6
        color: "#111"
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2

        ColumnLayout {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Text {
                text: popupRoot.titleText()
                color: "white"
                font.pixelSize: 22
                font.bold: true
            }

            Text {
                text: filePath !== "" ? filePath : " "
                color: "#aaa"
                font.pixelSize: 12
                elide: Text.ElideMiddle
                Layout.fillWidth: true
            }

            Text {
                text: "Invalid YAML can stop Frigate. A backup is created on the server before save."
                color: "#f0c040"
                font.pixelSize: 12
                wrapMode: Text.WordWrap
                Layout.fillWidth: true
            }

            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                radius: 4
                color: "#1a1a1a"
                border.width: 2
                border.color: loading || saving ? "#555"
                              : (yamlValid ? "#4CAF50" : "#E53935")

                ScrollView {
                    anchors.fill: parent
                    anchors.margins: 4
                    clip: true

                    TextArea {
                        id: editor
                        width: Math.max(popupRoot.width * 0.5, container.width - 16)
                        height: Math.max(implicitHeight, 400)
                        wrapMode: TextEdit.NoWrap
                        selectByMouse: true
                        font.family: "Consolas"
                        font.pixelSize: 13
                        // Green letters when valid, soft red when invalid (VS Code–ish feedback)
                        color: loading || saving ? "#e0e0e0"
                               : (yamlValid ? "#A5D6A7" : "#EF9A9A")
                        background: Item {}
                        readOnly: popupRoot.loading || popupRoot.saving

                        onTextChanged: {
                            if (!popupRoot.loading)
                                validateTimer.restart()
                        }
                    }
                }
            }

            Text {
                text: statusText
                color: loading || saving ? "#9cdcfe"
                       : (yamlValid ? "#81C784" : "#EF5350")
                font.pixelSize: 12
                Layout.fillWidth: true
                elide: Text.ElideRight
            }

            RowLayout {
                Layout.fillWidth: true
                spacing: 10

                Button {
                    text: "Reload"
                    enabled: !loading && !saving
                    onClicked: loadConfig()
                }

                Item { Layout.fillWidth: true }

                Button {
                    text: "Save"
                    enabled: !loading && !saving && yamlValid
                    onClicked: saveConfig(false)
                }

                Button {
                    text: "Save & Restart"
                    enabled: !loading && !saving && yamlValid
                    onClicked: saveConfig(true)
                }

                Button {
                    text: "Close"
                    onClicked: {
                        if (popupManager && popupManager.closePopup)
                            popupManager.closePopup()
                        closeRequested()
                    }
                }
            }
        }
    }

    Timer {
        id: validateTimer
        interval: 200
        repeat: false
        onTriggered: revalidate()
    }
}