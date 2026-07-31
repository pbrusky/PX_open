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
        print("[add_camera] load_yaml ERROR:", e)
        return {}

def save_yaml(path, data):
    try:
        with open(path, "w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
        return True
    except Exception as e:
        print("[add_camera] save_yaml ERROR:", e)
        return False

def clean_rtsp(url):
    return (url or "").strip()

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
# GO2RTC — client streams (sub + main)
# ---------------------------------------------------------

def add_go2rtc_streams(cam_id, main_url, sub_url):
    backup_file(GO2RTC_CONFIG_PATH)
    cfg = load_yaml(GO2RTC_CONFIG_PATH)
    cfg.setdefault("streams", {})

    main_url = clean_rtsp(main_url)
    sub_url = clean_rtsp(sub_url) if sub_url else main_url

    # Grid / multi-view
    cfg["streams"][cam_id] = sub_url
    # Fullscreen / primary
    cfg["streams"][f"{cam_id}_main"] = main_url

    print(f"[go2rtc] Added streams: {cam_id} (sub), {cam_id}_main (main)")

    if save_yaml(GO2RTC_CONFIG_PATH, cfg):
        restart_go2rtc()
        return True
    return False

# ---------------------------------------------------------
# FRIGATE — direct camera RTSP (same style as working cams)
# ---------------------------------------------------------

def add_frigate_camera(cam_id, main_url, sub_url, record=True):
    backup_file(FRIGATE_CONFIG_PATH)
    cfg = load_yaml(FRIGATE_CONFIG_PATH)
    cfg.setdefault("cameras", {})

    main_url = clean_rtsp(main_url)
    sub_url = clean_rtsp(sub_url) if sub_url else main_url

    # detect = sub (lighter), record = main (full quality)
    inputs = [
        {
            "path": sub_url,
            "input_args": "preset-rtsp-generic",
            "roles": ["detect"]
        }
    ]

    if record:
        inputs.append({
            "path": main_url,
            "input_args": "preset-rtsp-generic",
            "roles": ["record"]
        })

    cfg["cameras"][cam_id] = {
        "enabled": True,
        "ffmpeg": {
            "inputs": inputs
        },
        "live": {
            "streams": {
                "Sub Stream": cam_id,
                "Main Stream": f"{cam_id}_main"
            }
        },
        "detect": {
            "width": 1280,
            "height": 720
        },
        "record": {
            "enabled": bool(record)
        }
    }

    print(f"[frigate] Added camera {cam_id} (detect=sub direct, record=main direct)")
    return save_yaml(FRIGATE_CONFIG_PATH, cfg)

# ---------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------

def add_camera(cam_id, rtsp_url, record=True, rtsp_sub=None):
    """
    rtsp_url  = MAIN stream (fullscreen / record)
    rtsp_sub  = SUB stream (grid / detect); if empty, uses main
    """
    print(f"[camera_manager] add_camera {cam_id}")

    main_url = clean_rtsp(rtsp_url)
    sub_url = clean_rtsp(rtsp_sub) if rtsp_sub else main_url

    if not cam_id or not main_url.startswith("rtsp://"):
        return {
            "event": "cameraAddResult",
            "status": "error",
            "message": "Invalid camera name or main RTSP URL"
        }

    if sub_url and not sub_url.startswith("rtsp://"):
        return {
            "event": "cameraAddResult",
            "status": "error",
            "message": "Invalid sub RTSP URL"
        }

    go2_ok = add_go2rtc_streams(cam_id, main_url, sub_url)
    fr_ok = add_frigate_camera(cam_id, main_url, sub_url, record)
    restart_ok = restart_frigate() if fr_ok else False

    return {
        "event": "cameraAddResult",
        "status": "ok" if (go2_ok and fr_ok and restart_ok) else "error",
        "message": f"Camera {cam_id} added (main+sub)",
        "go2rtc": go2_ok,
        "frigate_restart": restart_ok
    }