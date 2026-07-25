import QtQuick 2.15

Item {
    id: dropHandler

    property var mainWindow
    property var contentLoader

    //
    // Drop a camera into the grid
    //
    function dropCamera(x, y, cameraName) {
        let sv = contentLoader.item
        if (!sv || sv.objectName !== "ServerView")
            return

        let grid = sv.cameraGrid
        if (!grid || !grid.dropAt) {
            sv.gridReady.connect(function() {
                let g = sv.cameraGrid
                if (!g || !g.dropAt) return

                let p2 = g.mapFromGlobal(x, y)
                g.dropAt(p2.x, p2.y, cameraName)
            })
            return
        }

        let p = grid.mapFromGlobal(x, y)
        grid.dropAt(p.x, p.y, cameraName)
    }

    //
    // Reorder tiles after drag release
    //
    function reorderTile(tileIndex, tileItem) {
        let sv = contentLoader.item
        if (!sv || sv.objectName !== "ServerView")
            return

        let grid = sv.cameraGrid
        if (grid && grid.reorderTilesByTileCenter)
            grid.reorderTilesByTileCenter(tileIndex, tileItem)
    }

    //
    // Enter fullscreen from a tile
    // (frameQueue is passed through so FullscreenCamera can render video)
    //
    function enterFullscreen(cameraName, frameQueue) {
        let sv = contentLoader.item
        if (!sv || sv.objectName !== "ServerView")
            return

        // ⭐ Clean fullscreen path (no logs here)
        if (mainWindow && mainWindow.fullscreenManager)
            mainWindow.fullscreenManager.open(cameraName, frameQueue)
    }

    //
    // Remove camera from tile
    //
    function removeCamera(cameraName) {
        let sv = contentLoader.item
        if (!sv || sv.objectName !== "ServerView")
            return

        if (sv.openRemoveCameraPopup)
            sv.openRemoveCameraPopup(cameraName)
    }
}
