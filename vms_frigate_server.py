import http.server
import ssl
import json
import socket
import threading
import time
import requests
import subprocess
import uuid
import os
import shutil
import yaml
import traceback
from requests.auth import HTTPDigestAuth
import xml.etree.ElementTree as ET

# CONFIG
HTTP_PORT = 8001
HTTPS_PORT = 8002
HOST = "0.0.0.0"
DISCOVERY_PORT = 3666
BROADCAST_IP = "255.255.255.255"

FRIGATE_HOST = "127.0.0.1"
FRIGATE_PORT = 5000
FRIGATE_BASE = f"http://{FRIGATE_HOST}:{FRIGATE_PORT}"

GO2RTC_HOST = "127.0.0.1"
GO2RTC_PORT = 1984
GO2RTC_BASE = f"http://{GO2RTC_HOST}:{GO2RTC_PORT}"
GO2RTC_CONFIG_PATH = r"C:\frigate\go2rtc.yaml"
FRIGATE_CONFIG_PATH = r"C:\frigate\config\config.yml"

SYSTEM_ID = "{11111111-2222-3333-4444-555555555555}"
MODULE_ID = "{66666666-7777-8888-9999-000000000000}"
SYSTEM_NAME = "Frigate System"
LAN_IP = "10.36.24.104"

PROGRESS_FILE = r"C:\PX\onvif_progress.log"

# UTILITIES
def backup_file(path):
    if os.path.exists(path):
        try:
            shutil.copy2(path, path + ".bak")
        except:
            pass

def is_valid_camera_name(name):
    return isinstance(name, str) and bool(name.strip())

def is_valid_rtsp_url(url):
    return isinstance(url, str) and url.lower().startswith("rtsp://")

def go2rtc_set_stream(name, rtsp_url):
    try:
        r = requests.post(f"{GO2RTC_BASE}/api/streams", json={name: rtsp_url}, timeout=5)
        return r.status_code in (200, 201)
    except:
        return False

def go2rtc_remove_stream(name):
    try:
        r = requests.delete(f"{GO2RTC_BASE}/api/streams/{name}", timeout=5)
        return r.status_code == 200
    except:
        return False

def frigate_reload():
    try:
        r = requests.post(f"{FRIGATE_BASE}/api/reload", timeout=10)
        return r.status_code == 200
    except:
        return False

def get_subnet_from_lan_ip():
    try:
        parts = LAN_IP.split(".")
        if len(parts) == 4:
            return ".".join(parts[:3]) + "."
    except:
        pass
    return "192.168.1."

# ---------------------------------------------------------
# ONVIF → RTSP RESOLVER
# ---------------------------------------------------------
def get_rtsp_url(ip, username="", password=""):
    endpoint = f"http://{ip}/onvif/device_service"
    auth = HTTPDigestAuth(username, password) if username else None

    # 1. ONVIF GetStreamUri
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
      <ProfileToken>Profile_1</ProfileToken>
    </GetStreamUri>
  </s:Body>
</s:Envelope>'''

        r = requests.post(endpoint, data=SOAP, timeout=2, auth=auth)
        if r.status_code == 200:
            xml = ET.fromstring(r.text)
            uri = xml.find(".//{*}Uri")
            if uri is not None and uri.text:
                rtsp = uri.text
                # inject credentials if provided
                if username:
                    rtsp = rtsp.replace("rtsp://", f"rtsp://{username}:{password}@")
                return rtsp
    except:
        pass

    # 2. Hikvision fallback (with credentials if provided)
    if username:
        return f"rtsp://{username}:{password}@{ip}:554/Streaming/Channels/101"

    # 3. Dahua fallback (no auth)
    return f"rtsp://{ip}:554/cam/realmonitor?channel=1&subtype=0"

# ---------------------------------------------------------
# CALL EXTERNAL ONVIF SCANNER
# ---------------------------------------------------------
def run_external_onvif_scan(username="", password=""):
    try:
        try:
            open(PROGRESS_FILE, "w").close()
        except:
            pass

        subnet = get_subnet_from_lan_ip()
        print(f"[SCAN] Starting ONVIF scan on subnet {subnet} with user='{username}'")

        result = subprocess.run(
            ["python", "onvif_scan.py", subnet, username, password],
            capture_output=True,
            text=True
        )

        if result.stderr.strip():
            print("[SCAN] Scanner stderr:", result.stderr.strip())

        output = result.stdout.strip()

        try:
            devices = json.loads(output)
            print(f"[SCAN] Parsed {len(devices)} devices from scanner output.")
            return devices
        except Exception as e:
            print("[SCAN] JSON parse error:", e)
            print("[SCAN] Raw output:", output)
            return []

    except Exception as e:
        print("[SCAN] Error running external ONVIF scanner:", e)
        return []

# ---------------------------------------------------------
# DISCOVERY WRAPPER
# ---------------------------------------------------------
def discover_onvif(username="", password=""):
    print(f"[MODULE] Calling external ONVIF scanner (user={username})...")
    devices = run_external_onvif_scan(username, password)
    print(f"[MODULE] External scanner found {len(devices)} devices.")
    return devices

# ---------------------------------------------------------
# FRIGATE CONFIG HELPERS
# ---------------------------------------------------------
def load_frigate_config():
    try:
        with open(FRIGATE_CONFIG_PATH, "r", encoding="utf-8") as f:
            return yaml.safe_load(f) or {}
    except Exception as e:
        print("[FRIGATE] Failed to load config:", e)
        return {}

def save_frigate_config(cfg):
    try:
        backup_file(FRIGATE_CONFIG_PATH)
        with open(FRIGATE_CONFIG_PATH, "w", encoding="utf-8") as f:
            yaml.safe_dump(cfg, f, default_flow_style=False)
        return True
    except Exception as e:
        print("[FRIGATE] Failed to save config:", e)
        return False

def ensure_camera_in_frigate(name, rtsp_url, record=True):
    cfg = load_frigate_config()
    if "cameras" not in cfg or cfg["cameras"] is None:
        cfg["cameras"] = {}

    cam = cfg["cameras"].get(name, {})

    # minimal Frigate camera definition
    cam.setdefault("ffmpeg", {})
    cam["ffmpeg"].setdefault("inputs", [])
    if cam["ffmpeg"]["inputs"]:
        cam["ffmpeg"]["inputs"][0]["path"] = rtsp_url
    else:
        cam["ffmpeg"]["inputs"].append({
            "path": rtsp_url,
            "roles": ["detect", "record"]
        })

    cam.setdefault("detect", {})
    cam["detect"]["enabled"] = True

    cam.setdefault("record", {})
    cam["record"]["enabled"] = bool(record)

    cfg["cameras"][name] = cam

    ok = save_frigate_config(cfg)
    return ok

def remove_camera_from_frigate(name):
    cfg = load_frigate_config()
    cams = cfg.get("cameras", {})
    if name in cams:
        del cams[name]
        cfg["cameras"] = cams
        return save_frigate_config(cfg)
    return False

# ---------------------------------------------------------
# HTTP HANDLER
# ---------------------------------------------------------
class VMSHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def send_json(self, data, code=200):
        payload = json.dumps(data).encode("utf-8")
        try:
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(payload)))
            self.send_header("Connection", "close")
            self.end_headers()
            self.wfile.write(payload)
        except:
            pass

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            data = json.loads(body)
        except:
            data = {}

        # ONVIF DISCOVERY
        if self.path == "/api/onvifDiscover":
            username = data.get("username", "")
            password = data.get("password", "")
            devices = discover_onvif(username, password)
            return self.send_json({"devices": devices})

        # RTSP RESOLUTION
        if self.path == "/api/getRtsp":
            ip = data.get("ip")
            username = data.get("username", "")
            password = data.get("password", "")
            rtsp = get_rtsp_url(ip, username, password)
            return self.send_json({"rtsp": rtsp})

        # ADD CAMERA (from FrigateAPI::addCamera)
        if self.path == "/api/addCamera":
            cam_id = data.get("id")
            rtsp = data.get("rtsp")
            record = bool(data.get("record", True))

            if not (is_valid_camera_name(cam_id) and is_valid_rtsp_url(rtsp)):
                return self.send_json({
                    "status": "error",
                    "message": "Invalid camera id or RTSP URL",
                    "go2rtc": False,
                    "frigate_reload": False
                }, code=400)

            go2_ok = go2rtc_set_stream(cam_id, rtsp)
            fr_cfg_ok = ensure_camera_in_frigate(cam_id, rtsp, record)
            frig_ok = frigate_reload() if fr_cfg_ok else False

            status = "ok" if (go2_ok and fr_cfg_ok and frig_ok) else "error"
            return self.send_json({
                "status": status,
                "go2rtc": go2_ok,
                "frigate_reload": frig_ok
            })

        # EDIT CAMERA (from FrigateAPI::editCamera / applyNewCameraRtsp)
        if self.path == "/api/editCamera":
            cam_id = data.get("id")
            rtsp = data.get("rtsp")

            if not (is_valid_camera_name(cam_id) and is_valid_rtsp_url(rtsp)):
                return self.send_json({
                    "status": "error",
                    "message": "Invalid camera id or RTSP URL",
                    "go2rtc": False,
                    "frigate_reload": False
                }, code=400)

            go2_ok = go2rtc_set_stream(cam_id, rtsp)
            fr_cfg_ok = ensure_camera_in_frigate(cam_id, rtsp, record=True)
            frig_ok = frigate_reload() if fr_cfg_ok else False

            status = "ok" if (go2_ok and fr_cfg_ok and frig_ok) else "error"
            return self.send_json({
                "status": status,
                "go2rtc": go2_ok,
                "frigate_reload": frig_ok
            })

        # REMOVE CAMERA
        if self.path == "/api/removeCamera":
            cam_id = data.get("id")

            if not is_valid_camera_name(cam_id):
                return self.send_json({
                    "status": "error",
                    "message": "Invalid camera id",
                    "go2rtc": False,
                    "frigate_reload": False
                }, code=400)

            go2_ok = go2rtc_remove_stream(cam_id)
            fr_cfg_ok = remove_camera_from_frigate(cam_id)
            frig_ok = frigate_reload() if fr_cfg_ok else False

            status = "ok" if (go2_ok and fr_cfg_ok and frig_ok) else "error"
            return self.send_json({
                "status": status,
                "go2rtc": go2_ok,
                "frigate_reload": frig_ok
            })

        return self.send_json({"status": "ok"})

    def do_GET(self):
        if self.path.startswith("/api/moduleInformation"):
            return self.send_json({
                "reply": {
                    "id": MODULE_ID,
                    "systemId": SYSTEM_ID,
                    "name": SYSTEM_NAME,
                    "version": "0.17.x",
                    "status": "online",
                    "httpPort": HTTP_PORT,
                    "httpsPort": HTTPS_PORT
                }
            })

        if self.path.startswith("/api/onvifProgress"):
            try:
                with open(PROGRESS_FILE, "r", encoding="utf-8") as f:
                    lines = [line.strip() for line in f.readlines() if line.strip()]
            except:
                lines = []
            return self.send_json({"progress": lines})

# ---------------------------------------------------------
# BROADCAST
# ---------------------------------------------------------
def broadcast_discovery():
    while True:
        packet = json.dumps({
            "id": MODULE_ID,
            "systemId": SYSTEM_ID,
            "name": SYSTEM_NAME,
            "port": HTTP_PORT,
            "type": "frigate",
            "address": LAN_IP,
        }).encode("utf-8")

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(packet, (BROADCAST_IP, DISCOVERY_PORT))
        time.sleep(2)

# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------
if __name__ == "__main__":
    threading.Thread(target=broadcast_discovery, daemon=True).start()

    httpd = http.server.HTTPServer((HOST, HTTP_PORT), VMSHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    print(f"[*] HTTP server active on http://0.0.0.0:{HTTP_PORT}")

    try:
        httpsd = http.server.HTTPServer((HOST, HTTPS_PORT), VMSHandler)
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(certfile="combined.pem")
        httpsd.socket = context.wrap_socket(httpsd.socket, server_side=True)
        threading.Thread(target=httpsd.serve_forever, daemon=True).start()
        print(f"[*] HTTPS server active on https://0.0.0.0:{HTTPS_PORT}")
    except Exception as e:
        print(f"[HTTPS] Failed: {e}")

    print("[MAIN] All services started.")
    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("Shutdown.")
