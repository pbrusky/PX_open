import requests
import concurrent.futures
import xml.etree.ElementTree as ET
import json
import sys
import os
from requests.auth import HTTPDigestAuth
from threading import Lock

TIMEOUT = 1.2
MAX_WORKERS = 80

# Command line arguments
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
            
            info = {
                "address": ip,
                "protocol": "ONVIF",
                "manufacturer": "Unknown",
                "model": "Unknown",
                "firmware": "Unknown",
                "serial": "Unknown",
                "hardware": "Unknown",
                "rtsp": []
            }

            for elem in xml.iter():
                tag = elem.tag.split('}')[-1]
                if elem.text and elem.text.strip():
                    if tag == "Manufacturer": info["manufacturer"] = elem.text.strip()
                    elif tag == "Model": info["model"] = elem.text.strip()
                    elif tag == "FirmwareVersion": info["firmware"] = elem.text.strip()
                    elif tag == "SerialNumber": info["serial"] = elem.text.strip()
                    elif tag == "HardwareId": info["hardware"] = elem.text.strip()

            return info
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
                "model": (xml.find(".//model") or ET.Element("")).text or "Hikvision",
                "firmware": (xml.find(".//firmwareVersion") or ET.Element("")).text or "Unknown",
                "serial": (xml.find(".//serialNumber") or ET.Element("")).text or "Unknown",
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


# ---------------------------------------------------------
if __name__ == "__main__":
    open(PROGRESS_FILE, "w").close()
    log(f"[SCAN] Starting scan on {SUBNET}0/24...")

    devices = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=MAX_WORKERS) as executor:
        futures = [executor.submit(scan_ip, f"{SUBNET}{i}") for i in range(1, 255)]
        
        for future in concurrent.futures.as_completed(futures):
            try:
                if result := future.result():
                    devices.append(result)
            except Exception:
                pass

    log(f"[SCAN] Total devices found: {len(devices)}")
    print(json.dumps(devices, indent=2))