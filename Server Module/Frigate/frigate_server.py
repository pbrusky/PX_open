import http.server
import ssl
import json
import socket
import threading
import time
import subprocess
from pathlib import Path

# Import config
from config import (
    LAN_IP, HTTP_PORT, HTTPS_PORT, BROADCAST_IP,
    PROGRESS_FILE, MODULE_ID, SYSTEM_ID, SYSTEM_NAME
)

# Import HTTPS module
from https_server import start_https_server

HOST = "0.0.0.0"
DISCOVERY_PORT = 3666

# ---------------------------------------------------------
# BROADCAST DISCOVERY
# ---------------------------------------------------------
def broadcast_discovery():
    packet = json.dumps({
        "id": MODULE_ID,
        "systemId": SYSTEM_ID,
        "name": SYSTEM_NAME,
        "port": HTTP_PORT,
        "type": "frigate",
        "address": LAN_IP,
    }).encode("utf-8")

    while True:
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)

            targets = []
            if BROADCAST_IP:
                targets.append(BROADCAST_IP)
            else:
                base = LAN_IP.rsplit(".", 1)[0]
                targets.extend([f"{base}.255", f"{base}.1", f"{base}.254"])

            for target in targets:
                try:
                    sock.sendto(packet, (target, DISCOVERY_PORT))
                except:
                    continue
            sock.close()
        except Exception:
            pass

        time.sleep(2)


# ---------------------------------------------------------
# HTTP HANDLER
# ---------------------------------------------------------
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
            body = self.rfile.read(length) if length > 0 else b''
            data = json.loads(body) if body else {}

            # ====================== ONVIF DISCOVERY ======================
            if self.path == "/api/onvifDiscover":
                username = data.get("username", "")
                password = data.get("password", "")
                
                print(f"[ONVIF] Discovery requested with user: '{username}'")
                
                try:
                    result = subprocess.run(
                        ["python", "onvif_scan.py", "10.36.24.", username, password],
                        capture_output=True,
                        text=True,
                        timeout=40
                    )

                    if result.stderr.strip():
                        print("[ONVIF Scanner] Stderr:", result.stderr.strip())

                    devices = json.loads(result.stdout.strip())
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

            # ====================== CAMERA & RTSP ENDPOINTS ======================
            if self.path == "/api/getRtsp":
                from camera_manager import get_rtsp_url
                rtsp = get_rtsp_url(
                    data.get("ip"),
                    data.get("username", ""),
                    data.get("password", "")
                )
                return self.send_json({"rtsp": rtsp})

            if self.path == "/api/addCamera":
                from camera_manager import add_camera
                return self.send_json(add_camera(
                    data.get("id"),
                    data.get("rtsp"),
                    bool(data.get("record", True))
                ))

            if self.path == "/api/editCamera":
                from camera_manager import edit_camera
                return self.send_json(edit_camera(data.get("id"), data.get("rtsp")))

            if self.path == "/api/removeCamera":
                from camera_manager import remove_camera
                return self.send_json(remove_camera(data.get("id")))

            # ====================== RESTART ENDPOINTS ======================
            if self.path == "/api/restartFrigate":
                from camera_manager import restart_frigate
                return self.send_json({"success": restart_frigate()})

            if self.path == "/api/restartGo2rtc":
                from camera_manager import restart_go2rtc
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

        return self.send_json({"status": "ok"})


# ---------------------------------------------------------
# MAIN
# ---------------------------------------------------------
if __name__ == "__main__":
    print(f"[*] Starting Frigate Integration Module on {LAN_IP}")

    threading.Thread(target=broadcast_discovery, daemon=True).start()

    # HTTP Server
    httpd = http.server.HTTPServer((HOST, HTTP_PORT), VMSHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    print(f"[*] HTTP server running → http://{LAN_IP}:{HTTP_PORT}")

    # HTTPS Server (now in separate file)
    start_https_server(HOST, HTTPS_PORT, VMSHandler)

    print("[MAIN] All services started. Press Ctrl+C to stop.")

    try:
        while True:
            time.sleep(1)
    except KeyboardInterrupt:
        print("\nShutdown.")
