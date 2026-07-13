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
import concurrent.futures
import ipaddress
import psutil
import yaml

# ----------------------------------------------------------------------
# CONFIG
# ----------------------------------------------------------------------
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

COMMON_PORTS = [80, 554, 8080, 8000, 8899]   # Reordered for speed

# ----------------------------------------------------------------------
# WS-DISCOVERY (Primary & Fast Method)
# ----------------------------------------------------------------------
WSA_NS = "http://schemas.xmlsoap.org/ws/2004/08/addressing"
DISCOVERY_NS = "http://schemas.xmlsoap.org/ws/2005/04/discovery"

PROBE_MESSAGE = f"""<?xml version="1.0" encoding="utf-8"?>
<e:Envelope xmlns:e="http://www.w3.org/2003/05/soap-envelope"
            xmlns:w="http://schemas.xmlsoap.org/ws/2004/08/addressing"
            xmlns:d="http://schemas.xmlsoap.org/ws/2005/04/discovery">
  <e:Header>
    <w:MessageID>uuid:{uuid.uuid4()}</w:MessageID>
    <w:To>urn:schemas-xmlsoap-org:ws:2005:04:discovery</w:To>
    <w:Action>http://schemas.xmlsoap.org/ws/2005/04/discovery/Probe</w:Action>
  </e:Header>
  <e:Body>
    <d:Probe>
      <d:Types>dn:NetworkVideoTransmitter</d:Types>
    </d:Probe>
  </e:Body>
</e:Envelope>
"""

# ----------------------------------------------------------------------
# WS-DISCOVERY
# ----------------------------------------------------------------------
def ws_discover(timeout=4):
    print("[DISCOVERY] Starting WS-Discovery (multicast)...")
    MULTICAST_ADDR = "239.255.255.250"
    MULTICAST_PORT = 3702

    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM, socket.IPPROTO_UDP)
    sock.setsockopt(socket.IPPROTO_IP, socket.IP_MULTICAST_TTL, 4)
    sock.settimeout(timeout)

    devices = []

    try:
        mreq = socket.inet_aton(MULTICAST_ADDR) + socket.inet_aton("0.0.0.0")
        sock.setsockopt(socket.IPPROTO_IP, socket.IP_ADD_MEMBERSHIP, mreq)
    except Exception as e:
        print("[DISCOVERY] IGMP join failed:", e)

    sock.sendto(PROBE_MESSAGE.encode("utf-8"), (MULTICAST_ADDR, MULTICAST_PORT))

    start = time.time()
    while time.time() - start < timeout:
        try:
            data, addr = sock.recvfrom(65535)
            ip = addr[0]
            root = ET.fromstring(data)

            manufacturer = model = ""
            for elem in root.iter():
                tag = elem.tag.lower()
                if "manufacturer" in tag and elem.text:
                    manufacturer = elem.text
                if "model" in tag and elem.text:
                    model = elem.text

            devices.append({
                "address": ip,
                "manufacturer": manufacturer,
                "model": model or "ONVIF Device",
                "username": "",
                "password": "",
                "rtsp": f"rtsp://{ip}/Streaming/Channels/101"
            })
            print(f"[DISCOVERY] WS-Discovery found: {ip}")
        except:
            continue

    print(f"[DISCOVERY] WS-Discovery found {len(devices)} devices")
    return devices

def ping_host(ip):
    try:
        # Faster timeout
        ret = os.system(f"ping -n 1 -w 50 {ip} >nul 2>&1")
        return ip if ret == 0 else None
    except:
        return None

# ----------------------------------------------------------------------
# Brand-specific probes (You were missing these)
# ----------------------------------------------------------------------
def probe_hikvision(ip, port):
    urls = [
        f"http://{ip}:{port}/ISAPI/System/deviceInfo",
        f"http://{ip}:{port}/ISAPI/Security/userCheck",
        f"http://{ip}:{port}/ISAPI/Streaming/Channels/101"
    ]
    for url in urls:
        try:
            r = requests.get(url, timeout=2.0, auth=("admin", "Azsxdcf2013"))
            if r.status_code == 200:
                manufacturer = "Hikvision"
                model = "Hikvision Camera"
                try:
                    root = ET.fromstring(r.content)
                    md = root.find(".//model")
                    name = root.find(".//deviceName")
                    if md is not None and md.text:
                        model = md.text
                    elif name is not None and name.text:
                        model = name.text
                except:
                    pass
                print(f"[DISCOVERY] ✓ Hikvision Hit → {ip} | {model}")
                return manufacturer, model
        except:
            continue
    return None, None


def probe_dahua(ip, port):
    try:
        r = requests.get(f"http://{ip}:{port}/cgi-bin/magicBox.cgi?action=getSystemInfo", timeout=2)
        if r.status_code == 200:
            for line in r.text.splitlines():
                if line.startswith("DeviceType="):
                    model = line.split("=", 1)[1].strip()
                    print(f"[DISCOVERY] ✓ Dahua Hit → {ip}")
                    return "Dahua", model or "Dahua"
    except:
        pass
    return None, None


def probe_vivotek(ip, port):
    try:
        r = requests.get(f"http://{ip}:{port}/cgi-bin/viewer/getparam.cgi", timeout=2)
        if r.status_code == 200 and "model" in r.text.lower():
            model = "Vivotek"
            print(f"[DISCOVERY] ✓ Vivotek Hit → {ip}")
            return "Vivotek", model
    except:
        pass
    return None, None

# ----------------------------------------------------------------------
# Improved Device Probe
# ----------------------------------------------------------------------
def probe_device(ip, username="", password=""):
    # Ports in order of likelihood
    ports_to_try = [80, 554, 8080, 8000, 8899]

    for port in ports_to_try:
        # === ONVIF Probe ===
        try:
            onvif_url = f"http://{ip}:{port}/onvif/device_service"
            soap = """<?xml version="1.0"?>
            <s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope"
                        xmlns:tds="http://www.onvif.org/ver10/device/wsdl">
              <s:Body><tds:GetDeviceInformation/></s:Body>
            </s:Envelope>"""

            resp = requests.post(onvif_url, data=soap,
                                 headers={"Content-Type": "application/soap+xml"},
                                 timeout=2.0, 
                                 auth=(username, password) if username else None)

            if resp.status_code == 200:
                root = ET.fromstring(resp.content)
                ns = {"tds": "http://www.onvif.org/ver10/device/wsdl"}
                m = root.find(".//tds:Manufacturer", ns)
                md = root.find(".//tds:Model", ns)

                manufacturer = m.text if m is not None else "ONVIF"
                model = md.text if md is not None else "Camera"

                print(f"[DISCOVERY] ✓ ONVIF Hit → {ip} | {manufacturer} {model}")
                return {
                    "address": ip,
                    "manufacturer": manufacturer,
                    "model": model,
                    "username": username,
                    "password": password,
                    "rtsp": f"rtsp://{ip}/Streaming/Channels/101"
                }
        except:
            pass

        # === Brand Probes ===
               # === Brand Probes ===
        m, md = probe_hikvision(ip, port)
        if m:
            print(f"[DISCOVERY] ✓ Hikvision Hit → {ip} | {model}")
            return {"address": ip, "manufacturer": m, "model": md or "Hikvision", 
                    "username": username, "password": password, "rtsp": f"rtsp://{ip}/Streaming/Channels/101"}
        
        m, md = probe_dahua(ip, port)
        if m:
            print(f"[DISCOVERY] ✓ Dahua Hit → {ip}")
            return {"address": ip, "manufacturer": m, "model": md or "Dahua", 
                    "username": username, "password": password, 
                    "rtsp": f"rtsp://{ip}/cam/realmonitor?channel=1&subtype=0"}

        m, md = probe_vivotek(ip, port)
        if m:
            print(f"[DISCOVERY] ✓ Vivotek Hit → {ip}")
            return {"address": ip, "manufacturer": m, "model": md or "Vivotek", 
                    "username": username, "password": password, "rtsp": f"rtsp://{ip}/Streaming/Channels/101"}

    # === Aggressive RTSP DESCRIBE Fallback ===
    print(f"[DISCOVERY] Trying RTSP fallback on {ip}...")
    dev = probe_rtsp_only_enhanced(ip)   # We'll define this below
    if dev:
        dev["username"] = username
        dev["password"] = password
        print(f"[DISCOVERY] ✓ RTSP Fallback Hit → {ip}")
        return dev

    return None

def probe_rtsp_only_enhanced(ip):
    common_paths = [
        "Streaming/Channels/101", "Streaming/Channels/1", "Streaming/Channels/0",
        "cam/realmonitor?channel=1&subtype=0", "live", "live1.sdp", "h264", "ch0",
        "profile1", "profile0", "video1", "stream1", "onvif1", "media"
    ]

    for path in common_paths:
        rtsp_url = f"rtsp://{ip}:554/{path}"
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
            sock.settimeout(1.2)
            sock.connect((ip, 554))

            msg = f"DESCRIBE {rtsp_url} RTSP/1.0\r\nCSeq: 2\r\nAccept: application/sdp\r\n\r\n".encode()
            sock.send(msg)
            resp = sock.recv(2048)
            sock.close()

            if b"RTSP/1.0 200" in resp or b"v=0" in resp:
                print(f"[DISCOVERY] RTSP DESCRIBE success: {rtsp_url}")
                return {
                    "address": ip,
                    "manufacturer": "",
                    "model": "",
                    "username": "",
                    "password": "",
                    "rtsp": rtsp_url
                }
        except:
            continue
    return None

# ----------------------------------------------------------------------
# Fast Discovery - Closer to NX Witness style
# ----------------------------------------------------------------------
def discover_onvif(username="", password=""):
    print("[MODULE] Enhanced discovery starting (Fast NX-style)...")
    start_time = time.time()

    devices = ws_discover(timeout=3)

    if len(devices) < 8:
        print("[DISCOVERY] Starting fast targeted probe...")
        candidates = get_probe_candidates()

        with concurrent.futures.ThreadPoolExecutor(max_workers=120) as ex:
            futures = [ex.submit(probe_device, ip, username, password) for ip in candidates]
            
            for f in concurrent.futures.as_completed(futures):
                try:
                    dev = f.result()
                    if dev and not any(d["address"] == dev["address"] for d in devices):
                        devices.append(dev)
                except:
                    pass

    total_time = time.time() - start_time
    print(f"[MODULE] Discovery complete. Found {len(devices)} devices in {total_time:.1f} seconds.")

    for d in devices:
        print(f"   → {d['address']:15} | {d.get('manufacturer','')} {d.get('model','')}")

    return devices


# Smarter candidate generation - much fewer IPs
def get_probe_candidates():
    candidates = set()
    for iface, addrs in psutil.net_if_addrs().items():
        for addr in addrs:
            if addr.family == socket.AF_INET:
                ip_str = addr.address
                if not ip_str.startswith("127.") and not ip_str.startswith("169.254."):
                    base = ".".join(ip_str.split(".")[:3])
                    # Probe a reasonable range around the current IP
                    last_octet = int(ip_str.split(".")[-1])
                    for i in range(max(1, last_octet - 60), min(255, last_octet + 60)):
                        candidates.add(f"{base}.{i}")
    
    candidates = list(candidates)
    print(f"[DISCOVERY] Probing {len(candidates)} likely IPs...")
    return candidates

# Faster & lighter active IP scan
def get_active_ips_fast():
    print("[DISCOVERY] Fast active scan...")
    subnets = []
    for iface, addrs in psutil.net_if_addrs().items():
        for addr in addrs:
            if addr.family == socket.AF_INET and addr.netmask:
                try:
                    net = ipaddress.IPv4Network(f"{addr.address}/{addr.netmask}", strict=False)
                    if not net.is_loopback and not net.is_link_local and net.num_addresses <= 512:
                        subnets.append(net)
                except:
                    continue

    active_ips = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=200) as executor:
        futures = []
        for net in subnets:
            for ip in list(net.hosts())[:100]:   # limit per subnet
                futures.append(executor.submit(ping_host, str(ip)))
        
        for future in concurrent.futures.as_completed(futures):
            if result := future.result():
                active_ips.append(result)

    print(f"[DISCOVERY] Found {len(active_ips)} active IPs")
    return active_ips


def ping_host(ip):
    try:
        return ip if os.system(f"ping -n 1 -w 40 {ip} >nul 2>&1") == 0 else None
    except:
        return None
    
def add_camera_to_go2rtc_config(name, rtsp_url):
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


# ----------------------------------------------------------------------
# Frigate config add/remove
# ----------------------------------------------------------------------
def add_camera_to_frigate_config(name, rtsp_url=None):
    path = FRIGATE_CONFIG_PATH
    try:
        if not os.path.exists(path):
            data = {}
        else:
            with open(path, 'r', encoding='utf-8') as f:
                data = yaml.safe_load(f) or {}

        if 'cameras' not in data:
            data['cameras'] = {}

        if rtsp_url and isinstance(rtsp_url, str) and rtsp_url.strip() != "":
            stream_url = rtsp_url
        else:
            stream_url = f"rtsp://{GO2RTC_HOST}:{GO2RTC_PORT}/{name}"

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
    
    # ----------------------------------------------------------------------
# HTTP HANDLER
# ----------------------------------------------------------------------
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

            try:
                self.wfile.write(payload)
            except ConnectionAbortedError:
                pass

        except Exception as e:
            print(f"[SERVER] send_json error: {e}")

    def do_POST(self):
        length = int(self.headers.get("Content-Length", 0))
        body = self.rfile.read(length)
        try:
            data = json.loads(body)
        except:
            data = {}

        if not self.path.startswith("/api/moduleInformation"):
            print(f"[CLIENT POST] {self.path} -> {data}")

        # --------------------------------------------------------------
        # ADD CAMERA
        # --------------------------------------------------------------
        if self.path == "/api/addCamera":
            cam_id = data.get("id")
            rtsp = data.get("rtsp")

            if not is_valid_camera_name(cam_id) or not is_valid_rtsp_url(rtsp):
                return self.send_json({"status": "error", "error": "invalid addCamera payload"}, 400)

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

        # --------------------------------------------------------------
        # EDIT CAMERA
        # --------------------------------------------------------------
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

        # --------------------------------------------------------------
        # REMOVE CAMERA
        # --------------------------------------------------------------
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

        # --------------------------------------------------------------
        # TEST RTSP
        # --------------------------------------------------------------
        if self.path == "/api/testRtsp":
            rtsp = data.get("rtsp")
            ok = test_rtsp_stream(rtsp)
            return self.send_json({"ok": ok})

        # --------------------------------------------------------------
        # ONVIF DISCOVERY (NX-style)
        # --------------------------------------------------------------
        if self.path == "/api/onvifDiscover":
            try:
                username = data.get("username", "")
                password = data.get("password", "")
                print("[MODULE] ONVIF credentials:", username, password)

                devices = discover_onvif(username, password)
                return self.send_json({"devices": devices})

            except Exception as e:
                print("[MODULE] ERROR in ONVIF discovery:", e)
                return self.send_json({"error": str(e)}, 500)

        # --------------------------------------------------------------
        # ONVIF PROFILES
        # --------------------------------------------------------------
        if self.path == "/api/onvifProfiles":
            address = data.get("address")
            username = data.get("username", "")
            password = data.get("password", "")

            profiles = get_onvif_profiles(address, username, password)
            return self.send_json({"profiles": profiles})

        return self.send_json({"error": "unknown endpoint"}, 404)

    # ------------------------------------------------------------------
    # GET HANDLER
    # ------------------------------------------------------------------
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
            return self.send_json({"error": "onvifDiscover only supports POST"}, 400)


# ----------------------------------------------------------------------
# BROADCAST DISCOVERY (NX-style)
# ----------------------------------------------------------------------
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


# ----------------------------------------------------------------------
# MAIN SERVER LOOP
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

