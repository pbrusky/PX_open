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

# Optional: set in config.py e.g. "http://127.0.0.1:5000"
try:
    from config import FRIGATE_API_BASE
except Exception:
    FRIGATE_API_BASE = os.environ.get("FRIGATE_API_BASE", "http://127.0.0.1:5000")

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
    """Load YAML. Returns (data, ok). ok=False means do NOT overwrite the file."""
    try:
        if not os.path.exists(path):
            print(f"[remove_camera] load_yaml: missing {path}")
            return {}, False
        with open(path, "r", encoding="utf-8") as f:
            raw = f.read()
        if not raw.strip():
            print(f"[remove_camera] load_yaml: empty file {path}")
            return {}, False
        data = yaml.safe_load(raw)
        if data is None:
            data = {}
        if not isinstance(data, dict):
            print(f"[remove_camera] load_yaml: root is not a mapping in {path}")
            return {}, False
        return data, True
    except Exception as e:
        print("[remove_camera] load_yaml ERROR:", e)
        return {}, False


def save_yaml(path, data):
    try:
        with open(path, "w", encoding="utf-8") as f:
            yaml.safe_dump(
                data,
                f,
                default_flow_style=False,
                sort_keys=False,
                allow_unicode=True,
            )
        return True
    except Exception as e:
        print("[remove_camera] save_yaml ERROR:", e)
        return False


def stream_keys_for_camera(cam_id):
    cam_id = (cam_id or "").strip()
    if not cam_id:
        return set()
    return {
        cam_id,
        f"{cam_id}_main",
        f"{cam_id}_sub",
    }


def delete_matching_stream_keys(streams, cam_id):
    if not isinstance(streams, dict):
        return {}, []
    wanted = {k.casefold() for k in stream_keys_for_camera(cam_id)}
    removed = []
    for key in list(streams.keys()):
        if str(key).casefold() in wanted:
            del streams[key]
            removed.append(str(key))
    return streams, removed


# ---------------------------------------------------------
# SAFE DOCKER / RESTART HELPERS
# ---------------------------------------------------------

def safe_docker(cmd, *args, timeout=120):
    try:
        print(f"[docker] {cmd} {' '.join(args)}")
        result = subprocess.run(
            ["docker", cmd, *args],
            capture_output=True,
            text=True,
            timeout=timeout,
        )
        if result.returncode != 0:
            print(f"[docker] warning: {result.stderr.strip() or result.stdout.strip()}")
            return False
        return True
    except FileNotFoundError:
        print(f"[docker] not found – skipping '{cmd}'")
        return False
    except subprocess.TimeoutExpired:
        print(f"[docker] TIMEOUT on '{cmd}' after {timeout}s")
        return False
    except Exception as e:
        print(f"[docker] ERROR: {e}")
        return False


def restart_docker(container):
    # Prefer restart (works if running). If that fails, try start (container was stopped).
    if safe_docker("restart", container, timeout=90):
        return True
    print("[docker] restart failed – trying start")
    return safe_docker("start", container, timeout=90)


def restart_systemd(service):
    try:
        print(f"[restart] systemctl restart → {service}")
        result = subprocess.run(
            ["systemctl", "restart", service],
            capture_output=True,
            text=True,
            timeout=90,
        )
        return result.returncode == 0
    except FileNotFoundError:
        print("[restart] systemctl not found – skipping")
        return False
    except subprocess.TimeoutExpired:
        print("[restart] systemctl TIMEOUT")
        return False
    except Exception as e:
        print("[restart] systemd ERROR:", e)
        return False


def frigate_api_restart():
    """Ask Frigate to restart via HTTP (does not leave container permanently stopped)."""
    import urllib.request
    url = FRIGATE_API_BASE.rstrip("/") + "/api/restart"
    try:
        print(f"[frigate] POST {url}")
        req = urllib.request.Request(url, method="POST", data=b"")
        with urllib.request.urlopen(req, timeout=10) as resp:
            print(f"[frigate] API restart status {resp.status}")
            return True
    except Exception as e:
        print(f"[frigate] API restart failed: {e}")
        return False


def restart_frigate():
    print(f"[frigate] Restart requested (install type: {FRIGATE_INSTALL_TYPE})")

    # Prefer Frigate's own restart endpoint — fastest and avoids "stuck stopped"
    if frigate_api_restart():
        return True

    if FRIGATE_INSTALL_TYPE == "docker":
        return restart_docker(FRIGATE_CONTAINER_NAME)

    if FRIGATE_INSTALL_TYPE == "baremetal":
        return restart_systemd(FRIGATE_SERVICE_NAME)

    print("[frigate] Unknown install type → trying Docker")
    return restart_docker(FRIGATE_CONTAINER_NAME)


def restart_go2rtc():
    print("[go2rtc] Restart requested")
    return restart_docker(GO2RTC_CONTAINER_NAME)


# ---------------------------------------------------------
# REMOVE FROM CONFIG FILES
# ---------------------------------------------------------

def remove_go2rtc_streams(cam_id):
    cfg, ok = load_yaml(GO2RTC_CONFIG_PATH)
    if not ok:
        print("[go2rtc] Skip write — could not load existing config (refusing to wipe streams)")
        return False

    streams = cfg.get("streams")
    if streams is None:
        print("[go2rtc] No streams section — nothing to remove")
        return True
    if not isinstance(streams, dict):
        print("[go2rtc] streams is not a mapping — refusing to modify")
        return False

    before = len(streams)
    streams, removed = delete_matching_stream_keys(streams, cam_id)
    cfg["streams"] = streams

    if not removed:
        print(f"[go2rtc] No matching streams for {cam_id} (left {before} streams intact)")
        return True

    backup_file(GO2RTC_CONFIG_PATH)
    if not save_yaml(GO2RTC_CONFIG_PATH, cfg):
        return False

    print(f"[go2rtc] Removed {removed} (remaining streams: {len(streams)})")
    # Best-effort; do not block remove on go2rtc restart
    try:
        restart_go2rtc()
    except Exception as e:
        print(f"[go2rtc] restart error (ignored): {e}")
    return True


def remove_frigate_camera(cam_id):
    cfg, ok = load_yaml(FRIGATE_CONFIG_PATH)
    if not ok:
        print("[frigate] Skip write — could not load Frigate config")
        return False

    changed = False

    cameras = cfg.get("cameras")
    if isinstance(cameras, dict) and cam_id in cameras:
        del cameras[cam_id]
        cfg["cameras"] = cameras
        changed = True
        print(f"[frigate] Removed camera {cam_id}")
    else:
        print(f"[frigate] Camera {cam_id} not found in cameras section")

    go2 = cfg.get("go2rtc")
    if isinstance(go2, dict):
        streams = go2.get("streams")
        if isinstance(streams, dict):
            streams, removed = delete_matching_stream_keys(streams, cam_id)
            go2["streams"] = streams
            cfg["go2rtc"] = go2
            if removed:
                changed = True
                print(f"[frigate] Removed embedded go2rtc streams: {removed}")

    if not changed:
        return True

    backup_file(FRIGATE_CONFIG_PATH)
    return save_yaml(FRIGATE_CONFIG_PATH, cfg)


# ---------------------------------------------------------
# FILE / FOLDER CLEANUP
# ---------------------------------------------------------

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


def _matches_camera_name(path, cam_id):
    target = cam_id.casefold()
    target_main = f"{cam_id}_main".casefold()
    if path.name.casefold() in (target, target_main):
        return True
    if path.stem.casefold() in (target, target_main):
        return True
    parts = [part.casefold() for part in path.parts]
    return target in parts or target_main in parts


def delete_camera_files(cam_id):
    success = True
    delete_roots = []
    for root in (FRIGATE_MEDIA_PATH, FRIGATE_CACHE_PATH):
        if root and Path(root).exists() and Path(root) not in delete_roots:
            delete_roots.append(Path(root))

    for root in delete_roots:
        print(f"[frigate] Scanning delete root: {root}")
        try:
            candidates = sorted(
                root.rglob("*"),
                key=lambda p: (len(p.parts), str(p)),
                reverse=True,
            )
        except Exception as e:
            print(f"[frigate] Scan failed for {root}: {e}")
            success = False
            continue
        for path in candidates:
            if _matches_camera_name(path, cam_id):
                if path.is_dir():
                    if not delete_dir_if_exists(path):
                        success = False
                elif path.is_file():
                    if not delete_file_if_exists(path):
                        success = False

    if not delete_dir_if_exists(Path(FRIGATE_MEDIA_PATH) / cam_id):
        success = False
    if not delete_dir_if_exists(Path(FRIGATE_CACHE_PATH) / cam_id):
        success = False
    return success


# ---------------------------------------------------------
# PUBLIC API
# ---------------------------------------------------------

def remove_camera(cam_id):
    print(f"[remove_camera] Removing {cam_id}")

    cam_id = (cam_id or "").strip()
    if not cam_id:
        return {
            "event": "cameraRemoveResult",
            "status": "error",
            "ok": False,
            "message": "Invalid camera name",
        }

    # Do NOT docker-stop Frigate first — that leaves it down if restart fails
    # and PX stays on "Frigate restarting" forever.

    go2_ok = remove_go2rtc_streams(cam_id)
    fr_ok = remove_frigate_camera(cam_id)

    # Media cleanup is best-effort and must not block the result
    try:
        delete_ok = delete_camera_files(cam_id)
    except Exception as e:
        print(f"[frigate] delete_camera_files ERROR: {e}")
        delete_ok = False

    # Config success is enough for PX to close the popup
    ok = go2_ok and fr_ok

    restart_ok = False
    if ok:
        try:
            restart_ok = restart_frigate()
        except Exception as e:
            print(f"[frigate] restart ERROR (ignored): {e}")
            restart_ok = False

    msg = f"Camera {cam_id} removed"
    if not delete_ok:
        msg += " (some media files could not be deleted)"
    if ok and not restart_ok:
        msg += " – please restart Frigate manually if UI does not reload"

    print(f"[remove_camera] done ok={ok} restart_ok={restart_ok}")

    return {
        "event": "cameraRemoveResult",
        "status": "ok" if ok else "error",
        "ok": ok,
        "message": msg,
    }