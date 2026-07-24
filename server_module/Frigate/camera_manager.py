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
    GO2RTC_BASE,
    FRIGATE_CONTAINER_NAME,
    GO2RTC_CONTAINER_NAME,
    FRIGATE_INSTALL_TYPE,
    FRIGATE_SERVICE_NAME
)

# ---------------------------------------------------------
# UTILITIES
# ---------------------------------------------------------

def backup_file(path):
    if not path or not os.path.exists(path):
        return
    try:
        backup_path = f"{path}.bak_{int(time.time())}"
        shutil.copy2(path, backup_path)
        print(f"[backup] Created {os.path.basename(backup_path)}")
    except Exception as e:
        print("[backup] ERROR:", e)

def load_yaml(path):
    try:
        if not os.path.exists(path):
            return {}
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
# INSTALL‑TYPE AWARE RESTART LOGIC
# ---------------------------------------------------------

def restart_docker(container_name):
    try:
        print(f"[restart] Docker restart → {container_name}")
        result = subprocess.run(
            ["docker", "restart", container_name],
            capture_output=True,
            text=True
        )
        print("[restart] Output:", result.stdout.strip())
        return True
    except Exception as e:
        print("[restart] Docker ERROR:", e)
        return False

def restart_systemd(service_name):
    try:
        print(f"[restart] systemctl restart → {service_name}")
        result = subprocess.run(
            ["systemctl", "restart", service_name],
            capture_output=True,
            text=True
        )
        print("[restart] Output:", result.stdout.strip())
        return True
    except Exception as e:
        print("[restart] systemd ERROR:", e)
        return False

def restart_hassio():
    try:
        print("[restart] Home Assistant add‑on restart → frigate")
        result = subprocess.run(
            ["ha", "addons", "restart", "frigate"],
            capture_output=True,
            text=True
        )
        print("[restart] Output:", result.stdout.strip())
        return True
    except Exception as e:
        print("[restart] hassio ERROR:", e)
        return False

def restart_frigate():
    print(f"[frigate] Restart requested (install type: {FRIGATE_INSTALL_TYPE})")

    if FRIGATE_INSTALL_TYPE == "docker":
        return restart_docker(FRIGATE_CONTAINER_NAME)

    if FRIGATE_INSTALL_TYPE == "hassio":
        return restart_hassio()

    if FRIGATE_INSTALL_TYPE == "baremetal":
        return restart_systemd(FRIGATE_SERVICE_NAME)

    print("[frigate] Unknown install type → using Docker fallback")
    return restart_docker(FRIGATE_CONTAINER_NAME)

def restart_go2rtc():
    print("[go2rtc] Restart requested")
    return restart_docker(GO2RTC_CONTAINER_NAME)

# ---------------------------------------------------------
# GO2RTC STREAM MANAGEMENT
# ---------------------------------------------------------

def go2rtc_set_stream(cam_id, rtsp_url):
    try:
        backup_file(GO2RTC_CONFIG_PATH)
        cfg = load_yaml(GO2RTC_CONFIG_PATH)

        cfg.setdefault("streams", {})

        clean_url = rtsp_url.split("?")[0]
        cfg["streams"][cam_id] = f"ffmpeg:{clean_url}#tcp"

        print(f"[go2rtc] Added/Updated {cam_id}")

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

        if "streams" in cfg and cam_id in cfg["streams"]:
            del cfg["streams"][cam_id]
            print(f"[go2rtc] Removed {cam_id}")
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
    cfg.setdefault("mqtt", {"enabled": False})
    cfg.setdefault("detectors", {"cpu1": {"type": "cpu"}})
    cfg.setdefault("record", {"enabled": False})
    cfg.setdefault("snapshots", {"enabled": False})
    cfg.setdefault("cameras", {})
    cfg.setdefault("version", "0.17-0")
    return cfg

def ensure_camera_in_frigate(cam_id, rtsp_url, record=True):
    try:
        backup_file(FRIGATE_CONFIG_PATH)
        cfg = load_yaml(FRIGATE_CONFIG_PATH)
        cfg = _ensure_frigate_base(cfg)

        if record:
            cfg["record"]["enabled"] = True

        roles = ["detect"]
        if cfg["record"]["enabled"] and record:
            roles.append("record")

        cfg["cameras"][cam_id] = {
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
            "live": {"streams": {"Main Stream": cam_id}},
            "detect": {"width": 1280, "height": 720},
            "record": {"enabled": cfg["record"]["enabled"] and record}
        }

        print(f"[frigate] Added/Updated {cam_id}")
        return save_yaml(FRIGATE_CONFIG_PATH, cfg)

    except Exception as e:
        print("[frigate] ensure_camera_in_frigate ERROR:", e)
        return False

def remove_camera_from_frigate(cam_id):
    try:
        backup_file(FRIGATE_CONFIG_PATH)
        cfg = load_yaml(FRIGATE_CONFIG_PATH)
        cfg = _ensure_frigate_base(cfg)

        if cam_id in cfg["cameras"]:
            del cfg["cameras"][cam_id]
            print(f"[frigate] Removed {cam_id}")
            return save_yaml(FRIGATE_CONFIG_PATH, cfg)

        return False

    except Exception as e:
        print("[frigate] remove_camera_from_frigate ERROR:", e)
        return False

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
            SOAP = f"""<?xml version="1.0"?>
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
</s:Envelope>"""

            r = requests.post(endpoint, data=SOAP, timeout=2.5, auth=auth)

            if r.status_code == 200:
                xml = ET.fromstring(r.text)
                uri = xml.find(".//{*}Uri")
                if uri is not None and uri.text:
                    rtsp = uri.text.strip()
                    print(f"[RTSP] SUCCESS with token '{token}'")
                    if username and password:
                        rtsp = rtsp.replace("rtsp://", f"rtsp://{username}:{password}@")
                    return rtsp

        except Exception:
            continue

    print(f"[RTSP] ONVIF failed for {ip}, using fallback")

    if username:
        return f"rtsp://{username}:{password}@{ip}:554/Streaming/Channels/101"
    return f"rtsp://{ip}:554/cam/realmonitor?channel=1&subtype=0"

# ---------------------------------------------------------
# CAMERA CRUD (INSTALL‑TYPE AWARE)
# ---------------------------------------------------------

def add_camera(cam_id, rtsp_url, record=True):
    print(f"[camera_manager] add_camera {cam_id}")

    if not is_valid_camera_name(cam_id) or not is_valid_rtsp_url(rtsp_url):
        return {
            "event": "cameraAddResult",
            "status": "error",
            "message": "Invalid camera name or RTSP URL"
        }

    go2_ok = go2rtc_set_stream(cam_id, rtsp_url)
    fr_ok = ensure_camera_in_frigate(cam_id, rtsp_url, record)
    restart_ok = restart_frigate() if fr_ok else False

    return {
        "event": "cameraAddResult",
        "status": "ok" if (go2_ok and fr_ok and restart_ok) else "error",
        "message": f"Camera {cam_id} added",
        "go2rtc": go2_ok,
        "frigate_restart": restart_ok
    }

def edit_camera(cam_id, rtsp_url):
    print(f"[camera_manager] edit_camera {cam_id}")

    if not is_valid_camera_name(cam_id) or not is_valid_rtsp_url(rtsp_url):
        return {
            "event": "cameraEditResult",
            "status": "error",
            "message": "Invalid camera name or RTSP URL"
        }

    go2_ok = go2rtc_set_stream(cam_id, rtsp_url)
    fr_ok = ensure_camera_in_frigate(cam_id, rtsp_url, True)
    restart_ok = restart_frigate() if fr_ok else False

    return {
        "event": "cameraEditResult",
        "status": "ok" if (go2_ok and fr_ok and restart_ok) else "error",
        "message": f"Camera {cam_id} edited",
        "go2rtc": go2_ok,
        "frigate_restart": restart_ok
    }

def remove_camera(cam_id):
    print(f"[camera_manager] remove_camera {cam_id}")

    if not is_valid_camera_name(cam_id):
        return {
            "event": "cameraRemoveResult",
            "status": "error",
            "message": "Invalid camera name"
        }

    go2_ok = go2rtc_remove_stream(cam_id)
    fr_ok = remove_camera_from_frigate(cam_id)
    restart_ok = restart_frigate() if fr_ok else False

    return {
        "event": "cameraRemoveResult",
        "status": "ok" if (go2_ok and fr_ok and restart_ok) else "error",
        "message": f"Camera {cam_id} removed",
        "go2rtc": go2_ok,
        "frigate_restart": restart_ok
    }
