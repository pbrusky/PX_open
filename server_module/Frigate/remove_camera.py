import yaml
import os
import shutil
import time
import subprocess
from pathlib import Path

from config import (
    FRIGATE_CONFIG_PATH,
    GO2RTC_CONFIG_PATH,
    FRIGATE_INSTALL_TYPE,
    FRIGATE_CONTAINER_NAME,
    FRIGATE_SERVICE_NAME,
    GO2RTC_CONTAINER_NAME,
    FRIGATE_MEDIA_PATH,
    FRIGATE_CACHE_PATH
)

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

def remove_go2rtc_streams(cam_id):
    backup_file(GO2RTC_CONFIG_PATH)
    cfg = load_yaml(GO2RTC_CONFIG_PATH)

    removed = False
    if "streams" in cfg:
        if cam_id in cfg["streams"]:
            del cfg["streams"][cam_id]
            removed = True
            print(f"[go2rtc] Removed stream {cam_id}")

        main_key = f"{cam_id}_main"
        if main_key in cfg["streams"]:
            del cfg["streams"][main_key]
            removed = True
            print(f"[go2rtc] Removed stream {main_key}")

    if save_yaml(GO2RTC_CONFIG_PATH, cfg):
        if removed:
            restart_go2rtc()
        return True
    return False

def remove_frigate_camera(cam_id):
    backup_file(FRIGATE_CONFIG_PATH)
    cfg = load_yaml(FRIGATE_CONFIG_PATH)

    if "cameras" in cfg and cam_id in cfg["cameras"]:
        del cfg["cameras"][cam_id]
        print(f"[frigate] Removed camera {cam_id}")

    return save_yaml(FRIGATE_CONFIG_PATH, cfg)

def delete_dir_if_exists(path):
    try:
        if not path.exists():
            return True

        print(f"[frigate] Deleting folder: {path}")
        shutil.rmtree(path, ignore_errors=False)
        return not path.exists()
    except Exception as e:
        print(f"[frigate] Failed to delete folder {path}: {e}")
        return False


def delete_camera_files(cam_id):
    success = True
    media_targets = []
    cache_targets = []

    if FRIGATE_MEDIA_PATH.exists():
        for path in FRIGATE_MEDIA_PATH.rglob('*'):
            if path.is_dir() and path.name in {cam_id, f"{cam_id}_main"}:
                media_targets.append(path)

    for media_target in media_targets:
        if not delete_dir_if_exists(media_target):
            success = False

    direct_media_folder = FRIGATE_MEDIA_PATH / cam_id
    if not delete_dir_if_exists(direct_media_folder):
        success = False

    direct_cache_folder = FRIGATE_CACHE_PATH / cam_id
    if not delete_dir_if_exists(direct_cache_folder):
        success = False

    if FRIGATE_CACHE_PATH.exists():
        for path in FRIGATE_CACHE_PATH.rglob('*'):
            if path.is_dir() and path.name in {cam_id, f"{cam_id}_main"}:
                cache_targets.append(path)

    for cache_target in cache_targets:
        if not delete_dir_if_exists(cache_target):
            success = False

    return success

def remove_camera(cam_id):
    print(f"[remove_camera] Removing {cam_id}")

    if not cam_id:
        return {
            "event": "cameraRemoveResult",
            "status": "error",
            "ok": False,
            "message": "Invalid camera name"
        }

    # STOP FRIGATE FIRST
    print("[frigate] Stopping Frigate before deletion...")
    subprocess.run(["docker", "stop", FRIGATE_CONTAINER_NAME], capture_output=True, text=True)

    go2_ok = remove_go2rtc_streams(cam_id)
    fr_ok = remove_frigate_camera(cam_id)
    delete_ok = delete_camera_files(cam_id)

    restart_ok = restart_frigate()

    ok = go2_ok and fr_ok and delete_ok and restart_ok

    return {
        "event": "cameraRemoveResult",
        "status": "ok" if ok else "error",
        "ok": ok,
        "message": f"Camera {cam_id} removed"
    }
