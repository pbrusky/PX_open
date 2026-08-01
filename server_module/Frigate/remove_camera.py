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


def delete_file_if_exists(path):
    try:
        if not path.exists():
            return True

        print(f"[frigate] Deleting file: {path}")
        path.unlink(missing_ok=True)
        return not path.exists()
    except Exception as e:
        print(f"[frigate] Failed to delete file {path}: {e}")
        return False


def purge_cache_root():
    try:
        if not FRIGATE_CACHE_PATH.exists():
            return True

        print(f"[frigate] Purging cache root: {FRIGATE_CACHE_PATH}")
        success = True

        for child in sorted(FRIGATE_CACHE_PATH.iterdir(), key=lambda p: (len(p.parts), str(p)), reverse=True):
            if child.is_dir():
                if not delete_dir_if_exists(child):
                    success = False
            elif child.is_file():
                if not delete_file_if_exists(child):
                    success = False

        return success
    except Exception as e:
        print(f"[frigate] Failed to purge cache root {FRIGATE_CACHE_PATH}: {e}")
        return False


def _matches_camera_name(path, cam_id):
    target = cam_id.casefold()
    target_main = f"{cam_id}_main".casefold()

    if path.name.casefold() == target or path.name.casefold() == target_main:
        return True

    if path.stem.casefold() == target or path.stem.casefold() == target_main:
        return True

    parts = [part.casefold() for part in path.parts]
    return target in parts or target_main in parts


def delete_camera_files(cam_id):
    success = True
    delete_roots = []

    for root in (FRIGATE_MEDIA_PATH, FRIGATE_CACHE_PATH):
        if root and root.exists() and root not in delete_roots:
            delete_roots.append(root)

    parent_media = getattr(FRIGATE_MEDIA_PATH, "parent", None)
    if parent_media and parent_media.exists() and parent_media not in delete_roots:
        delete_roots.append(parent_media)

    parent_cache = getattr(FRIGATE_CACHE_PATH, "parent", None)
    if parent_cache and parent_cache.exists() and parent_cache not in delete_roots:
        delete_roots.append(parent_cache)

    for root in delete_roots:
        print(f"[frigate] Scanning delete root: {root}")
        candidates = sorted(root.rglob('*'), key=lambda p: (len(p.parts), str(p)), reverse=True)
        for path in candidates:
            if _matches_camera_name(path, cam_id):
                if path.is_dir():
                    if not delete_dir_if_exists(path):
                        success = False
                elif path.is_file():
                    if not delete_file_if_exists(path):
                        success = False

    direct_media_folder = FRIGATE_MEDIA_PATH / cam_id
    if not delete_dir_if_exists(direct_media_folder):
        success = False

    direct_cache_folder = FRIGATE_CACHE_PATH / cam_id
    if not delete_dir_if_exists(direct_cache_folder):
        success = False

    if not purge_cache_root():
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
