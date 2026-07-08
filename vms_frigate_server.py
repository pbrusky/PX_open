import http.server
import ssl
import json
import socket
import threading
import time
import requests
import subprocess
import yaml
import os
import xml.etree.ElementTree as ET
import uuid

from urllib.parse import urlparse

HOST = "0.0.0.0"
PORT = 7001
DISCOVERY_PORT = 3666
BROADCAST_IP = "255.255.255.255"

FRIGATE_HOST = "127.0.0.1"
FRIGATE_PORT = 5000
FRIGATE_BASE = f"http://{FRIGATE_HOST}:{FRIGATE_PORT}"

GO2RTC_HOST = "127.0.0.1"
GO2RTC_PORT = 1984
GO2RTC_BASE = f"http://{GO2RTC_HOST}:{GO2RTC_PORT}"

CONFIG_PATH = "C:/frigate/config/config.yml"
GO2RTC_CONFIG_PATH = "C:/frigate/config/go2rtc.yaml"

SYSTEM_ID = "{11111111-2222-3333-4444-555555555555}"
MODULE_ID = "{66666666-7777-8888-9999-000000000000}"
SYSTEM_NAME = "Frigate System"


# ----------------------------------------------------------------------
# DOCKER HELPERS
# ----------------------------------------------------------------------
def get_frigate_container_name():
    try:
        result = subprocess.check_output(
            ["docker", "ps", "--format", "{{.Names}} {{.Image}} {{.Ports}}"],
            text=True
        )
        for line in result.splitlines():
            if "frigate" in line.lower() and "5000" in line:
                return line.split()[0]
    except:
        pass
    return None


def restart_frigate():
    name = get_frigate_container_name()
    if name:
        print(f"[*] Restarting container: {name}")
        subprocess.call(["docker", "restart", name])


def restart_go2rtc():
    try:
        result = subprocess.check_output(
            ["docker", "ps", "--format", "{{.Names}} {{.Image}} {{.Ports}}"],
            text=True
        )
        for line in result.splitlines():
            if "go2rtc" in line.lower() and "1984" in line:
                name = line.split()[0]
                print(f"[*] Restarting go2rtc container: {name}")
                subprocess.call(["docker", "restart", name])
                return
    except Exception as e:
        print("[!] restart_go2rtc failed:", e)


def wait_for_frigate(timeout=20):
    print("[*] Waiting for Frigate to become ready...")
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = requests.get(f"{FRIGATE_BASE}/api/config", timeout=2)
            if r.status_code == 200:
                print("[*] Frigate is online")
                return True
        except:
            pass
        time.sleep(1)
    print("[!] Frigate did not become ready in time")
    return False


def wait_for_go2rtc(timeout=15):
    print("[*] Waiting for go2rtc to become ready...")
    start = time.time()
    while time.time() - start < timeout:
        try:
            r = requests.get(f"{GO2RTC_BASE}/api/streams", timeout=2)
            if r.status_code == 200:
                print("[*] go2rtc is online")
                return True
        except:
            pass
        time.sleep(1)
    print("[!] go2rtc did not become ready in time")
    return False


# ----------------------------------------------------------------------
# CONFIG HELPERS
# ----------------------------------------------------------------------
def load_config():
    if not os.path.exists(CONFIG_PATH):
        return {}
    with open(CONFIG_PATH, "r") as f:
        return yaml.safe_load(f) or {}


def save_config(cfg):
    with open(CONFIG_PATH, "w") as f:
        yaml.dump(cfg, f, default_flow_style=False)


def ensure_frigate_defaults(cfg):
    # Preserve existing config, only add missing required blocks
    if "mqtt" not in cfg:
        cfg["mqtt"] = {"enabled": False}

    if "detectors" not in cfg:
        cfg["detectors"] = {
            "cpu1": {
                "type": "cpu"
            }
        }

    if "record" not in cfg:
        cfg["record"] = {
            "enabled": True,
            "retain": {
                "days": 3
            }
        }

    if "birdseye" not in cfg:
        cfg["birdseye"] = {
            "enabled": False
        }

    if "model" not in cfg:
        cfg["model"] = {
            "path": "/config/model_cache/ssd_mobilenet_v3_large.tflite"
        }

    if "objects" not in cfg:
        cfg["objects"] = {
            "track": ["person", "car"]
        }

    if "database" not in cfg:
        cfg["database"] = {
            "path": "/config/frigate.db"
        }

    if "cameras" not in cfg:
        cfg["cameras"] = {}


# ----------------------------------------------------------------------
# go2rtc YAML HELPERS
# ----------------------------------------------------------------------
def load_go2rtc_config():
    if not os.path.exists(GO2RTC_CONFIG_PATH):
        return {}
    with open(GO2RTC_CONFIG_PATH, "r") as f:
        return yaml.safe_load(f) or {}


def save_go2rtc_config(cfg):
    with open(GO2RTC_CONFIG_PATH, "w") as f:
        yaml.dump(cfg, f, default_flow_style=False)


def set_go2rtc_stream(name, rtsp_url):
    cfg = load_go2rtc_config()
    cfg.setdefault("streams", {})
    cfg["streams"][name] = rtsp_url
    save_go2rtc_config(cfg)


def remove_go2rtc_stream_yaml(name):
    cfg = load_go2rtc_config()
    if "streams" in cfg and name in cfg["streams"]:
        del cfg["streams"][name]
        save_go2rtc_config(cfg)


# ----------------------------------------------------------------------
# RTSP TEST
# ----------------------------------------------------------------------
def test_rtsp_stream(rtsp_url):
    try:
        cmd = [
            "ffprobe",
            "-v", "error",
            "-rtsp_transport", "tcp",
            "-timeout", "5000000",
            "-i", rtsp_url
        ]
        subprocess.check_output(cmd, stderr=subprocess.STDOUT)
        return True
    except:
        return False


# ----------------------------------------------------------------------
# ONVIF PROFILE FETCH
# ----------------------------------------------------------------------
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
    except Exception as e:
        print("[!] ONVIF profile request failed:", e)
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


# ----------------------------------------------------------------------
# NX‑STYLE ONVIF DISCOVERY
# ----------------------------------------------------------------------
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

    try:
        sock.sendto(probe, (MULTICAST_ADDR, MULTICAST_PORT))
    except:
        return []

    results = []
    start = time.time()

    while time.time() - start < 1.5:
        try:
            data, addr = sock.recvfrom(65535)
            ip = addr[0]

            info = {"manufacturer": "", "model": ""}
            try:
                resp = requests.post(
                    f"http://{ip}/onvif/device_service",
                    data="""
                    <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
                                xmlns:tds="http://www.onvif.org/ver10/device/wsdl">
                        <s:Body>
                            <tds:GetDeviceInformation/>
                        </s:Body>
                    </s:Envelope>
                    """,
                    headers={"Content-Type": "application/soap+xml"},
                    timeout=2
                )
                if resp.status_code == 200:
                    r = ET.fromstring(resp.text)
                    ns2 = {"tds": "http://www.onvif.org/ver10/device/wsdl"}
                    m = r.find(".//tds:Manufacturer", ns2)
                    md = r.find(".//tds:Model", ns2)
                    info["manufacturer"] = m.text if m is not None else ""
                    info["model"] = md.text if md is not None else ""
            except:
                pass

            profiles = get_onvif_profiles(ip)
            rtsp = ""
            if profiles:
                best = max(profiles, key=score_profile)
                rtsp = best.get("rtsp", "")

            if not rtsp:
                rtsp = f"rtsp://{ip}/Streaming/Channels/101"

            results.append({
                "address": ip,
                "manufacturer": info["manufacturer"],
                "model": info["model"],
                "username": "",
                "password": "",
                "rtsp": rtsp
            })

        except socket.timeout:
            break
        except:
            break

    return results


# ----------------------------------------------------------------------
# HTTP HANDLER
# ----------------------------------------------------------------------
class VMSHandler(http.server.BaseHTTPRequestHandler):

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

        print(f"[*] POST {self.path} -> {data}")

        if self.path == "/api/addCamera":
            cam_id = data.get("id")
            rtsp = data.get("rtsp")
            if not cam_id or not rtsp:
                return self.send_json({"error": "missing fields"}, 400)

            cfg = load_config()
            ensure_frigate_defaults(cfg)
            cfg["cameras"][cam_id] = {
                "ffmpeg": {
                    "inputs": [
                        {"path": rtsp, "roles": ["detect", "record"]}
                    ]
                }
            }
            save_config(cfg)

            set_go2rtc_stream(cam_id, rtsp)

            restart_frigate()
            wait_for_frigate()

            restart_go2rtc()
            wait_for_go2rtc()

            return self.send_json({"status": "ok"})

        if self.path == "/api/editCamera":
            cam_id = data.get("id")
            rtsp = data.get("rtsp")

            cfg = load_config()
            ensure_frigate_defaults(cfg)
            if "cameras" not in cfg or cam_id not in cfg["cameras"]:
                return self.send_json({"error": "not found"}, 404)

            cfg["cameras"][cam_id]["ffmpeg"]["inputs"][0]["path"] = rtsp
            save_config(cfg)

            set_go2rtc_stream(cam_id, rtsp)

            restart_frigate()
            wait_for_frigate()

            restart_go2rtc()
            wait_for_go2rtc()

            return self.send_json({"status": "ok"})

        if self.path == "/api/removeCamera":
            cam_id = data.get("id")
            cfg = load_config()
            ensure_frigate_defaults(cfg)
            if "cameras" in cfg and cam_id in cfg["cameras"]:
                del cfg["cameras"][cam_id]
                save_config(cfg)

                remove_go2rtc_stream_yaml(cam_id)

                restart_frigate()
                wait_for_frigate()

                restart_go2rtc()
                wait_for_go2rtc()

                return self.send_json({"status": "ok"})
            return self.send_json({"error": "not found"}, 404)

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

        if self.path == "/api/onvifAutoProfile":
            address = data.get("address")
            username = data.get("username", "")
            password = data.get("password", "")
            profiles = get_onvif_profiles(address, username, password)
            if not profiles:
                return self.send_json({"ok": False, "error": "no profiles"})
            best = max(profiles, key=score_profile)
            rtsp = best.get("rtsp")
            if rtsp and rtsp.startswith("rtsp://") and "@" not in rtsp:
                rtsp = rtsp.replace("rtsp://", f"rtsp://{username}:{password}@")
            return self.send_json({"ok": True, "rtsp": rtsp})

        if self.path == "/api/onvifDeviceInfo":
            address = data.get("address")
            username = data.get("username", "")
            password = data.get("password", "")

            soap = """
            <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
                        xmlns:tds="http://www.onvif.org/ver10/device/wsdl">
                <s:Body>
                    <tds:GetDeviceInformation/>
                </s:Body>
            </s:Envelope>
            """.strip()

            try:
                resp = requests.post(
                    f"http://{address}/onvif/device_service",
                    data=soap,
                    headers={"Content-Type": "application/soap+xml"},
                    auth=(username, password) if username else None,
                    timeout=3
                )
            except Exception as e:
                return self.send_json({"ok": False, "error": str(e)})

            if resp.status_code != 200:
                return self.send_json({"ok": False, "error": "HTTP " + str(resp.status_code)})

            try:
                root = ET.fromstring(resp.text)
                ns = {"tds": "http://www.onvif.org/ver10/device/wsdl"}

                info = {
                    "manufacturer": root.find(".//tds:Manufacturer", ns).text
                    if root.find(".//tds:Manufacturer", ns) is not None else "",
                    "model": root.find(".//tds:Model", ns).text
                    if root.find(".//tds:Model", ns) is not None else "",
                    "firmware": root.find(".//tds:FirmwareVersion", ns).text
                    if root.find(".//tds:FirmwareVersion", ns) is not None else ""
                }

                return self.send_json({"ok": True, "info": info})

            except Exception as e:
                return self.send_json({"ok": False, "error": str(e)})

        return self.send_json({"error": "unknown endpoint"}, 404)

    def do_GET(self):
        print(f"[*] GET {self.path}")

        if self.path == "/api/moduleInformation":
            return self.send_json({
                "reply": {
                    "id": MODULE_ID,
                    "systemId": SYSTEM_ID,
                    "name": SYSTEM_NAME,
                    "version": "0.17.x",
                    "status": "online"
                }
            })

        if self.path == "/api/discoverOnvif" or self.path == "/api/onvifDiscover":
            devices = discover_onvif()
            return self.send_json({"devices": devices})

        return self.send_json({"error": "not found"}, 404)


# ----------------------------------------------------------------------
# BROADCAST DISCOVERY
# ----------------------------------------------------------------------
def broadcast_discovery():
    while True:
        container = get_frigate_container_name()
        packet = json.dumps({
            "id": MODULE_ID,
            "systemId": SYSTEM_ID,
            "name": SYSTEM_NAME,
            "port": PORT,
            "type": "frigate",
            "container": container or "unknown"
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

    context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    context.load_cert_chain(certfile="combined.pem")

    httpd = http.server.HTTPServer((HOST, PORT), VMSHandler)
    httpd.socket = context.wrap_socket(httpd.socket, server_side=True)

    print(f"[*] Frigate discovery proxy active on https://0.0.0.0:{PORT}")
    httpd.serve_forever()
