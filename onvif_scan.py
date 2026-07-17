import requests
import concurrent.futures
import xml.etree.ElementTree as ET
import json
import sys
import os
from requests.auth import HTTPDigestAuth
from threading import Lock
import signal

TIMEOUT = 1.15
MAX_WORKERS = 80

if len(sys.argv) < 2:
    print(json.dumps({"error": "No subnet provided"}))
    sys.exit(1)

SUBNET = sys.argv[1].rstrip('.') + "."
USERNAME = sys.argv[2] if len(sys.argv) >= 3 else ""
PASSWORD = sys.argv[3] if len(sys.argv) >= 4 else ""

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
PROGRESS_FILE = os.path.join(SCRIPT_DIR, "onvif_progress.log")

progress_lock = Lock()

def log(msg):
    with progress_lock:
        try:
            with open(PROGRESS_FILE, "a", encoding="utf-8") as f:
                f.write(msg + "\n")
            print(msg, file=sys.stderr)
        except:
            pass

session = requests.Session()
session.mount('http://', requests.adapters.HTTPAdapter(pool_connections=100, pool_maxsize=100))

# ---------------------------------------------------------
def detect_onvif(ip):
    try:
        url = f"http://{ip}/onvif/device_service"
        soap = '''<?xml version="1.0"?>
<s:Envelope xmlns:s="http://www.w3.org/2003/05/soap-envelope">
  <s:Body><GetDeviceInformation xmlns="http://www.onvif.org/ver10/device/wsdl"/></s:Body>
</s:Envelope>'''

        auth = HTTPDigestAuth(USERNAME, PASSWORD) if USERNAME else None
        r = session.post(url, data=soap, timeout=TIMEOUT, auth=auth)
        
        if r.status_code == 200:
            xml = ET.fromstring(r.text)
            log(f"ONVIF → {ip}")
            
            manufacturer = model = firmware = serial = hardware = "Unknown"
            for elem in xml.iter():
                tag = elem.tag.split('}')[-1]
                if elem.text:
                    if tag == "Manufacturer": manufacturer = elem.text
                    elif tag == "Model": model = elem.text
                    elif tag == "FirmwareVersion": firmware = elem.text
                    elif tag == "SerialNumber": serial = elem.text
                    elif tag == "HardwareId": hardware = elem.text
            
            return {
                "address": ip,
                "protocol": "ONVIF",
                "manufacturer": manufacturer,
                "model": model,
                "firmware": firmware,
                "serial": serial,
                "hardware": hardware,
                "rtsp": []
            }
    except:
        pass
    return None


def detect_hikvision(ip):
    try:
        auth = HTTPDigestAuth(USERNAME, PASSWORD) if USERNAME else None
        r = session.get(f"http://{ip}/ISAPI/System/deviceInfo", timeout=0.9, auth=auth)
        if r.status_code == 200:
            xml = ET.fromstring(r.text)
            log(f"Hikvision → {ip}")
            return {
                "address": ip,
                "protocol": "Hikvision",
                "manufacturer": "Hikvision",
                "model": getattr(xml.find(".//model"), 'text', "Hikvision"),
                "firmware": getattr(xml.find(".//firmwareVersion"), 'text', "Unknown"),
                "serial": getattr(xml.find(".//serialNumber"), 'text', "Unknown"),
                "hardware": "Unknown",
                "rtsp": []
            }
    except:
        pass
    return None


def detect_dahua(ip):
    try:
        auth = HTTPDigestAuth(USERNAME, PASSWORD) if USERNAME else None
        r = session.get(f"http://{ip}/cgi-bin/magicBox.cgi?action=getSystemInfo", timeout=0.9, auth=auth)
        if r.status_code == 200:
            info = dict(line.split("=", 1) for line in r.text.splitlines() if "=" in line)
            log(f"Dahua → {ip}")
            return {
                "address": ip,
                "protocol": "Dahua",
                "manufacturer": "Dahua",
                "model": info.get("deviceType", "Dahua"),
                "firmware": info.get("softwareVersion", "Unknown"),
                "serial": info.get("serialNumber", "Unknown"),
                "hardware": info.get("hardwareVersion", "Unknown"),
                "rtsp": []
            }
    except:
        pass
    return None


def scan_ip(ip):
    for detector in [detect_onvif, detect_hikvision, detect_dahua]:
        result = detector(ip)
        if result:
            return result
    return None


def shutdown_handler(signum, frame):
    log("[SCAN] Scan interrupted")
    sys.exit(0)

signal.signal(signal.SIGINT, shutdown_handler)
signal.signal(signal.SIGTERM, shutdown_handler)

# ---------------------------------------------------------
if __name__ == "__main__":
    open(PROGRESS_FILE, "w").close()
    log(f"[SCAN] Starting scan on {SUBNET}0/24...")

    devices = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [executor.submit(scan_ip, f"{SUBNET}{i}") for i in range(1, 255)]
        try:
            for future in concurrent.futures.as_completed(futures):
                if result := future.result():
                    devices.append(result)
        except KeyboardInterrupt:
            log("[SCAN] Scan cancelled by user")

    log(f"[SCAN] Total cameras found: {len(devices)}")
    print(json.dumps(devices, indent=2))