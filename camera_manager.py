import os
import yaml
import shutil
import requests
from requests.auth import HTTPDigestAuth
import xml.etree.ElementTree as ET
import time
import subprocess

# Import shared config from main server
from config import (
    FRIGATE_CONFIG_PATH,
    GO2RTC_CONFIG_PATH,
    FRIGATE_BASE,
    GO2RTC_BASE
)

# ---------------------------------------------------------
# UTILITIES
# ---------------------------------------------------------

def backup_file(path):
    if not path or not os.path.exists(path):
        return
    try:
        path_str = str(path)
        backup_path = path_str + f".bak_{int(time.time())}"
        shutil.copy2(path_str, backup_path)
        print(f"[backup] Created {os.path.basename(backup_path)}")
    except Exception as e:
        print("[backup] ERROR:", e)

def load_yaml(path):
    if not os.path.exists(path):
        return {}
    try:
        with open(path, "r", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        print("[camera_manager] load_yaml ERROR:", e)
        return {}

def save_yaml(path, data):
    try:
        with open(path, "w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False)
        return True
    except Exception as e:
        print("[camera_manager] save_yaml ERROR:", e)
        return False

def is_valid_camera_name(name):
    return isinstance(name, str) and len(name.strip()) > 0

def is_valid_rtsp_url(url):
    return isinstance(url, str) and url.lower().startswith("rtsp://")

# ---------------------------------------------------------
# GO2RTC RESTART
# ---------------------------------------------------------

def restart_go2rtc():
    """
    Restart the go2rtc Docker container so it reloads go2rtc.yaml.
    """
    try:
        print("[go2rtc] Restarting container...")
        result = subprocess.run(
            ["docker", "restart", "go2rtc"],
            capture_output=True,
            text=True
        )
        print("[go2rtc] Restart output:", result.stdout.strip())
        print("[go2rtc] Restart complete")
        return True
    except Exception as e:
        print(f"[go2rtc] restart ERROR: {e}")
        return False

# ---------------------------------------------------------
# GO2RTC STREAM MANAGEMENT
# ---------------------------------------------------------

def go2rtc_set_stream(cam_id, rtsp_url):
    try:
        backup_file(GO2RTC_CONFIG_PATH)
        cfg = load_yaml(GO2RTC_CONFIG_PATH)

        if not cfg:
            cfg = dict(GO2RTC_BASE)

        if 'streams' not in cfg or not isinstance(cfg['streams'], dict):
            cfg['streams'] = {}

        # Clean URL and wrap in ffmpeg proxy
        clean_url = rtsp_url.split('?')[0]
        cfg['streams'][cam_id] = f"ffmpeg:{clean_url}#tcp"

        print(f"[go2rtc] Added/Updated {cam_id} in go2rtc.yaml")

        if save_yaml(GO2RTC_CONFIG_PATH, cfg):
            restart_go2rtc()
            return True
        return False

    except Exception as e:
        print("[go2rtc] set_stream ERROR:", e)
        return False

def go2rtc_remove_stream(cam_id):
    try:
        backup_file(GO2RTC_CONFIG_PATH)
        cfg = load_yaml(GO2RTC_CONFIG_PATH)

        if 'streams' in cfg and cam_id in cfg['streams']:
            del cfg['streams'][cam_id]
            print(f"[go2rtc] Removed {cam_id} from go2rtc.yaml")
            if save_yaml(GO2RTC_CONFIG_PATH, cfg):
                restart_go2rtc()
                return True
        return True
    except Exception as e:
        print("[go2rtc] remove_stream ERROR:", e)
        return False

# ---------------------------------------------------------
# FRIGATE CONFIG MANAGEMENT
# ---------------------------------------------------------

def _ensure_frigate_base(cfg):
    """
    Ensure cfg has the required Frigate structure.
    Preserve all existing global values.
    Only fill missing required sections.
    """
    # If config is empty, use the base template
    if not cfg:
        return {
            "mqtt": {"enabled": False},
            "detectors": {"cpu1": {"type": "cpu"}},
            "record": {"enabled": False},
            "snapshots": {"enabled": False},
            "cameras": {},
            "version": "0.17-0"
        }

    # Ensure required top-level keys exist
    if "mqtt" not in cfg:
        cfg["mqtt"] = {"enabled": False}

    if "detectors" not in cfg:
        cfg["detectors"] = {"cpu1": {"type": "cpu"}}

    if "record" not in cfg:
        cfg["record"] = {"enabled": False}

    if "snapshots" not in cfg:
        cfg["snapshots"] = {"enabled": False}

    if "cameras" not in cfg or not isinstance(cfg["cameras"], dict):
        cfg["cameras"] = {}

    if "version" not in cfg:
        cfg["version"] = "0.17-0"

    return cfg

def ensure_camera_in_frigate(cam_id, rtsp_url, record=True):
    try:
        backup_file(FRIGATE_CONFIG_PATH)
        cfg = load_yaml(FRIGATE_CONFIG_PATH)
        cfg = _ensure_frigate_base(cfg)

        # Enable global recording if user wants recording on this camera
        if record:
            if "record" not in cfg:
                cfg["record"] = {}
            cfg["record"]["enabled"] = True

        global_record_enabled = bool(cfg.get("record", {}).get("enabled", False))

        roles = ["detect"]
        if global_record_enabled and record:
            roles.append("record")

        camera_block = {
            "enabled": True,
            "ffmpeg": {
                "inputs": [
                    {
                        "path": rtsp_url,
                        "input_args": "preset-rtsp-generic",
                        "roles": roles
                    }
                ]
            },
            "live": {
                "streams": {
                    "Main Stream": cam_id
                }
            },
            "detect": {
                "width": 1280,
                "height": 720
            }
        }

        if global_record_enabled and record:
            camera_block["record"] = {"enabled": True}

        cfg["cameras"][cam_id] = camera_block

        print(f"[frigate] Added/Updated {cam_id} - Recording: {'ENABLED' if record else 'DISABLED'}")
        return save_yaml(FRIGATE_CONFIG_PATH, cfg)

    except Exception as e:
        print("[frigate] ensure_camera_in_frigate ERROR:", e)
        return False

def remove_camera_from_frigate(cam_id):
    try:
        backup_file(FRIGATE_CONFIG_PATH)
        cfg = load_yaml(FRIGATE_CONFIG_PATH)

        cfg = _ensure_frigate_base(cfg)

        if "cameras" in cfg and cam_id in cfg["cameras"]:
            del cfg["cameras"][cam_id]
            return save_yaml(FRIGATE_CONFIG_PATH, cfg)

        return False

    except Exception as e:
        print("[frigate] remove_camera_from_frigate ERROR:", e)
        return False

def frigate_reload():
    print("[frigate] reload skipped (Frigate has no HTTP reload API)")
    return True

# ---------------------------------------------------------
# RTSP RESOLUTION
# ---------------------------------------------------------

def get_rtsp_url(ip, username="", password=""):
    print(f"[RTSP] Attempting to get URL for {ip}")
    auth = HTTPDigestAuth(username, password) if username else None
    endpoint = f"http://{ip}/onvif/device_service"

    tokens = ["Profile_1", "profile_1", "0", "1", "Main"]

    for token in tokens:
        try:
            SOAP = f'''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body>
    <GetStreamUri xmlns="http://www.onvif.org/ver10/media/wsdl">
      <StreamSetup>
        <Stream xmlns="http://www.onvif.org/ver10/schema">RTP-Unicast</Stream>
        <Transport xmlns="http://www.onvif.org/ver10/schema">
          <Protocol>RTSP</Protocol>
        </Transport>
      </StreamSetup>
      <ProfileToken>{token}</ProfileToken>
    </GetStreamUri>
  </s:Body>
</s:Envelope>'''

            r = requests.post(endpoint, data=SOAP, timeout=2.5, auth=auth)

            if r.status_code == 200:
                xml = ET.fromstring(r.text)
                uri = xml.find(".//{*}Uri")

                if uri is not None and uri.text:
                    rtsp = uri.text.strip()
                    print(f"[RTSP] SUCCESS with token '{token}'")

                    if username and password and "rtsp://" in rtsp:
                        rtsp = rtsp.replace("rtsp://", f"rtsp://{username}:{password}@")

                    return rtsp

        except Exception:
            continue

    print(f"[RTSP] ONVIF failed for {ip}, using fallback")

    if username:
        return f"rtsp://{username}:{password}@{ip}:554/Streaming/Channels/101"
    else:
        return f"rtsp://{ip}:554/cam/realmonitor?channel=1&subtype=0"

# ---------------------------------------------------------
# CAMERA CRUD
# ---------------------------------------------------------

def add_camera(cam_id, rtsp_url, record=True):
    print(f"[camera_manager] add_camera {cam_id} -> {rtsp_url}")

    if not is_valid_camera_name(cam_id) or not is_valid_rtsp_url(rtsp_url):
        return {"status": "error", "go2rtc": False, "frigate_reload": False}

    go2_ok = go2rtc_set_stream(cam_id, rtsp_url)
    fr_ok = ensure_camera_in_frigate(cam_id, rtsp_url, record)
    reload_ok = frigate_reload() if fr_ok else False

    status = "ok" if (go2_ok and fr_ok and reload_ok) else "error"

    return {
        "status": status,
        "go2rtc": go2_ok,
        "frigate_reload": reload_ok
    }

def edit_camera(cam_id, rtsp_url):
    print(f"[camera_manager] edit_camera {cam_id} -> {rtsp_url}")

    if not is_valid_camera_name(cam_id) or not is_valid_rtsp_url(rtsp_url):
        return {"status": "error", "go2rtc": False, "frigate_reload": False}

    go2_ok = go2rtc_set_stream(cam_id, rtsp_url)
    fr_ok = ensure_camera_in_frigate(cam_id, rtsp_url, record=True)
    reload_ok = frigate_reload() if fr_ok else False

    status = "ok" if (go2_ok and fr_ok and reload_ok) else "error"

    return {
        "status": status,
        "go2rtc": go2_ok,
        "frigate_reload": reload_ok
    }

def remove_camera(cam_id):
    print(f"[camera_manager] remove_camera {cam_id}")

    if not is_valid_camera_name(cam_id):
        return {"status": "error", "go2rtc": False, "frigate_reload": False}

    go2_ok = go2rtc_remove_stream(cam_id)
    fr_ok = remove_camera_from_frigate(cam_id)
    reload_ok = frigate_reload() if fr_ok else False

    status = "ok" if (go2_ok and fr_ok and reload_ok) else "error"

    return {
        "status": status,
        "go2rtc": go2_ok,
        "frigate_reload": reload_ok
    }
