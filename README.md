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

       cd C:\path\to\PX_open\server_module\Frigate
       pip install pyyaml psutil requests

4. Configure `config.json` (created on first run if missing). Important fields:

| Key | Purpose |
|-----|---------|
| `http_port` / `https_port` | Module API (default **8001** / **8002**) |
| `system_name` | Name shown in client discovery |
| `frigate_container_name` | Docker name for Frigate |
| `go2rtc_container_name` | Docker name for go2rtc |
| `frigate_config_path` | Path to Frigate `config.yml` |
| `go2rtc_config_path` | Path to go2rtc config |
| `frigate_media_path` / `frigate_cache_path` | Media/cache paths |

5. Start the module:

       python frigate_server.py

You should see discovery broadcast and HTTP listening, for example: `http://<LAN-IP>:8001`

Optional: if you ship a `frigate_server.exe`, place `config.json` beside it and run the exe instead of the `.py` file.

### 1.2 Linux

1. Install Python 3 and dependencies (Debian / Ubuntu / Linux Lite style):

       sudo apt update
       sudo apt install -y python3 python3-pip python3-venv python3-yaml python3-psutil python3-requests

If Frigate runs in Docker:

       sudo apt install -y docker.io

If `pip install` fails with externally-managed-environment, prefer the `python3-*` packages above, or use a venv:

       cd /path/to/PX_open/server_module/Frigate
       python3 -m venv .venv
       source .venv/bin/activate
       pip install pyyaml psutil requests

2. Start:

       python3 frigate_server.py

On first run, `config.json` may be created or adjusted for Linux paths. Verify Frigate and go2rtc config paths and container names (`docker ps`).

3. Allow firewall access if needed: TCP **8001** / **8002**, and UDP discovery (client listens on **3666**).

### 1.3 Verify the module

From another machine on the LAN open `http://<server-lan-ip>:8001/`. In the PX Open client the system should appear on discovery (name from `system_name`). If discovery fails, use manual IP entry.

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

       sudo dpkg -i px-open_*.deb
       sudo apt-get install -f -y

3. Start from the menu (PX Open) or:

       /opt/px-open/bin/px-open

4. Uninstall:

       sudo apt remove px-open

Most heavy libraries ship inside the .deb. Remaining depends are normal desktop libraries (OpenGL, xcb, fontconfig, nss, etc.). Use `apt-get install -f` to install them.

If the app does not start:

       /opt/px-open/bin/px-open
       LD_LIBRARY_PATH=/opt/px-open/lib ldd /opt/px-open/bin/px_open | grep "not found"

On weak GPUs (e.g. some Intel Atom systems):

       QT_QUICK_BACKEND=software /opt/px-open/bin/px-open

### Option B – Build from source (developers)

       cd client
       cmake -S . -B build -G Ninja -DCMAKE_BUILD_TYPE=Release \
         -DCMAKE_PREFIX_PATH="$HOME/Qt/6.5.3/gcc_64"
       cmake --build build -j$(nproc)
       ./build/px_open

Optional: produce a .deb with packaging/package_deb.sh using a Release binary.

WSL is useful for compiling; UDP discovery often fails under WSL NAT — use manual server IP or test on real Windows/Linux.

---

## 4. First-time use

1. Start Frigate (and go2rtc if separate).
2. Start the Server Module on the Frigate host.
3. Start the PX Open Client.
4. Select the discovered server (or enter IP + ports manually).
5. Use sidebar cameras, grid, fullscreen, and timeline as needed.

---

## 5. Default ports

| Service | Port | Notes |
|---------|------|--------|
| Frigate API | 5000 | Typical compose mapping |
| go2rtc RTSP | 8554 | Live streams for the client |
| Server module HTTP | 8001 | Configurable in config.json |
| Server module HTTPS | 8002 | Configurable |
| Client discovery | UDP 3666 | Client listens; module broadcasts |

---

## 6. Troubleshooting

| Issue | What to try |
|--------|-------------|
| No servers in discovery | Module running? Same LAN? Firewall? Try manual IP. WSL often blocks broadcast. |
| .deb dependency errors | sudo dpkg -i … then sudo apt-get install -f -y |
| Client missing .so libraries | Install matching release .deb; check with ldd as above |
| Black / empty window | QT_QUICK_BACKEND=software |
| About Version unknown | Ensure version.txt is next to the binary |
| Add/remove camera fails | Module must reach Docker and correct Frigate + go2rtc paths |

---

## Project layout

| Path | Contents |
|------|----------|
| client/ | Qt/QML desktop application |
| server_module/Frigate/ | Frigate integration module |
| packaging/ | Linux .deb packaging script (if present) |

---

## License

See the repository for license terms.