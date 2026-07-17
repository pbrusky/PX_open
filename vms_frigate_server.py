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

# ---------------------------------------------------------
# IP DETECTION
# ---------------------------------------------------------
SERVER_IP = os.environ.get("FRIGATE_SERVER_IP", "127.0.0.1")

def get_local_ip():
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))   # does NOT send traffic
        ip = s.getsockname()[0]
        s.close()
        return ip
    except:
        return "127.0.0.1"

LAN_IP = get_local_ip()

# ---------------------------------------------------------
# CONFIG
# ---------------------------------------------------------
HTTP_PORT = 8001
HTTPS_PORT = 8002
HOST = "0.0.0.0"
DISCOVERY_PORT = 3666
BROADCAST_IP = "255.255.255.255"

FRIGATE_HOST = LAN_IP
FRIGATE_PORT = 5000
FRIGATE_BASE = f"http://{FRIGATE_HOST}:{FRIGATE_PORT}"

GO2RTC_HOST = LAN_IP
GO2RTC_PORT = 1984
GO2RTC_BASE = f"http://{GO2RTC_HOST}:{GO2RTC_PORT}"

GO2RTC_CONFIG_PATH = r"C:\frigate\go2rtc.yaml"
FRIGATE_CONFIG_PATH = r"C:\frigate\config\config.yml"

SYSTEM_ID = "{11111111-2222-3333-4444-555555555555}"
MODULE_ID = "{66666666-7777-8888-9999-000000000000}"
SYSTEM_NAME = "Frigate System"

PROGRESS_FILE = r"C:\PX\onvif_progress.log"

# ---------------------------------------------------------
# ONVIF SCANNING
# ---------------------------------------------------------
def get_subnet_from_lan_ip():
    try:
        parts = LAN_IP.split(".")
        if len(parts) == 4:
            return ".".join(parts[:3]) + "."
    except:
        pass
    return "192.168.1."

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

def discover_onvif(username="", password=""):
    print(f"[MODULE] Calling external ONVIF scanner (user={username})...")
    devices = run_external_onvif_scan(username, password)
    print(f"[MODULE] External scanner found {len(devices)} devices.")
    return devices

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
        # import here to avoid circular import at module load time
        from camera_manager import (
            add_camera,
            edit_camera,
            remove_camera,
            get_rtsp_url,
        )

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

        # ADD CAMERA
        if self.path == "/api/addCamera":
            cam_id = data.get("id")
            rtsp = data.get("rtsp")
            record = bool(data.get("record", True))
            return self.send_json(add_camera(cam_id, rtsp, record))

        # EDIT CAMERA
        if self.path == "/api/editCamera":
            cam_id = data.get("id")
            rtsp = data.get("rtsp")
            return self.send_json(edit_camera(cam_id, rtsp))

        # REMOVE CAMERA
        if self.path == "/api/removeCamera":
            cam_id = data.get("id")
            return self.send_json(remove_camera(cam_id))

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
