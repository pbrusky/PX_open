"""
add_camera.py — write configs, then BLOCKING restart go2rtc + Frigate.
Signature matches frigate_server.py:
  add_camera(id, rtsp, bool(record), rtsp_sub)
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
            print(f"[add_camera] missing {path} — starting empty")
            return {}, True
        with open(path, "r", encoding="utf-8") as f:
            raw = f.read()
        if not raw.strip():
            return {}, True
        data = yaml.safe_load(raw)
        if data is None:
            data = {}
        if not isinstance(data, dict):
            return {}, False
        return data, True
    except Exception as e:
        print("[add_camera] load_yaml ERROR:", e)
        return {}, False


def save_yaml(path, data):
    try:
        parent = os.path.dirname(str(path))
        if parent and not os.path.exists(parent):
            os.makedirs(parent, exist_ok=True)
        with open(str(path), "w", encoding="utf-8") as f:
            yaml.safe_dump(
                data, f, default_flow_style=False, sort_keys=False, allow_unicode=True
            )
        print(f"[add_camera] wrote {path}")
        return True
    except Exception as e:
        print("[add_camera] save_yaml ERROR:", e)
        return False


def normalize_id(cam_id):
    return (str(cam_id) if cam_id is not None else "").strip().replace(" ", "_")


def as_str(value):
    if value is None or isinstance(value, bool):
        return ""
    return str(value).strip()


def as_bool(value, default=True):
    if isinstance(value, bool):
        return value
    if value is None:
        return default
    if isinstance(value, (int, float)):
        return bool(value)
    s = str(value).strip().lower()
    if s in ("1", "true", "yes", "on"):
        return True
    if s in ("0", "false", "no", "off", ""):
        return False
    return default


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
print(f"[add_camera] docker={DOCKER}")


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
    time.sleep(3)
    print(f"========== RESTART done api_ready={ready} ==========")
    return ready


def restart_frigate():
    return force_restart_and_wait()


def restart_go2rtc():
    return restart_named(GO2RTC_CONTAINER_NAME or "go2rtc")


def upsert_go2rtc_streams(cam_id, main_url, sub_url):
    cfg, ok = load_yaml(GO2RTC_CONFIG_PATH)
    if not ok:
        print("[go2rtc] refuse to write — load failed")
        return False

    streams = cfg.get("streams")
    if not isinstance(streams, dict):
        streams = {}

    sub = as_str(sub_url)
    main = as_str(main_url)
    if not sub and not main:
        print("[go2rtc] no URLs — skip")
        return True
    if not sub:
        sub = main
    if not main:
        main = sub

    streams[cam_id] = sub
    print(f"[go2rtc] set streams['{cam_id}']")

    if main and main != sub:
        streams[f"{cam_id}_main"] = main
        print(f"[go2rtc] set streams['{cam_id}_main']")

    cfg["streams"] = streams
    backup_file(GO2RTC_CONFIG_PATH)
    return save_yaml(GO2RTC_CONFIG_PATH, cfg)


def upsert_frigate_camera(cam_id, main_url, sub_url, record=True):
    cfg, ok = load_yaml(FRIGATE_CONFIG_PATH)
    if not ok:
        print("[frigate] refuse to write — load failed")
        return False

    sub = as_str(sub_url)
    main = as_str(main_url)
    if not sub and not main:
        return False
    if not sub:
        sub = main
    if not main:
        main = sub

    dual = bool(main and sub and main != sub)
    detect_path = f"rtsp://127.0.0.1:8554/{cam_id}"
    record_path = f"rtsp://127.0.0.1:8554/{cam_id}_main" if dual else detect_path

    cameras = cfg.get("cameras")
    if not isinstance(cameras, dict):
        cameras = {}

    cam = {
        "enabled": True,
        "ffmpeg": {"inputs": []},
        "detect": {"width": 1280, "height": 720},
        "record": {"enabled": bool(record)},
        "live": {"streams": {}},
    }

    if dual:
        cam["ffmpeg"]["inputs"] = [
            {"path": detect_path, "input_args": "preset-rtsp-restream", "roles": ["detect"]},
            {"path": record_path, "input_args": "preset-rtsp-restream", "roles": ["record"]},
        ]
        cam["live"]["streams"] = {
            "Sub Stream": cam_id,
            "Main Stream": f"{cam_id}_main",
        }
    else:
        cam["ffmpeg"]["inputs"] = [
            {
                "path": detect_path,
                "input_args": "preset-rtsp-restream",
                "roles": ["detect", "record"],
            }
        ]
        cam["live"]["streams"] = {"Main Stream": cam_id}

    cameras[cam_id] = cam
    cfg["cameras"] = cameras

    go2 = cfg.get("go2rtc")
    if not isinstance(go2, dict):
        go2 = {}
    emb = go2.get("streams")
    if not isinstance(emb, dict):
        emb = {}
    emb[cam_id] = sub
    if dual:
        emb[f"{cam_id}_main"] = main
    go2["streams"] = emb
    cfg["go2rtc"] = go2

    if "record" not in cfg or not isinstance(cfg["record"], dict):
        cfg["record"] = {"enabled": True}
    else:
        cfg["record"]["enabled"] = True

    backup_file(FRIGATE_CONFIG_PATH)
    if not save_yaml(FRIGATE_CONFIG_PATH, cfg):
        return False

    print(f"[frigate] upserted camera {cam_id} (dual={dual})")
    return True


def add_camera(cam_id, main_url="", record=True, sub_url=""):
    if isinstance(record, str) and (isinstance(sub_url, bool) or sub_url is None):
        sub_url, record = record, (sub_url if isinstance(sub_url, bool) else True)
    elif isinstance(sub_url, bool) and isinstance(record, str):
        record, sub_url = sub_url, record

    main_url = as_str(main_url)
    sub_url = as_str(sub_url)
    record = as_bool(record, True)
    cam_id = normalize_id(cam_id)

    print(
        f"[add_camera] id={cam_id!r} main={main_url!r} "
        f"sub={sub_url!r} record={record!r}"
    )

    if not cam_id:
        return {
            "event": "cameraAddResult",
            "status": "error",
            "ok": False,
            "message": "Invalid camera name",
        }

    if not main_url and not sub_url:
        return {
            "event": "cameraAddResult",
            "status": "error",
            "ok": False,
            "message": "Main or sub RTSP URL required",
        }

    go2_ok = upsert_go2rtc_streams(cam_id, main_url, sub_url)
    fr_ok = upsert_frigate_camera(cam_id, main_url, sub_url, record=record)
    ok = go2_ok and fr_ok

    if not ok:
        msg = f"Failed to update config for {cam_id}"
        if not go2_ok:
            msg = f"Failed to update go2rtc for {cam_id}"
        elif not fr_ok:
            msg = f"Failed to update Frigate config for {cam_id}"
        return {
            "event": "cameraAddResult",
            "status": "error",
            "ok": False,
            "message": msg,
            "cameraId": cam_id,
        }

    try:
        force_restart_and_wait()
    except Exception as e:
        print(f"[add_camera] restart ERROR: {e}")

    print(f"[add_camera] ===== done ok=True camera={cam_id} =====")
    return {
        "event": "cameraAddResult",
        "status": "ok",
        "ok": True,
        "message": f"Camera {cam_id} added",
        "cameraId": cam_id,
    }