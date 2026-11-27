import QtQuick 2.15
import QtQuick.Controls 2.15
import QtQuick.Layouts 1.15
import QtCore
import PxOpen 1.0

Item {
    id: tree

    property var frigateRef
    property var cameraList: []
    property string serverKey: ""
    property string selectedCameraId: ""

    signal cameraSelected(string cameraId)
    signal cameraFullscreenRequested(string cameraName)
    signal requestRemoveCamera(string cameraId)
    signal navigate(string page)
    signal cameraDropped(real x, real y, string cameraName)

    readonly property var nx: NxStyle

    Settings {
        id: settings
        category: "cameraTree"
    }

    property var favoriteIds: []
    property var groups: ({})
    property var groupOrder: []
    property var expanded: ({})
    property string searchText: ""
    property var treeModel: []

    property bool dragging: false
    property string draggingCameraId: ""
    property string draggingCameraName: ""
    property real ghostX: 0
    property real ghostY: 0

    // ------------------------------------------------------------------
    // Persistence helpers (per server)
    // ------------------------------------------------------------------
    function storageKey(suffix) {
        return suffix + "_" + ((serverKey && serverKey.length) ? serverKey : "default")
    }

    function readArray(k) {
        var raw = settings.value(k, "")
        if (typeof raw !== "string" || raw.length === 0)
            return []
        try {
            var v = JSON.parse(raw)
            return (v instanceof Array) ? v : []
        } catch (e) {
            return []
        }
    }

    function readObject(k) {
        var raw = settings.value(k, "")
        if (typeof raw !== "string" || raw.length === 0)
            return ({})
        try {
            var v = JSON.parse(raw)
            return (v && typeof v === "object" && !(v instanceof Array)) ? v : ({})
        } catch (e) {
            return ({})
        }
    }

    function writeValue(k, value) {
        settings.setValue(k, JSON.stringify(value))
    }

    function loadState() {
        favoriteIds = readArray(storageKey("favorites"))

        var g = readObject(storageKey("groups"))
        var names = Object.keys(g)
        var order = readArray(storageKey("groupOrder"))
        var ordered = []
        var i
        for (i = 0; i < order.length; i++) {
            if (g.hasOwnProperty(order[i]) && ordered.indexOf(order[i]) < 0)
                ordered.push(order[i])
        }
        for (i = 0; i < names.length; i++) {
            if (ordered.indexOf(names[i]) < 0)
                ordered.push(names[i])
        }

        var e = readObject(storageKey("expanded"))
        var nextExpanded = ({ favorites: e.favorites !== false, all: e.all !== false })
        for (i = 0; i < ordered.length; i++)
            nextExpanded["group:" + ordered[i]] = e["group:" + ordered[i]] !== false

        groups = g
        groupOrder = ordered
        expanded = nextExpanded
        onlineState = ({})
        rebuild()
    }

    function saveFavorites() { writeValue(storageKey("favorites"), favoriteIds) }
    function saveGroups() { writeValue(storageKey("groups"), groups) }
    function saveGroupOrder() { writeValue(storageKey("groupOrder"), groupOrder) }
    function saveExpanded() { writeValue(storageKey("expanded"), expanded) }

    // ------------------------------------------------------------------
    // Camera helpers
    // ------------------------------------------------------------------
    function norm(value) {
        return ("" + (value === undefined || value === null ? "" : value)).trim().toLowerCase()
    }

    function camId(cam) {
        if (cam === undefined || cam === null)
            return ""
        if (typeof cam === "string")
            return cam
        return "" + (cam.id || cam.name || "")
    }

    function camName(cam) {
        if (cam === undefined || cam === null)
            return ""
        if (typeof cam === "string")
            return cam
        return "" + (cam.name || cam.id || "")
    }

    function sameCam(a, b) {
        var na = norm(a)
        var nb = norm(b)
        return na.length > 0 && na === nb
    }

    function allCameras() {
        var out = []
        var list = cameraList || []
        for (var i = 0; i < list.length; i++) {
            var c = list[i]
            var id = camId(c)
            if (id.length === 0)
                continue
            out.push({ id: id, name: camName(c) })
        }
        return out
    }

    function findCamera(id, list) {
        var src = list || allCameras()
        for (var i = 0; i < src.length; i++) {
            if (sameCam(src[i].id, id))
                return src[i]
        }
        return null
    }

    function isFavorite(id) {
        for (var i = 0; i < favoriteIds.length; i++) {
            if (sameCam(favoriteIds[i], id))
                return true
        }
        return false
    }

    function toggleFavorite(id) {
        if (!id)
            return
        var next = []
        var found = false
        for (var i = 0; i < favoriteIds.length; i++) {
            if (sameCam(favoriteIds[i], id)) {
                found = true
                continue
            }
            next.push(favoriteIds[i])
        }
        if (!found)
            next.push(id)
        favoriteIds = next
        saveFavorites()
        rebuild()
    }

    function groupExists(name) {
        return groups.hasOwnProperty(name)
    }

    function addGroup(name) {
        var n = ("" + (name || "")).trim()
        if (n.length === 0 || groupExists(n))
            return false
        var next = ({})
        var keys = Object.keys(groups)
        for (var i = 0; i < keys.length; i++)
            next[keys[i]] = groups[keys[i]]
        next[n] = []
        groups = next
        groupOrder = groupOrder.concat([n])
        var ex = expanded
        ex["group:" + n] = true
        expanded = ex
        saveGroups()
        saveGroupOrder()
        saveExpanded()
        rebuild()
        return true
    }

    function renameGroup(oldName, newName) {
        var n = ("" + (newName || "")).trim()
        if (!groupExists(oldName) || n.length === 0 || (n !== oldName && groupExists(n)))
            return false
        if (n === oldName)
            return true
        var next = ({})
        var keys = Object.keys(groups)
        for (var i = 0; i < keys.length; i++)
            next[keys[i] === oldName ? n : keys[i]] = groups[keys[i]]
        groups = next
        var order = []
        for (var j = 0; j < groupOrder.length; j++)
            order.push(groupOrder[j] === oldName ? n : groupOrder[j])
        groupOrder = order
        var ex = {}
        var exKeys = Object.keys(expanded)
        for (var k = 0; k < exKeys.length; k++) {
            var key = exKeys[k]
            ex[key === ("group:" + oldName) ? ("group:" + n) : key] = expanded[key]
        }
        expanded = ex
        saveGroups()
        saveGroupOrder()
        saveExpanded()
        rebuild()
        return true
    }

    function deleteGroup(name) {
        if (!groupExists(name))
            return
        var next = ({})
        var keys = Object.keys(groups)
        for (var i = 0; i < keys.length; i++) {
            if (keys[i] !== name)
                next[keys[i]] = groups[keys[i]]
        }
        groups = next
        var order = []
        for (var j = 0; j < groupOrder.length; j++) {
            if (groupOrder[j] !== name)
                order.push(groupOrder[j])
        }
        groupOrder = order
        var ex = expanded
        ex["group:" + name] = false
        expanded = ex
        saveGroups()
        saveGroupOrder()
        rebuild()
    }

    function groupsForCamera(id) {
        var out = []
        for (var i = 0; i < groupOrder.length; i++) {
            var ids = groups[groupOrder[i]] || []
            for (var j = 0; j < ids.length; j++) {
                if (sameCam(ids[j], id)) {
                    out.push(groupOrder[i])
                    break
                }
            }
        }
        return out
    }

    function assignToGroup(id, groupName) {
        if (!id || !groupExists(groupName))
            return
        var ids = (groups[groupName] || []).slice()
        for (var i = 0; i < ids.length; i++) {
            if (sameCam(ids[i], id))
                return
        }
        ids.push(id)
        var next = ({})
        var keys = Object.keys(groups)
        for (var j = 0; j < keys.length; j++)
            next[keys[j]] = groups[keys[j]]
        next[groupName] = ids
        groups = next
        saveGroups()
        rebuild()
    }

    function removeFromGroup(id, groupName) {
        if (!groupExists(groupName))
            return
        var ids = groups[groupName] || []
        var next = []
        for (var i = 0; i < ids.length; i++) {
            if (!sameCam(ids[i], id))
                next.push(ids[i])
        }
        var g = ({})
        var keys = Object.keys(groups)
        for (var j = 0; j < keys.length; j++)
            g[keys[j]] = groups[keys[j]]
        g[groupName] = next
        groups = g
        saveGroups()
        rebuild()
    }

    function toggleSection(keyName) {
        var ex = expanded
        ex[keyName] = !(ex[keyName] !== false)
        expanded = ex
        saveExpanded()
        rebuild()
    }

    // ------------------------------------------------------------------
    // Tree model
    // ------------------------------------------------------------------
    function headerRow(keyName, title, count) {
        return {
            kind: "header",
            key: keyName,
            title: title,
            count: count || 0,
            expanded: expanded[keyName] !== false,
            fixed: keyName === "search"
        }
    }

    function cameraRow(cam, sectionKey, groupName) {
        return {
            kind: "camera",
            id: cam.id,
            name: cam.name,
            favorite: isFavorite(cam.id),
            sectionKey: sectionKey,
            groupName: groupName || ""
        }
    }

    function rebuild() {
        var rows = []
        var cams = allCameras()
        var q = norm(searchText)

        if (q.length > 0) {
            var matches = []
            for (var m = 0; m < cams.length; m++) {
                if (norm(cams[m].name).indexOf(q) >= 0 || norm(cams[m].id).indexOf(q) >= 0)
                    matches.push(cams[m])
            }
            rows.push(headerRow("search", "Search results", matches.length))
            for (var s = 0; s < matches.length; s++)
                rows.push(cameraRow(matches[s], "search", ""))
            if (matches.length === 0)
                rows.push({ kind: "empty", text: "No matching cameras" })
            treeModel = rows
            return
        }

        // Favorites first — always visible when populated (NX style).
        if (favoriteIds.length > 0) {
            var favs = []
            for (var f = 0; f < favoriteIds.length; f++) {
                var fc = findCamera(favoriteIds[f], cams)
                if (fc)
                    favs.push(fc)
            }
            rows.push(headerRow("favorites", "Favorites", favs.length))
            if (expanded.favorites !== false) {
                for (var fi = 0; fi < favs.length; fi++)
                    rows.push(cameraRow(favs[fi], "favorites", ""))
            }
        }

        for (var gi = 0; gi < groupOrder.length; gi++) {
            var gname = groupOrder[gi]
            var ids = groups[gname] || []
            var gcams = []
            for (var gci = 0; gci < ids.length; gci++) {
                var gc = findCamera(ids[gci], cams)
                if (gc)
                    gcams.push(gc)
            }
            var gkey = "group:" + gname
            rows.push(headerRow(gkey, gname, gcams.length))
            if (expanded[gkey] !== false) {
                for (var gj = 0; gj < gcams.length; gj++)
                    rows.push(cameraRow(gcams[gj], gkey, gname))
            }
        }

        rows.push(headerRow("all", "All Cameras", cams.length))
        if (expanded.all !== false) {
            for (var i = 0; i < cams.length; i++)
                rows.push(cameraRow(cams[i], "all", ""))
        }
        if (cams.length === 0)
            rows.push({ kind: "empty", text: "No cameras" })

        treeModel = rows
    }

    function selectCamera(id) {
        if (!id)
            return
        tree.cameraSelected(id)
    }

    function stepCamera(direction) {
        var list = allCameras()
        if (list.length === 0)
            return
        var idx = -1
        for (var i = 0; i < list.length; i++) {
            if (sameCam(list[i].id, selectedCameraId)) {
                idx = i
                break
            }
        }
        idx = (idx + direction + list.length) % list.length
        selectCamera(list[idx].id)
    }

    Component.onCompleted: loadState()
    onServerKeyChanged: loadState()
    onCameraListChanged: rebuild()
    onSelectedCameraIdChanged: { /* highlight is bound directly in the delegate */ }

    // ------------------------------------------------------------------
    // UI
    // ------------------------------------------------------------------
    Rectangle {
        anchors.fill: parent
        color: "transparent"
    }

    ColumnLayout {
        anchors.fill: parent
        spacing: 6

        // Search field
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            radius: 4
            color: nx.surface
            border.color: nx.border
            border.width: 1

            Image {
                id: searchIcon
                anchors.left: parent.left
                anchors.leftMargin: 8
                anchors.verticalCenter: parent.verticalCenter
                width: 14
                height: 14
                source: "qrc:/app/assets/icons/nx/search.svg"
                fillMode: Image.PreserveAspectFit
                opacity: 0.7
            }

            TextField {
                id: searchField
                anchors.left: searchIcon.right
                anchors.leftMargin: 6
                anchors.right: clearSearch.left
                anchors.rightMargin: 4
                anchors.verticalCenter: parent.verticalCenter
                height: parent.height - 4
                placeholderText: "Search cameras..."
                placeholderTextColor: nx.textMuted
                color: nx.text
                font.pixelSize: 12
                background: Rectangle { color: "transparent" }
                onTextChanged: searchText = text
            }

            Text {
                id: clearSearch
                anchors.right: parent.right
                anchors.rightMargin: 9
                anchors.verticalCenter: parent.verticalCenter
                text: searchText.length > 0 ? "×" : ""
                color: nx.textMuted
                font.pixelSize: 18
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        searchField.text = ""
                        searchText = ""
                        searchField.forceActiveFocus()
                    }
                }
            }
        }

        // Tree header with "new group" action
        Item {
            Layout.fillWidth: true
            Layout.preferredHeight: 16
            Text {
                anchors.left: parent.left
                anchors.verticalCenter: parent.verticalCenter
                text: "Cameras"
                color: nx.textMuted
                font.pixelSize: 11
                font.bold: true
            }
            Text {
                anchors.right: parent.right
                anchors.verticalCenter: parent.verticalCenter
                text: "+ group"
                color: newGroupArea.containsMouse ? nx.accentHover : nx.textMuted
                font.pixelSize: 11
                MouseArea {
                    id: newGroupArea
                    anchors.fill: parent
                    anchors.margins: -4
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: {
                        groupPopup.targetGroup = ""
                        groupPopup.open()
                    }
                }
            }
        }

        ListView {
            id: listView
            Layout.fillWidth: true
            Layout.fillHeight: true
            clip: true
            model: treeModel
            cacheBuffer: 600

            ScrollBar.vertical: ScrollBar {
                policy: ScrollBar.AsNeeded
                contentItem: Rectangle {
                    implicitWidth: 4
                    radius: 2
                    color: "#555555"
                }
            }

            delegate: Item {
                id: row
                width: listView.width
                property var dataRow: modelData
                property string camKey: norm(modelData.id)
                property bool isOnline: tree.onlineState[camKey] !== false
                property bool isHeader: modelData.kind === "header"
                property bool isEmpty: modelData.kind === "empty"
                height: isHeader ? 28 : (isEmpty ? 30 : 34)

                // ---- Section header ----
                Rectangle {
                    visible: row.isHeader
                    anchors.fill: parent
                    color: headerArea.containsMouse ? nx.surfaceHover : "transparent"

                    Image {
                        id: chevron
                        anchors.left: parent.left
                        anchors.leftMargin: 6
                        anchors.verticalCenter: parent.verticalCenter
                        width: 12
                        height: 12
                        source: modelData.expanded
                                ? "qrc:/app/assets/icons/nx/arrow-down.svg"
                                : "qrc:/app/assets/icons/nx/arrow-right.svg"
                        fillMode: Image.PreserveAspectFit
                        opacity: 0.75
                        visible: !modelData.fixed
                    }

                    Text {
                        anchors.left: chevron.right
                        anchors.leftMargin: modelData.fixed ? 10 : 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.title || ""
                        color: nx.text
                        font.pixelSize: 12
                        font.bold: modelData.key === "favorites"
                        elide: Text.ElideRight
                        width: parent.width - countText.width - 44
                    }

                    Text {
                        id: countText
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: (modelData.count !== undefined && modelData.count !== null) ? modelData.count : ""
                        color: nx.textMuted
                        font.pixelSize: 11
                    }

                    MouseArea {
                        id: headerArea
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: function(mouse) {
                            if (mouse.button === Qt.LeftButton && !modelData.fixed)
                                toggleSection(modelData.key)
                        }
                        onPressed: function(mouse) {
                            if (mouse.button === Qt.RightButton && modelData.key.indexOf("group:") === 0)
                                groupHeaderMenu.groupName = modelData.key.slice(6)
                        }
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        onReleased: function(mouse) {
                            if (mouse.button === Qt.RightButton && modelData.key.indexOf("group:") === 0)
                                groupHeaderMenu.open()
                        }
                    }
                }

                // ---- Camera row ----
                Rectangle {
                    visible: !row.isHeader && !row.isEmpty
                    anchors.fill: parent
                    radius: 4
                    color: (modelData.id === tree.selectedCameraId)
                           ? nx.selected
                           : (rowHover.hovered || starArea.containsMouse)
                             ? nx.surfaceHover
                             : "transparent"
                    opacity: (tree.dragging && tree.draggingCameraId === modelData.id) ? 0.5 : 1.0

                    Item {
                        width: 18
                        height: 22
                        anchors.left: parent.left
                        anchors.leftMargin: 18
                        anchors.verticalCenter: parent.verticalCenter
                        Image {
                            anchors.centerIn: parent
                            width: 16
                            height: 16
                            source: "qrc:/app/assets/icons/nx/cameras.svg"
                            fillMode: Image.PreserveAspectFit
                            opacity: row.isOnline ? 1.0 : 0.5
                        }
                        Rectangle {
                            width: 6
                            height: 6
                            radius: 3
                            anchors.right: parent.right
                            anchors.bottom: parent.bottom
                            color: row.isOnline ? nx.online : nx.offline
                            border.color: nx.background
                            border.width: 1
                        }
                    }

                    Text {
                        anchors.left: parent.left
                        anchors.leftMargin: 44
                        anchors.right: star.left
                        anchors.rightMargin: 4
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.name || ""
                        color: nx.text
                        font.pixelSize: 13
                        elide: Text.ElideRight
                    }

                    Text {
                        id: star
                        anchors.right: parent.right
                        anchors.rightMargin: 10
                        anchors.verticalCenter: parent.verticalCenter
                        text: modelData.favorite ? "★" : "☆"
                        color: modelData.favorite ? "#F5B82E" : nx.textMuted
                        font.pixelSize: 16
                        MouseArea {
                            id: starArea
                            anchors.fill: parent
                            anchors.margins: -6
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: function(mouse) {
                                mouse.accepted = true
                                toggleFavorite(modelData.id)
                            }
                        }
                    }

                    HoverHandler {
                        id: rowHover
                    }

                    TapHandler {
                        acceptedButtons: Qt.LeftButton
                        onTapped: selectCamera(modelData.id)
                        onDoubleTapped: tree.cameraFullscreenRequested(modelData.id)
                    }

                    MouseArea {
                        anchors.fill: parent
                        acceptedButtons: Qt.RightButton
                        z: 10
                        onClicked: {
                            cameraMenu.cameraId = modelData.id
                            cameraMenu.open()
                        }
                    }

                    DragHandler {
                        id: rowDrag
                        target: null
                        acceptedButtons: Qt.LeftButton
                        grabPermissions: PointerHandler.CanTakeOverFromAnything
                                         | PointerHandler.ApprovesTakeOverByAnything

                        function syncGhost() {
                            if (!rowDrag.centroid)
                                return
                            var scene = rowDrag.centroid.scenePosition
                            if (!scene)
                                return
                            var loc = tree.mapFromItem(null, scene.x, scene.y)
                            tree.ghostX = loc.x + 10
                            tree.ghostY = loc.y + 10
                        }

                        onActiveChanged: {
                            if (active) {
                                tree.dragging = true
                                tree.draggingCameraId = modelData.id
                                tree.draggingCameraName = modelData.name
                                syncGhost()
                            } else if (tree.draggingCameraId === modelData.id) {
                                var scene = rowDrag.centroid ? rowDrag.centroid.scenePosition : null
                                if (scene) {
                                    var loc = tree.mapFromItem(null, scene.x, scene.y)
                                    var g = tree.mapToGlobal(loc.x, loc.y)
                                    tree.cameraDropped(g.x, g.y, tree.draggingCameraName)
                                }
                                tree.dragging = false
                                tree.draggingCameraId = ""
                                tree.draggingCameraName = ""
                            }
                        }

                        onTranslationChanged: {
                            if (active)
                                syncGhost()
                        }
                    }
                }

                // ---- Empty state ----
                Text {
                    visible: row.isEmpty
                    anchors.centerIn: parent
                    text: modelData.text || ""
                    color: nx.textMuted
                    font.pixelSize: 12
                }
            }
        }
    }

    // ------------------------------------------------------------------
    // Camera status (live signal driven)
    // A configured camera is shown as online until a stream reports a
    // failure; only then is it marked offline.
    // ------------------------------------------------------------------
    property var onlineState: ({})

    Connections {
        target: frigateRef
        ignoreUnknownSignals: true
        enabled: frigateRef !== null && frigateRef !== undefined
        function onCamerasLoaded() { rebuild() }
        function onCameraOnline(name) {
            var ex = tree.onlineState
            ex[norm(name)] = true
            tree.onlineState = ex
        }
        function onCameraOffline(name) {
            var ex = tree.onlineState
            ex[norm(name)] = false
            tree.onlineState = ex
        }
    }

    // ------------------------------------------------------------------
    // Menus
    // ------------------------------------------------------------------
    Menu {
        id: cameraMenu
        property string cameraId: ""
        title: cameraId

        MenuItem {
            text: "Open fullscreen"
            onTriggered: tree.cameraFullscreenRequested(cameraMenu.cameraId)
        }
        MenuItem {
            text: isFavorite(cameraMenu.cameraId) ? "Remove from Favorites" : "Add to Favorites"
            onTriggered: toggleFavorite(cameraMenu.cameraId)
        }

        Menu {
            id: assignMenu
            title: "Add to group"
            onAboutToShow: {
                clearDynamic(assignMenu)
                var names = groupOrder
                for (var i = 0; i < names.length; i++) {
                    assignMenu.addItem(assignItem.createObject(null, {
                        cameraId: cameraMenu.cameraId,
                        groupName: names[i]
                    }))
                }
                assignMenu.addItem(newGroupItem.createObject(null, {
                    cameraId: cameraMenu.cameraId
                }))
            }
        }

        Menu {
            id: unassignMenu
            title: "Remove from group"
            onAboutToShow: {
                clearDynamic(unassignMenu)
                var names = groupsForCamera(cameraMenu.cameraId)
                for (var i = 0; i < names.length; i++) {
                    unassignMenu.addItem(unassignItem.createObject(null, {
                        cameraId: cameraMenu.cameraId,
                        groupName: names[i]
                    }))
                }
            }
        }

        MenuSeparator {}
        MenuItem {
            text: "Edit Camera"
            onTriggered: tree.navigate("editCamera:" + cameraMenu.cameraId)
        }
        MenuItem {
            text: "Remove Camera"
            onTriggered: tree.requestRemoveCamera(cameraMenu.cameraId)
        }
    }

    function clearDynamic(menu) {
        while (menu.count > 0) {
            var item = menu.takeItem(0)
            if (item)
                item.destroy()
        }
    }

    Component {
        id: assignItem
        MenuItem {
            property string cameraId: ""
            property string groupName: ""
            text: groupName
            onTriggered: assignToGroup(cameraId, groupName)
        }
    }

    Component {
        id: unassignItem
        MenuItem {
            property string cameraId: ""
            property string groupName: ""
            text: groupName
            onTriggered: removeFromGroup(cameraId, groupName)
        }
    }

    Component {
        id: newGroupItem
        MenuItem {
            property string cameraId: ""
            text: "New group..."
            onTriggered: {
                groupPopup.targetGroup = ""
                groupPopup.pendingCameraId = cameraId
                groupPopup.open()
            }
        }
    }

    Menu {
        id: groupHeaderMenu
        property string groupName: ""
        MenuItem {
            text: "Rename group"
            onTriggered: {
                groupPopup.targetGroup = groupHeaderMenu.groupName
                groupPopup.pendingCameraId = ""
                groupPopup.open()
            }
        }
        MenuItem {
            text: "Delete group"
            onTriggered: deleteGroup(groupHeaderMenu.groupName)
        }
    }

    Popup {
        id: groupPopup
        modal: true
        focus: true
        anchors.centerIn: parent
        width: Math.min(280, tree.width - 16)
        height: 112
        padding: 12

        property string targetGroup: ""
        property string pendingCameraId: ""

        background: Rectangle {
            color: nx.surfaceAlt
            border.color: nx.border
            radius: 6
        }

        ColumnLayout {
            anchors.fill: parent
            spacing: 8
            Text {
                text: groupPopup.targetGroup.length ? "Rename group" : "New group"
                color: nx.text
                font.pixelSize: 13
                font.bold: true
            }
            TextField {
                id: groupNameField
                Layout.fillWidth: true
                placeholderText: "Group name"
                color: nx.text
                selectedTextColor: nx.text
                selectionColor: NxStyle.accent
                background: Rectangle {
                    color: "#1A1A1A"
                    border.color: nx.border
                    radius: 3
                }
                onAccepted: groupPopup.acceptGroup()
            }
            RowLayout {
                Layout.fillWidth: true
                spacing: 8
                Item { Layout.fillWidth: true }
                Button {
                    text: "Cancel"
                    onClicked: groupPopup.close()
                }
                Button {
                    text: "Save"
                    onClicked: groupPopup.acceptGroup()
                }
            }
        }

        function acceptGroup() {
            var n = (groupNameField.text || "").trim()
            if (n.length === 0)
                return
            var ok = true
            if (targetGroup.length)
                ok = renameGroup(targetGroup, n)
            else
                ok = addGroup(n)
            if (ok && pendingCameraId.length)
                assignToGroup(pendingCameraId, targetGroup.length ? targetGroup : n)
            groupNameField.text = ""
            pendingCameraId = ""
            targetGroup = ""
            groupPopup.close()
        }

        onOpened: {
            groupNameField.text = targetGroup
            groupNameField.forceActiveFocus()
        }
    }

    // Drag ghost
    Rectangle {
        visible: tree.dragging
        width: Math.min(220, Math.max(130, ghostLabel.implicitWidth + 48))
        height: 34
        radius: 6
        z: 100000
        x: tree.ghostX
        y: tree.ghostY
        color: nx.ghostBg
        border.color: nx.ghostBorder
        border.width: 1

        Row {
            anchors.verticalCenter: parent.verticalCenter
            anchors.left: parent.left
            anchors.leftMargin: 10
            spacing: 8
            Image {
                width: 16
                height: 16
                anchors.verticalCenter: parent.verticalCenter
                source: "qrc:/app/assets/icons/nx/cameras.svg"
                fillMode: Image.PreserveAspectFit
            }
            Text {
                id: ghostLabel
                anchors.verticalCenter: parent.verticalCenter
                text: tree.draggingCameraName
                color: nx.text
                font.pixelSize: 13
                font.bold: true
            }
        }
    }
}
