"""
remove_camera.py — match original client flow:

Client closes "Frigate Restarting" only when:
  loadCameras() returns list.length > 0 AND elapsed >= 3000ms

So docker restart must finish and Frigate API must be up BEFORE HTTP returns.
"""
import yaml
import os
import shutil
import time
import subprocess
import shutil as _shutil
from pathlib import Path

from config import (
    FRIGATE_CONFIG_PATH,
    GO2RTC_CONFIG_PATH,
    FRIGATE_INSTALL_TYPE,
    FRIGATE_CONTAINER_NAME,
    FRIGATE_SERVICE_NAME,
    GO2RTC_CONTAINER_NAME,
    FRIGATE_MEDIA_PATH,
    FRIGATE_CACHE_PATH,
)

try:
    from config import FRIGATE_API_BASE
except Exception:
    FRIGATE_API_BASE = os.environ.get("FRIGATE_API_BASE", "http://127.0.0.1:5000")


def backup_file(path):
    if not path or not os.path.exists(str(path)):
        return
    try:
        shutil.copy2(str(path), f"{path}.bak_{int(time.time())}")
    except Exception as e:
        print("[backup] ERROR:", e)


def load_yaml(path):
    try:
        path = str(path)
        if not os.path.exists(path):
            return {}, False
        with open(path, "r", encoding="utf-8") as f:
            raw = f.read()
        if not raw.strip():
            return {}, False
        data = yaml.safe_load(raw)
        if not isinstance(data, dict):
            return {}, False
        return data, True
    except Exception as e:
        print("[load_yaml] ERROR:", e)
        return {}, False


def save_yaml(path, data):
    try:
        with open(str(path), "w", encoding="utf-8") as f:
            yaml.safe_dump(
                data, f, default_flow_style=False, sort_keys=False, allow_unicode=True
            )
        return True
    except Exception as e:
        print("[save_yaml] ERROR:", e)
        return False


def stream_keys(cam_id):
    cam_id = (cam_id or "").strip()
    return {
        cam_id,
        f"{cam_id}_main",
        f"{cam_id}_sub",
        cam_id.replace(" ", "_"),
        f"{cam_id.replace(' ', '_')}_main",
    }


def delete_stream_keys(streams, cam_id):
    if not isinstance(streams, dict):
        return {}, []
    wanted = {k.casefold() for k in stream_keys(cam_id)}
    removed = []
    for key in list(streams.keys()):
        if str(key).casefold() in wanted:
            del streams[key]
            removed.append(str(key))
    return streams, removed


def find_docker():
    exe = _shutil.which("docker")
    if exe:
        return exe
    for c in (
        r"C:\Program Files\Docker\Docker\resources\bin\docker.exe",
        r"C:\Program Files\Docker\Docker\resources\docker.exe",
        r"C:\ProgramData\DockerDesktop\version-bin\docker.exe",
    ):
        if os.path.isfile(c):
            return c
    return "docker"


DOCKER = find_docker()
print(f"[remove_camera] docker={DOCKER}")


def docker_cmd(*args, timeout=180):
    cmd_list = [DOCKER] + list(args)
    print(f"[docker] {' '.join(str(a) for a in cmd_list)}")
    try:
        r = subprocess.run(
            cmd_list, capture_output=True, text=True, timeout=timeout, shell=False
        )
        out = (r.stdout or "").strip()
        err = (r.stderr or "").strip()
        if r.returncode == 0:
            if out:
                print(f"[docker] ok: {out[:300]}")
            return True
        print(f"[docker] rc={r.returncode}: {err or out}")
        return False
    except Exception as e:
        print(f"[docker] ERROR: {e}")
        return False


def restart_named(name):
    if not name:
        return False
    if docker_cmd("restart", name):
        print(f"[docker] RESTARTED: {name}")
        return True
    if docker_cmd("start", name):
        print(f"[docker] STARTED: {name}")
        return True
    return False


def wait_frigate_api(timeout_sec=90):
    """Block until Frigate answers so client loadCameras() can get cameras."""
    import urllib.request
    url = str(FRIGATE_API_BASE).rstrip("/") + "/api/config"
    deadline = time.time() + timeout_sec
    while time.time() < deadline:
        try:
            with urllib.request.urlopen(url, timeout=3) as resp:
                if resp.status == 200:
                    print(f"[frigate] API ready ({url})")
                    return True
        except Exception:
            pass
        time.sleep(2)
    print("[frigate] API wait timed out")
    return False


def force_restart_and_wait():
    print("========== RESTART Frigate + go2rtc (blocking) ==========")
    go2 = GO2RTC_CONTAINER_NAME or "go2rtc"
    fr = FRIGATE_CONTAINER_NAME or "frigate-frigate-1"

    restart_named(go2)
    time.sleep(2)
    restart_named(fr)

    ready = wait_frigate_api(timeout_sec=90)
    # Extra settle so /api/cameras is populated for the client
    time.sleep(3)
    print(f"========== RESTART done api_ready={ready} ==========")
    return ready


def remove_go2rtc_streams(cam_id):
    cfg, ok = load_yaml(GO2RTC_CONFIG_PATH)
    if not ok:
        print("[go2rtc] load failed — skip write")
        return False
    streams = cfg.get("streams")
    if not isinstance(streams, dict):
        print("[go2rtc] no streams dict")
        return True
    streams, removed = delete_stream_keys(streams, cam_id)
    cfg["streams"] = streams
    if not removed:
        print(f"[go2rtc] nothing to remove for {cam_id}")
        return True
    backup_file(GO2RTC_CONFIG_PATH)
    if save_yaml(GO2RTC_CONFIG_PATH, cfg):
        print(f"[go2rtc] removed {removed}")
        return True
    return False


def remove_frigate_camera(cam_id):
    cfg, ok = load_yaml(FRIGATE_CONFIG_PATH)
    if not ok:
        print("[frigate] load failed — skip write")
        return False
    changed = False
    cameras = cfg.get("cameras")
    for key in (cam_id, cam_id.replace(" ", "_")):
        if isinstance(cameras, dict) and key in cameras:
            del cameras[key]
            cfg["cameras"] = cameras
            changed = True
            print(f"[frigate] removed camera {key}")
            break
    go2 = cfg.get("go2rtc")
    if isinstance(go2, dict) and isinstance(go2.get("streams"), dict):
        streams, removed = delete_stream_keys(go2["streams"], cam_id)
        go2["streams"] = streams
        cfg["go2rtc"] = go2
        if removed:
            changed = True
            print(f"[frigate] removed embedded streams {removed}")
    if not changed:
        return True
    backup_file(FRIGATE_CONFIG_PATH)
    return save_yaml(FRIGATE_CONFIG_PATH, cfg)


def delete_camera_files(cam_id):
    for root in (FRIGATE_MEDIA_PATH, FRIGATE_CACHE_PATH):
        try:
            root = Path(root)
            if not root.exists():
                continue
            for name in (cam_id, cam_id.replace(" ", "_"), f"{cam_id}_main"):
                folder = root / name
                if folder.is_dir():
                    print(f"[media] delete {folder}")
                    shutil.rmtree(folder, ignore_errors=True)
        except Exception as e:
            print(f"[media] ERROR: {e}")


def remove_camera(cam_id):
    print(f"[remove_camera] ===== Removing {cam_id!r} =====")
    cam_id = (cam_id or "").strip()
    if not cam_id:
        return {
            "event": "cameraRemoveResult",
            "status": "error",
            "ok": False,
            "message": "Invalid camera name",
        }

    go2_ok = remove_go2rtc_streams(cam_id)
    fr_ok = remove_frigate_camera(cam_id)
    if not (go2_ok and fr_ok):
        return {
            "event": "cameraRemoveResult",
            "status": "error",
            "ok": False,
            "message": f"Failed to update config for {cam_id}",
        }

    # Blocking restart — required for existing PX popup logic
    try:
        force_restart_and_wait()
    except Exception as e:
        print(f"[remove_camera] restart ERROR: {e}")

    try:
        delete_camera_files(cam_id)
    except Exception as e:
        print(f"[remove_camera] media ERROR: {e}")

    print("[remove_camera] ===== done ok=True =====")
    return {
        "event": "cameraRemoveResult",
        "status": "ok",
        "ok": True,
        "message": f"Camera {cam_id} removed",
    }