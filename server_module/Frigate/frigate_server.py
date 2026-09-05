import http.server
import json
import socket
import threading
import time
import subprocess
import sys
from pathlib import Path

from config import (
    LAN_IP, HTTP_PORT, HTTPS_PORT, BROADCAST_IP,
    PROGRESS_FILE, MODULE_ID, SYSTEM_ID, SYSTEM_NAME,
    FRIGATE_CONFIG_PATH, FRIGATE_MEDIA_PATH, FRIGATE_CACHE_PATH,
    GO2RTC_CONFIG_PATH,
    CONFIG_FILE,
)

from https_server import start_https_server

from add_camera import add_camera, restart_frigate, restart_go2rtc
from edit_camera import edit_camera
from remove_camera import remove_camera
from config_file import get_frigate_config, save_frigate_config, get_go2rtc_config, save_go2rtc_config

HOST = "0.0.0.0"
DISCOVERY_PORT = 3666


def get_onvif_scan_prefix() -> str:
    """
    Subnet prefix for onvif_scan.py, e.g. "10.36.24."

    Priority:
      1) config.json key "scan_subnet" (e.g. "10.36.24" or "10.36.24.")
      2) Derived from LAN_IP from config (auto-detected or lan_ip override)
    """
    try:
        if CONFIG_FILE.exists():
            with open(CONFIG_FILE, "r", encoding="utf-8") as f:
                cfg = json.load(f) or {}
            raw = str(cfg.get("scan_subnet") or "").strip()
            if raw:
                raw = raw.rstrip(".")
                parts = raw.split(".")
                if len(parts) >= 3:
                    return ".".join(parts[:3]) + "."
                return raw + "."
    except Exception as e:
        print(f"[ONVIF] Could not read scan_subnet from config: {e}")

    try:
        parts = str(LAN_IP).strip().split(".")
        if len(parts) == 4 and all(p.isdigit() for p in parts):
            return ".".join(parts[:3]) + "."
    except Exception:
        pass

    print(f"[ONVIF] WARN: could not derive subnet from LAN_IP={LAN_IP!r}, using 192.168.1.")
    return "192.168.1."


def broadcast_discovery():
    packet = json.dumps({
        "id": MODULE_ID,
        "systemId": SYSTEM_ID,
        "name": SYSTEM_NAME,
        "port": HTTP_PORT,
        "type": "frigate",
        "address": LAN_IP,
    }).encode("utf-8")

    print(f"[Discovery] Broadcasting as {SYSTEM_NAME} @ {LAN_IP}:{HTTP_PORT}")
    print(f"[Discovery] Primary broadcast target: {BROADCAST_IP}")

    while True:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

            targets = set()

            if BROADCAST_IP:
                targets.add(BROADCAST_IP)

            try:
                base = LAN_IP.rsplit(".", 1)[0]
                targets.update([
                    f"{base}.255",
                    f"{base}.1",
                    f"{base}.254",
                    "255.255.255.255",
                ])
            except Exception:
                targets.add("255.255.255.255")

            for target in targets:
                try:
                    sock.sendto(packet, (target, DISCOVERY_PORT))
                except Exception:
                    continue

            sock.close()
        except Exception as e:
            print(f"[Discovery] Broadcast error: {e}")

        time.sleep(2)


class VMSHandler(http.server.BaseHTTPRequestHandler):
    def log_message(self, format, *args):
        return

    def send_json(self, data, code=200):
        payload = json.dumps(data, ensure_ascii=False).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Content-Length", str(len(payload)))
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        try:
            length = int(self.headers.get("Content-Length", 0))
            body = self.rfile.read(length) if length > 0 else b""
            data = json.loads(body) if body else {}

            if self.path == "/api/onvifDiscover":
                username = data.get("username", "")
                password = data.get("password", "")

                req_subnet = str(data.get("subnet") or data.get("scan_subnet") or "").strip()
                if req_subnet:
                    prefix = req_subnet.rstrip(".") + "."
                else:
                    prefix = get_onvif_scan_prefix()

                print(f"[ONVIF] Discovery requested user='{username}' subnet={prefix}")

                try:
                    script_path = Path(__file__).with_name("onvif_scan.py")
                    result = subprocess.run(
                        [sys.executable, str(script_path), prefix, username, password],
                        capture_output=True,
                        text=True,
                        timeout=40,
                        stdin=subprocess.DEVNULL,
                        cwd=str(Path(__file__).resolve().parent),
                    )

                    if result.stderr.strip():
                        print("[ONVIF Scanner] Stderr:", result.stderr.strip())

                    devices = json.loads(result.stdout.strip() or "[]")
                    print(f"[ONVIF] Found {len(devices)} device(s)")
                    return self.send_json({"devices": devices})

                except subprocess.TimeoutExpired:
                    print("[ONVIF] Scanner timed out")
                    return self.send_json({"devices": []})
                except json.JSONDecodeError:
                    print("[ONVIF] Failed to parse scanner output")
                    return self.send_json({"devices": []})
                except Exception as e:
                    print(f"[ONVIF] Error: {e}")
                    return self.send_json({"devices": []})

            if self.path == "/api/getRtsp":
                ip = data.get("ip")
                username = data.get("username", "")
                password = data.get("password", "")

                if not ip:
                    return self.send_json({"rtsp": None})

                try:
                    from requests.auth import HTTPDigestAuth
                    import requests
                    import xml.etree.ElementTree as ET

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
                                        rtsp = rtsp.replace(
                                            "rtsp://",
                                            f"rtsp://{username}:{password}@",
                                        )
                                    return self.send_json({"rtsp": rtsp})

                        except Exception:
                            continue

                    print(f"[RTSP] ONVIF failed for {ip}, using fallback")

                    if username:
                        fallback = (
                            f"rtsp://{username}:{password}@{ip}:554/"
                            f"Streaming/Channels/101"
                        )
                    else:
                        fallback = (
                            f"rtsp://{ip}:554/cam/realmonitor?channel=1&subtype=0"
                        )

                    return self.send_json({"rtsp": fallback})

                except Exception as e:
                    print("[getRtsp ERROR]", e)
                    return self.send_json({"rtsp": None})

            if self.path == "/api/addCamera":
                return self.send_json(add_camera(
                    data.get("id"),
                    data.get("rtsp"),
                    bool(data.get("record", True)),
                    data.get("rtsp_sub"),
                ))

            if self.path == "/api/editCamera":
                return self.send_json(edit_camera(
                    data.get("id"),
                    data.get("rtsp"),
                    data.get("rtsp_sub"),
                    bool(data.get("record", True)),
                ))

            if self.path == "/api/removeCamera":
                return self.send_json(remove_camera(data.get("id")))

            if self.path == "/api/saveFrigateConfig":
                return self.send_json(save_frigate_config(
                    data.get("content"),
                    restart=bool(data.get("restart", True)),
                ))

            if self.path == "/api/saveGo2rtcConfig":
                return self.send_json(save_go2rtc_config(
                    data.get("content"),
                    restart=bool(data.get("restart", True)),
                ))

            if self.path == "/api/restartFrigate":
                return self.send_json({"success": restart_frigate()})

            if self.path == "/api/restartGo2rtc":
                return self.send_json({"success": restart_go2rtc()})

            return self.send_json({"status": "ok"})

        except Exception as e:
            import traceback
            print(f"[HTTP ERROR] {self.path}: {e}")
            print(traceback.format_exc())
            return self.send_json({"status": "error", "message": str(e)}, code=500)

    def do_GET(self):
        if self.path.startswith("/api/moduleInformation"):
            return self.send_json({
                "reply": {
                    "id": MODULE_ID,
                    "systemId": SYSTEM_ID,
                    "name": SYSTEM_NAME,
                    "version": "1.0",
                    "status": "online",
                    "httpPort": HTTP_PORT,
                    "httpsPort": HTTPS_PORT,
                }
            })

        if self.path.startswith("/api/getFrigateConfig"):
            return self.send_json(get_frigate_config())

        if self.path.startswith("/api/getGo2rtcConfig"):
            return self.send_json(get_go2rtc_config())

        if self.path.startswith("/api/onvifProgress"):
            try:
                with open(PROGRESS_FILE, "r", encoding="utf-8") as f:
                    lines = [line.strip() for line in f.readlines() if line.strip()]
            except Exception:
                lines = []
            return self.send_json({"progress": lines})

        return self.send_json({"status": "ok"})


if __name__ == "__main__":
    print(f"[*] Starting Frigate Integration Module on {LAN_IP}")
    print(f"[*] ONVIF scan subnet prefix: {get_onvif_scan_prefix()}")

    threading.Thread(target=broadcast_discovery, daemon=True).start()

    httpd = http.server.HTTPServer((HOST, HTTP_PORT), VMSHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    print(f"[*] HTTP server running → http://{LAN_IP}:{HTTP_PORT}")

    start_https_server(HOST, HTTPS_PORT, VMSHandler)

    print("[MAIN] All services started. Press Ctrl+C to stop.")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutdown.")