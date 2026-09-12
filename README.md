# PX Open

Desktop client for Frigate NVR, plus a **Frigate Server Module** that runs on the machine hosting Frigate (discovery, add/remove cameras, config edit, ONVIF).

| Piece | Role |
|--------|------|
| **PX Open Client** | Windows / Linux app (live view, grid, fullscreen, timeline, config editor) |
| **Server Module** | Python service next to Frigate + go2rtc |

---

## Requirements

### Frigate host (where the Server Module runs)

- Frigate (Docker recommended)
- go2rtc (separate container or embedded, depending on your setup)
- Docker (if you use containers)
- Network access between the client PC and this host

### Client PC

- **Windows:** Windows 10/11 (64-bit)
- **Linux:** 64-bit (x86_64). The `.deb` bundles Qt and most FFmpeg libraries; a few system packages are still required (see below).

---

## 1. Server Module

The server module must run on the **same LAN host** that runs Frigate (or can reach Frigate’s API, Docker, and config files).

### 1.1 Windows

1. Install **Python 3.10+** and add it to `PATH`.
2. Install **Docker Desktop** if Frigate/go2rtc run in Docker.
3. Clone or copy the repo, then open a terminal in the server folder:

```bat
cd C:\path\to\PX_open\server_module\Frigate
pip install pyyaml psutil requests