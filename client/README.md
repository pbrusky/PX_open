# PX Open Client

This is the main PX Open application.  
It connects to the PX Frigate Server Module and provides camera management, ONVIF discovery, RTSP testing, and Frigate integration.

## Camera tree

The sidebar camera list is now a tree:

- **Search** cameras by name or ID.
- **Favorites** — click the ☆ on a camera row to star it. Favorites are saved per server.
- **Groups** — use "+ group" above the tree, or right-click a camera and use *Add to group*. Right-click a group header to rename or delete it.
- Drag a row onto the grid to add it to the live view; double-click a row for fullscreen; right-click for camera actions.

## Keyboard shortcuts

Press **F1** in the app for the full list. The most useful ones:

| Key | Action |
|-----|--------|
| `1`–`9`, `0` | Select camera 1–9 (0 = 10th) and add it to the grid |
| `↑` / `↓` | Previous / next camera |
| `←` / `→` | Seek ±10 s in fullscreen playback, otherwise select camera |
| `F` / `F11` | Toggle fullscreen for the selected camera |
| `L` | Return to live |
| `Esc` | Leave fullscreen / close dialogs |
| `Tab` | Toggle camera tree |
| `Shift+Tab`, `E` | Toggle events panel |
| `Ctrl+Tab`, `T` | Toggle timeline |
| `G` / `H` | Grid / home |
| `Ctrl+S` | Save current grid as the Default layout |
