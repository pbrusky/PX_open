# PX Open

Desktop client for Frigate NVR, plus a **Frigate Server Module** that runs on the machine hosting Frigate (discovery, add/remove cameras, config edit, ONVIF).

| Piece | Role |
|--------|------|
| **PX Open Client** | Windows / Linux app (live view, grid, fullscreen, timeline, config editor) |
| **Server Module** | Python service next to Frigate + go2rtc |

**Releases:** https://github.com/pbrusky/PX_open/releases

---

## Requirements

### Frigate host (where the Server Module runs)

- Frigate (Docker recommended)
- go2rtc (separate container or embedded, depending on your setup)
- Docker (if you use containers)
- Network access between the client PC and this host

### Client PC

- **Windows:** Windows 10/11 (64-bit)
- **Linux:** 64-bit (x86_64). The release `.deb` bundles Qt and most FFmpeg libraries; a few system packages are still required (see Client – Linux).

---

## 1. Server Module

The server module should run on the **same LAN host** that runs Frigate (or a host that can reach Frigate’s API, Docker, and config files).

### 1.1 Windows

1. Install **Python 3.10+** and ensure it is on `PATH`.
2. Install **Docker Desktop** if Frigate/go2rtc run in Docker.
3. Open a terminal in the server module folder:

```bat
cd C:\path\to\PX_open\server_module\Frigate
pip install pyyaml psutil requests

---

**Part 2 of 2** (append after Part 1)

```markdown
---

## 2. Client – Windows

### Option A – Release build (recommended)

1. Download the Windows build from https://github.com/pbrusky/PX_open/releases
2. Unzip if needed and run **px_open.exe**
3. Select your Frigate system from discovery, or add the server manually (IP + Frigate API port + module port)

A normal Release package includes required runtimes; you do not need to install Qt separately.

### Option B – Build from source

- Visual Studio (with C++), Qt 6.5+, CMake, FFmpeg (e.g. C:\ffmpeg)
- Build the client project (Release for daily use)
- Run e.g. build\client\Release\px_open.exe
- Optional: place version.txt next to the exe so About shows the version

---

## 3. Client – Linux

### Option A – .deb package (recommended)

The release .deb installs under /opt/px-open, adds a PX Open menu entry, and bundles Qt 6.5.x plus many FFmpeg/codec libraries. You do not need a full Qt SDK only to run the app.

1. Download px-open_*_amd64.deb from https://github.com/pbrusky/PX_open/releases
2. Install:

```bash
sudo dpkg -i px-open_*.deb
sudo apt-get install -f -y