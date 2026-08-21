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
# RESTART LOGIC  (SAFE – does not crash when Docker is missing)
# ---------------------------------------------------------

def restart_docker(container):
    try:
        print(f"[restart] Docker restart → {container}")
        result = subprocess.run(
            ["docker", "restart", container],
            capture_output=True,
            text=True
        )
        if result.returncode != 0:
            print(f"[restart] Docker warning: {result.stderr.strip() or result.stdout.strip()}")
            return False
        return True
    except FileNotFoundError:
        print("[restart] Docker not found – skipping restart (config was still updated)")
        return False
    except Exception as e:
        print("[restart] Docker ERROR:", e)
        return False

def restart_systemd(service):
    try:
        print(f"[restart] systemctl restart → {service}")
        result = subprocess.run(
            ["systemctl", "restart", service],
            capture_output=True,
            text=True
        )
        return result.returncode == 0
    except FileNotFoundError:
        print("[restart] systemctl not found – skipping")
        return False
    except Exception as e:
        print("[restart] systemd ERROR:", e)
        return False

def restart_frigate():
    print(f"[frigate] Restart requested (install type: {FRIGATE_INSTALL_TYPE})")

    if FRIGATE_INSTALL_TYPE == "docker":
        return restart_docker(FRIGATE_CONTAINER_NAME)

    if FRIGATE_INSTALL_TYPE == "baremetal":
        return restart_systemd(FRIGATE_SERVICE_NAME)

    print("[frigate] Unknown install type → trying Docker (will skip if not available)")
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

    # Restart is best-effort – config is already written even if restart fails
    restart_ok = restart_frigate() if fr_ok else False

    success = go2_ok and fr_ok   # we no longer require restart_ok to be True

    return {
        "event": "cameraAddResult",
        "status": "ok" if success else "error",
        "message": f"Camera {cam_id} added (main+sub)" + (" – restart skipped (no Docker)" if not restart_ok else ""),
        "go2rtc": go2_ok,
        "frigate_restart": restart_ok
    }