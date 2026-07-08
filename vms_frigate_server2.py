import http.server
import ssl
import json
import socket
import threading
import time
import requests
import subprocess
import xml.etree.ElementTree as ET
import uuid
import os
import shutil

try:
    import yaml
    YAML_AVAILABLE = True
except Exception:
    YAML_AVAILABLE = False

# ----------------------------------------------------------------------
# CONFIG
# ----------------------------------------------------------------------
HTTP_PORT = 7001
HTTPS_PORT = 7002
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


# ----------------------------------------------------------------------
# HELPERS
# ----------------------------------------------------------------------
def frigate_reload():
    try:
        url = f"{FRIGATE_BASE}/api/reload"
        r = requests.post(url, timeout=2)
        print(f"[MODULE] frigate_reload -> POST {url} status={r.status_code} text={r.text}")
        if r.status_code == 200:
            return True

        # Some Frigate deployments expose reload as GET or a different endpoint.
        if r.status_code == 405:
            try:
                r2 = requests.get(url, timeout=2)
                print(f"[MODULE] frigate_reload -> GET {url} status={r2.status_code} text={r2.text}")
                return r2.status_code == 200
            except Exception:
                import traceback
                print("[MODULE] frigate_reload GET exception:\n" + traceback.format_exc())

        return False
    except:
        import traceback
        print("[MODULE] frigate_reload exception:\n" + traceback.format_exc())
        return False

def go2rtc_set_stream(name, rtsp_url):
    if not is_valid_camera_name(name) or not is_valid_rtsp_url(rtsp_url):
        print(f"[MODULE] go2rtc_set_stream invalid name or rtsp_url: {name!r}, {rtsp_url!r}")
        return False

    try:
        url = f"{GO2RTC_BASE}/api/streams"
        payload1 = {name: rtsp_url}
        print(f"[MODULE] go2rtc_set_stream -> POST {url} payload={payload1}")
        r = requests.post(url, json=payload1, timeout=2)
        print(f"[MODULE] go2rtc_set_stream response: status={r.status_code} text={r.text}")

        if r.status_code == 200:
            return True

        # Retry with alternate payload format many go2rtc variants accept
        payload2 = {"streams": {name: rtsp_url}}
        try:
            print(f"[MODULE] go2rtc_set_stream -> RETRY POST {url} payload={payload2}")
            r2 = requests.post(url, json=payload2, timeout=2)
            print(f"[MODULE] go2rtc_set_stream retry response: status={r2.status_code} text={r2.text}")
            return r2.status_code == 200
        except Exception:
            import traceback
            print("[MODULE] go2rtc_set_stream retry exception:\n" + traceback.format_exc())

        return False
    except:
        import traceback
        print("[MODULE] go2rtc_set_stream exception:\n" + traceback.format_exc())
        return False

def go2rtc_remove_stream(name):
    if not is_valid_camera_name(name):
        print(f"[MODULE] go2rtc_remove_stream invalid camera name: {name!r}")
        return False

    try:
        url = f"{GO2RTC_BASE}/api/streams/{name}"
        print(f"[MODULE] go2rtc_remove_stream -> DELETE {url}")
        r = requests.delete(url, timeout=2)
        print(f"[MODULE] go2rtc_remove_stream response: status={r.status_code} text={r.text}")
        return r.status_code == 200
    except:
        import traceback
        print("[MODULE] go2rtc_remove_stream exception:\n" + traceback.format_exc())
        return False


def is_valid_camera_name(name):
    return isinstance(name, str) and name.strip() != ""


def is_valid_rtsp_url(rtsp_url):
    return isinstance(rtsp_url, str) and rtsp_url.strip() != ""


def backup_file(path):
    try:
        if os.path.exists(path):
            shutil.copy(path, path + ".backup")
            print(f"[MODULE] backup created: {path}.backup")
            return True
    except Exception:
        import traceback
        print("[MODULE] backup_file exception:\n" + traceback.format_exc())
    return False


def add_camera_to_go2rtc_config(name, rtsp_url):
    if not YAML_AVAILABLE:
        print("[MODULE] PyYAML not available; cannot edit go2rtc config")
        return False

    path = GO2RTC_CONFIG_PATH
    try:
        if not os.path.exists(path):
            data = {"streams": {name: rtsp_url}}
        else:
            with open(path, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f) or {}
            if 'streams' not in data:
                data['streams'] = {}
            data['streams'][name] = rtsp_url

        backup_file(path)
        with open(path, 'w', encoding='utf-8') as f:
            yaml.safe_dump(data, f)
        print(f"[MODULE] go2rtc config updated: {path} -> added {name}")
        return True
    except Exception:
        import traceback
        print("[MODULE] add_camera_to_go2rtc_config exception:\n" + traceback.format_exc())
        return False


def remove_camera_from_go2rtc_config(name):
    if not YAML_AVAILABLE:
        print("[MODULE] PyYAML not available; cannot edit go2rtc config")
        return False

    path = GO2RTC_CONFIG_PATH
    try:
        if not os.path.exists(path):
            return False
        with open(path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f) or {}
        if 'streams' in data and name in data['streams']:
            del data['streams'][name]
            backup_file(path)
            with open(path, 'w', encoding='utf-8') as f:
                yaml.safe_dump(data, f)
            print(f"[MODULE] go2rtc config updated: {path} -> removed {name}")
            return True
        return False
    except Exception:
        import traceback
        print("[MODULE] remove_camera_from_go2rtc_config exception:\n" + traceback.format_exc())
        return False


def add_camera_to_frigate_config(name, rtsp_url=None):
    if not YAML_AVAILABLE:
        print("[MODULE] PyYAML not available; cannot edit Frigate config")
        return False

    path = FRIGATE_CONFIG_PATH
    try:
        if not os.path.exists(path):
            data = {}
        else:
            with open(path, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f) or {}

        if 'cameras' not in data:
            data['cameras'] = {}

        # Prefer original RTSP if provided, otherwise use go2rtc local stream URL
        if rtsp_url and isinstance(rtsp_url, str) and rtsp_url.strip() != "":
            stream_url = rtsp_url
        else:
            stream_url = f"rtsp://{GO2RTC_HOST}:{GO2RTC_PORT}/{name}"

        # Minimal camera entry using provided RTSP
        data['cameras'][name] = {
            'ffmpeg': {
                'inputs': [
                    {'path': stream_url, 'roles': ['detect', 'record']}
                ]
            }
        }

        backup_file(path)
        with open(path, 'w', encoding='utf-8') as f:
            yaml.safe_dump(data, f)
        print(f"[MODULE] Frigate config updated: {path} -> added camera {name}")
        return True
    except Exception:
        import traceback
        print("[MODULE] add_camera_to_frigate_config exception:\n" + traceback.format_exc())
        return False


def remove_camera_from_frigate_config(name):
    if not YAML_AVAILABLE:
        print("[MODULE] PyYAML not available; cannot edit Frigate config")
        return False

    path = FRIGATE_CONFIG_PATH
    try:
        if not os.path.exists(path):
            return False
        with open(path, 'r', encoding='utf-8') as f:
            data = yaml.safe_load(f) or {}
        if 'cameras' in data and name in data['cameras']:
            del data['cameras'][name]
            backup_file(path)
            with open(path, 'w', encoding='utf-8') as f:
                yaml.safe_dump(data, f)
            print(f"[MODULE] Frigate config updated: {path} -> removed camera {name}")
            return True
        return False
    except Exception:
        import traceback
        print("[MODULE] remove_camera_from_frigate_config exception:\n" + traceback.format_exc())
        return False

def test_rtsp_stream(rtsp_url):
    try:
        cmd = [
            "ffprobe",
            "-v", "error",
            "-rtsp_transport", "tcp",
            "-timeout", "5000000",
            "-i", rtsp_url
        ]
        print(f"[MODULE] test_rtsp_stream -> running ffprobe for {rtsp_url}")
        out = subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        print(f"[MODULE] test_rtsp_stream output: {out[:200]}")
        return True
    except:
        import traceback
        print("[MODULE] test_rtsp_stream exception:\n" + traceback.format_exc())
        return False

def get_onvif_profiles(address, username="", password=""):
    service_url = f"http://{address}/onvif/device_service"
    soap = """
    <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
                xmlns:trt="http://www.onvif.org/ver10/media/wsdl">
        <s:Body>
            <trt:GetProfiles/>
        </s:Body>
    </s:Envelope>
    """.strip()

    try:
        resp = requests.post(
            service_url,
            data=soap,
            headers={"Content-Type": "application/soap+xml"},
            auth=(username, password) if username else None,
            timeout=3
        )
    except:
        return []

    if resp.status_code != 200:
        return []

    try:
        root = ET.fromstring(resp.text)
    except:
        return []

    ns = {
        "trt": "http://www.onvif.org/ver10/media/wsdl",
        "tt": "http://www.onvif.org/ver10/schema"
    }

    profiles = []
    for profile in root.findall(".//trt:Profiles", ns):
        uri = profile.find(".//tt:Uri", ns)
        rtsp = uri.text if uri is not None else ""
        profiles.append({"rtsp": rtsp})

    return profiles


def score_profile(p):
    rtsp = p.get("rtsp", "")
    score = 0
    if "h264" in rtsp.lower(): score += 10
    if "h265" in rtsp.lower(): score += 12
    if "main" in rtsp.lower(): score += 5
    if "sub" in rtsp.lower(): score -= 5
    if "1080" in rtsp: score += 5
    if "4k" in rtsp.lower(): score += 10
    return score


def discover_onvif():
    MULTICAST_ADDR = "239.255.255.250"
    MULTICAST_PORT = 3702

    message_id = uuid.uuid4()
    probe = f"""
    <e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
                xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
                xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">
        <e:Header>
            <w:MessageID>uuid:{message_id}</w:MessageID>
            <w:To>urn:schemas-xmlsoap-org:ws:2005:04/discovery</w:To>
            <w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
        </e:Header>
        <e:Body>
            <d:Probe>
                <d:Types>dn:NetworkVideoTransmitter</d:Types>
            </d:Probe>
        </e:Body>
    </e:Envelope>
    """.strip().encode("utf-8")

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 2)
    sock.settimeout(1.5)

    results = []
    start = time.time()

    try:
        sock.sendto(probe, (MULTICAST_ADDR, MULTICAST_PORT))
    except:
        return []

    while time.time() - start < 1.5:
        try:
            data, addr = sock.recvfrom(65535)
            ip = addr[0]

            profiles = get_onvif_profiles(ip)
            rtsp = ""
            if profiles:
                best = max(profiles, key=score_profile)
                rtsp = best.get("rtsp", "")

            if not rtsp:
                rtsp = f"rtsp://{ip}/Streaming/Channels/101"

            results.append({
                "address": ip,
                "manufacturer": "",
                "model": "",
                "username": "",
                "password": "",
                "rtsp": rtsp
            })

        except:
            break

    return results


# ----------------------------------------------------------------------
# HTTP HANDLER
# ----------------------------------------------------------------------
class VMSHandler(http.server.BaseHTTPRequestHandler):

    def log_message(self, format, *args):
        return

    def send_json(self, data, code=200):
        payload = json.dumps(data).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(payload)))
        self.send_header("Connection", "close")
        self.end_headers()
        self.wfile.write(payload)

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            data = json.loads(body)
        except:
            data = {}

        if not self.path.startswith("/api/moduleInformation"):
            print(f"[CLIENT POST] {self.path} -> {data}")

        if self.path == "/api/addCamera":
            cam_id = data.get("id")
            rtsp = data.get("rtsp")
            if not is_valid_camera_name(cam_id) or not is_valid_rtsp_url(rtsp):
                return self.send_json({"status": "error", "error": "invalid addCamera payload"}, 400)

            # Try API first, fall back to editing go2rtc config file
            ok_api = go2rtc_set_stream(cam_id, rtsp)
            ok_config = False
            if not ok_api:
                ok_config = add_camera_to_go2rtc_config(cam_id, rtsp)

            # Ensure Frigate config has the camera entry (pointing to go2rtc stream)
            ok_frigate_config = add_camera_to_frigate_config(cam_id, rtsp)

            # Reload Frigate
            ok_reload = frigate_reload()

            return self.send_json({
                "status": "ok",
                "go2rtc_api": ok_api,
                "go2rtc_config": ok_config,
                "frigate_config": ok_frigate_config,
                "frigate_reload": ok_reload
            })

        if self.path == "/api/editCamera":
            cam_id = data.get("id")
            rtsp = data.get("rtsp")
            if not is_valid_camera_name(cam_id) or not is_valid_rtsp_url(rtsp):
                return self.send_json({"status": "error", "error": "invalid editCamera payload"}, 400)

            ok_api = go2rtc_set_stream(cam_id, rtsp)
            ok_config = False
            if not ok_api:
                ok_config = add_camera_to_go2rtc_config(cam_id, rtsp)

            ok_frigate_config = add_camera_to_frigate_config(cam_id, rtsp)
            ok_reload = frigate_reload()

            return self.send_json({
                "status": "ok",
                "go2rtc_api": ok_api,
                "go2rtc_config": ok_config,
                "frigate_config": ok_frigate_config,
                "frigate_reload": ok_reload
            })

        if self.path == "/api/removeCamera":
            cam_id = data.get("id")
            if not is_valid_camera_name(cam_id):
                return self.send_json({"status": "error", "error": "invalid removeCamera payload"}, 400)

            ok_api = go2rtc_remove_stream(cam_id)
            ok_config = False
            if not ok_api:
                ok_config = remove_camera_from_go2rtc_config(cam_id)

            ok_frigate_config = remove_camera_from_frigate_config(cam_id)
            ok_reload = frigate_reload()

            return self.send_json({
                "status": "ok",
                "go2rtc_api": ok_api,
                "go2rtc_config": ok_config,
                "frigate_config": ok_frigate_config,
                "frigate_reload": ok_reload
            })

        if self.path == "/api/testRtsp":
            rtsp = data.get("rtsp")
            ok = test_rtsp_stream(rtsp)
            return self.send_json({"ok": ok})

        if self.path == "/api/onvifDiscover":
            devices = discover_onvif()
            return self.send_json({"devices": devices})

        if self.path == "/api/onvifProfiles":
            address = data.get("address")
            username = data.get("username", "")
            password = data.get("password", "")
            profiles = get_onvif_profiles(address, username, password)
            return self.send_json({"profiles": profiles})

        return self.send_json({"error": "unknown endpoint"}, 404)

    def do_GET(self):

        if not self.path.startswith("/api/moduleInformation"):
            print(f"[CLIENT GET] {self.path}")

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

        if self.path == "/api/onvifDiscover":
            devices = discover_onvif()
            return self.send_json({"devices": devices})

        return self.send_json({"error": "not found"}, 404)


# ----------------------------------------------------------------------
# BROADCAST DISCOVERY (MATCHES YOUR EXISTING CLIENT CODE)
# ----------------------------------------------------------------------
def broadcast_discovery():
    while True:
        packet = json.dumps({
            "id": MODULE_ID,
            "systemId": SYSTEM_ID,
            "name": SYSTEM_NAME,
            "port": HTTP_PORT,     # <-- THIS is what your client reads
            "type": "frigate"
        }).encode("utf-8")

        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.setsockopt(socket.SOL_SOCKET, socket.SO_BROADCAST, 1)
        sock.sendto(packet, (BROADCAST_IP, DISCOVERY_PORT))
        time.sleep(2)


# ----------------------------------------------------------------------
# MAIN
# ----------------------------------------------------------------------
if __name__ == "__main__":
    threading.Thread(target=broadcast_discovery, daemon=True).start()

    httpd = http.server.HTTPServer((HOST, HTTP_PORT), VMSHandler)
    threading.Thread(target=httpd.serve_forever, daemon=True).start()
    print(f"[*] HTTP server active on http://0.0.0.0:{HTTP_PORT}")

    httpsd = http.server.HTTPServer((HOST, HTTPS_PORT), VMSHandler)
    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile="combined.pem")
    httpsd.socket = context.wrap_socket(httpsd.socket, server_side=True)
    threading.Thread(target=httpsd.serve_forever, daemon=True).start()
    print(f"[*] HTTPS server active on https://0.0.0.0:{HTTPS_PORT}")

    while True:
        time.sleep(1)
