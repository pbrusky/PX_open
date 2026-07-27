import yaml
import os
import shutil
import time
import subprocess

from config import (
    FRIGATE_CONFIG_PATH,
    GO2RTC_CONFIG_PATH,
    FRIGATE_INSTALL_TYPE,
    FRIGATE_CONTAINER_NAME,
    FRIGATE_SERVICE_NAME,
    GO2RTC_CONTAINER_NAME
)

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
        print("[remove_camera] load_yaml ERROR:", e)
        return {}

def save_yaml(path, data):
    try:
        with open(path, "w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
        return True
    except Exception as e:
        print("[remove_camera] save_yaml ERROR:", e)
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
# GO2RTC STREAM REMOVE
# ---------------------------------------------------------

def remove_go2rtc_stream(cam_id):
    backup_file(GO2RTC_CONFIG_PATH)
    cfg = load_yaml(GO2RTC_CONFIG_PATH)

    if "streams" in cfg and cam_id in cfg["streams"]:
        del cfg["streams"][cam_id]
        print(f"[go2rtc] Removed stream for {cam_id}")

    if save_yaml(GO2RTC_CONFIG_PATH, cfg):
        restart_go2rtc()
        return True
    return False

# ---------------------------------------------------------
# FRIGATE CONFIG REMOVE
# ---------------------------------------------------------

def remove_frigate_camera(cam_id):
    backup_file(FRIGATE_CONFIG_PATH)
    cfg = load_yaml(FRIGATE_CONFIG_PATH)

    if "cameras" in cfg and cam_id in cfg["cameras"]:
        del cfg["cameras"][cam_id]
        print(f"[frigate] Removed camera {cam_id}")

    return save_yaml(FRIGATE_CONFIG_PATH, cfg)

# ---------------------------------------------------------
# PUBLIC API: REMOVE CAMERA
# ---------------------------------------------------------

def remove_camera(cam_id):
    print(f"[remove_camera] Removing {cam_id}")

    if not cam_id:
        return {
            "event": "cameraRemoveResult",
            "status": "error",
            "message": "Invalid camera name"
        }

    go2_ok = remove_go2rtc_stream(cam_id)
    fr_ok = remove_frigate_camera(cam_id)
    restart_ok = restart_frigate() if fr_ok else False

    return {
        "event": "cameraRemoveResult",
        "status": "ok" if (go2_ok and fr_ok and restart_ok) else "error",
        "message": f"Camera {cam_id} removed",
        "go2rtc": go2_ok,
        "frigate_restart": restart_ok
    }
