import QtQuick 2.15

Item {
    id: controller
    property var frigateRef

    signal cameraAdded()
    signal cameraEdited()
    signal cameraRemoved()

    function addCamera(id, url, record) {
        if (!frigateRef) return
        frigateRef.addCamera(id, url, record)
    }

    function editCamera(id, url) {
        if (!frigateRef) return
        frigateRef.editCamera(id, url)
    }

    function removeCamera(id) {
        if (!frigateRef) return
        frigateRef.removeCamera(id)
    }

    Connections {
        target: frigateRef || null

        function onCameraAddResult(ok, msg) {
            if (ok) controller.cameraAdded()
        }

        function onCameraEditResult(ok, msg) {
            if (ok) controller.cameraEdited()
        }

        function onCameraRemoveResult(ok, msg) {
            if (ok) controller.cameraRemoved()
        }
    }
}
