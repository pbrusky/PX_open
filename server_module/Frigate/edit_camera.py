import yaml
import os
import shutil
import time

from config import (
    FRIGATE_CONFIG_PATH,
    GO2RTC_CONFIG_PATH,
    FRIGATE_INSTALL_TYPE,
    FRIGATE_CONTAINER_NAME,
    FRIGATE_SERVICE_NAME,
    GO2RTC_CONTAINER_NAME
)

import subprocess

# ---------------------------------------------------------
# UTILITIES
# ---------------------------------------------------------

def backup_file(path):
    if not os.path.exists(path):
        return
    try:
        backup_path = f"{path}.bak_{int(time.time())}"
        shutil.copy2(path, backup_path)
        print(f"[backup] Created {backup_path}")
    except Exception as e:
        print("[backup] ERROR:", e)

def load_yaml(path):
    try:
        with open(path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        print("[edit_camera] load_yaml ERROR:", e)
        return {}

def save_yaml(path, data):
    try:
        with open(path, "w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
        return True
    except Exception as e:
        print("[edit_camera] save_yaml ERROR:", e)
        return False

# ---------------------------------------------------------
# RESTART LOGIC
# ---------------------------------------------------------

def restart_docker(container):
    try:
        print(f"[restart] Docker restart → {container}")
        subprocess.run(["docker", "restart", container], capture_output=True, text=True)
        return True
    except Exception as e:
        print("[restart] Docker ERROR:", e)
        return False

def restart_systemd(service):
    try:
        print(f"[restart] systemctl restart → {service}")
        subprocess.run(["systemctl", "restart", service], capture_output=True, text=True)
        return True
    except Exception as e:
        print("[restart] systemd ERROR:", e)
        return False

def restart_frigate():
    print(f"[frigate] Restart requested (install type: {FRIGATE_INSTALL_TYPE})")

    if FRIGATE_INSTALL_TYPE == "docker":
        return restart_docker(FRIGATE_CONTAINER_NAME)

    if FRIGATE_INSTALL_TYPE == "baremetal":
        return restart_systemd(FRIGATE_SERVICE_NAME)

    print("[frigate] Unknown install type → using Docker fallback")
    return restart_docker(FRIGATE_CONTAINER_NAME)

def restart_go2rtc():
    print("[go2rtc] Restart requested")
    return restart_docker(GO2RTC_CONTAINER_NAME)

# ---------------------------------------------------------
# GO2RTC STREAM UPDATE
# ---------------------------------------------------------

def update_go2rtc_stream(cam_id, rtsp_url):
    backup_file(GO2RTC_CONFIG_PATH)
    cfg = load_yaml(GO2RTC_CONFIG_PATH)

    cfg.setdefault("streams", {})
    clean_url = rtsp_url.split("?")[0]

    cfg["streams"][cam_id] = f"ffmpeg:{clean_url}#tcp"
    print(f"[go2rtc] Updated stream for {cam_id}")

    if save_yaml(GO2RTC_CONFIG_PATH, cfg):
        restart_go2rtc()
        return True
    return False

# ---------------------------------------------------------
# FRIGATE CONFIG UPDATE
# ---------------------------------------------------------

def update_frigate_camera(cam_id, rtsp_url):
    backup_file(FRIGATE_CONFIG_PATH)
    cfg = load_yaml(FRIGATE_CONFIG_PATH)

    cfg.setdefault("cameras", {})

    cfg["cameras"][cam_id] = {
        "enabled": True,
        "ffmpeg": {
            "inputs": [
                {
                    "path": rtsp_url,
                    "input_args": "preset-rtsp-generic",
                    "roles": ["detect", "record"]
                }
            ]
        },
        "live": {"streams": {"Main Stream": cam_id}},
        "detect": {"width": 1280, "height": 720},
        "record": {"enabled": True}
    }

    print(f"[frigate] Updated camera {cam_id}")

    return save_yaml(FRIGATE_CONFIG_PATH, cfg)

# ---------------------------------------------------------
# PUBLIC API: EDIT CAMERA
# ---------------------------------------------------------

def edit_camera(cam_id, rtsp_url):
    print(f"[edit_camera] Editing {cam_id}")

    if not cam_id or not rtsp_url.startswith("rtsp://"):
        return {
            "event": "cameraEditResult",
            "status": "error",
            "message": "Invalid camera name or RTSP URL"
        }

    go2_ok = update_go2rtc_stream(cam_id, rtsp_url)
    fr_ok = update_frigate_camera(cam_id, rtsp_url)
    restart_ok = restart_frigate() if fr_ok else False

    return {
        "event": "cameraEditResult",
        "status": "ok" if (go2_ok and fr_ok and restart_ok) else "error",
        "message": f"Camera {cam_id} updated",
        "go2rtc": go2_ok,
        "frigate_restart": restart_ok
    }
