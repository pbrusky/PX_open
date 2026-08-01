import os
import socket
import struct
import psutil
from pathlib import Path
import subprocess
import yaml
import json

# ---------------------------------------------------------
# NETWORK DETECTION
# ---------------------------------------------------------

def get_local_ip() -> str:
    env_ip = os.getenv("HOST_IP") or os.getenv("FRIGATE_SERVER_IP")
    if env_ip:
        return env_ip

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if not ip.startswith("169.254"):
            return ip
    except:
        pass

    try:
        for iface, addrs in psutil.net_if_addrs().items():
            if any(x in iface for x in ["Virtual", "VMware", "Hyper-V", "Loopback", "Docker", "vEthernet", "VPN"]):
                continue
            for addr in addrs:
                if addr.family == socket.AF_INET and not addr.address.startswith("169.254"):
                    return addr.address
    except:
        pass

    return "127.0.0.1"


def get_ip_and_mask():
    for iface, addrs in psutil.net_if_addrs().items():
        if any(x in iface for x in ["Virtual", "VMware", "Hyper-V", "Loopback", "Docker", "vEthernet", "VPN"]):
            continue
        for addr in addrs:
            if addr.family == socket.AF_INET:
                return addr.address, addr.netmask or "255.255.255.0"
    return "127.0.0.1", "255.255.255.0"


def compute_broadcast(ip: str, mask: str):
    try:
        ip_packed = struct.unpack("!I", socket.inet_aton(ip))[0]
        mask_packed = struct.unpack("!I", socket.inet_aton(mask))[0]

        if mask_packed in (0xFFFFFFFF, 0xFFFFFFFE):
            return None

        broadcast_packed = ip_packed | (~mask_packed & 0xFFFFFFFF)
        return socket.inet_ntoa(struct.pack("!I", broadcast_packed))
    except:
        return None


# ====================== CONFIG ======================

LAN_IP = get_local_ip()
LAN_IP, SUBNET_MASK = get_ip_and_mask() if LAN_IP == "127.0.0.1" else (LAN_IP, "255.255.255.0")
BROADCAST_IP = compute_broadcast(LAN_IP, SUBNET_MASK)

HTTP_PORT = int(os.getenv("HTTP_PORT", 8001))
HTTPS_PORT = int(os.getenv("HTTPS_PORT", 8002))

SYSTEM_ID = "{11111111-2222-3333-4444-555555555555}"
MODULE_ID = "{66666666-7777-8888-9999-000000000000}"
SYSTEM_NAME = "Frigate System"

PROGRESS_FILE = Path(r"C:\PX\onvif_progress.log")

# ---------------------------------------------------------
# DOCKER INSPECT PARSING (REPLACES OLD COMPOSE PARSER)
# ---------------------------------------------------------

def detect_paths_from_docker(container_name):
    try:
        result = subprocess.run(
            ["docker", "inspect", container_name],
            capture_output=True,
            text=True
        )

        data = json.loads(result.stdout)[0]
        mounts = data.get("Mounts", [])

        media_path = None
        cache_path = None
        config_path = None

        for m in mounts:
            dest = m.get("Destination", "")
            src = m.get("Source", "")

            if dest == "/media/frigate":
                media_path = Path(src)

            if dest == "/tmp/cache":
                cache_path = Path(src)

            if dest == "/config":
                config_path = Path(src) / "config.yml"

        return media_path, cache_path, config_path

    except Exception as e:
        print("[CONFIG] docker inspect failed:", e)
        return None, None, None


# ---------------------------------------------------------
# DOCKER CONTAINER NAMES (AUTO-DETECT + OVERRIDE)
# ---------------------------------------------------------

def auto_detect_container(name_hint: str):
    try:
        result = subprocess.run(
            ["docker", "ps", "--format", "{{.Names}}"],
            capture_output=True,
            text=True
        )
        names = result.stdout.strip().splitlines()
        for n in names:
            if name_hint.lower() in n.lower():
                return n
    except:
        pass
    return None


AUTO_DETECT_FRIGATE_CONTAINER = True
AUTO_DETECT_GO2RTC_CONTAINER = True

FRIGATE_CONTAINER_NAME = os.getenv("FRIGATE_CONTAINER_NAME", "frigate")
GO2RTC_CONTAINER_NAME = os.getenv("GO2RTC_CONTAINER_NAME", "go2rtc")

if AUTO_DETECT_FRIGATE_CONTAINER:
    detected = auto_detect_container("frigate")
    if detected:
        FRIGATE_CONTAINER_NAME = detected

if AUTO_DETECT_GO2RTC_CONTAINER:
    detected = auto_detect_container("go2rtc")
    if detected:
        GO2RTC_CONTAINER_NAME = detected

# ---------------------------------------------------------
# INSTALL TYPE DETECTION
# ---------------------------------------------------------

def detect_install_type():
    if os.path.exists("/data/options.json"):
        return "hassio"

    try:
        result = subprocess.run(["docker", "ps"], capture_output=True, text=True)
        if "frigate" in result.stdout.lower():
            return "docker"
    except:
        pass

    try:
        result = subprocess.run(["systemctl", "status", "frigate"], capture_output=True, text=True)
        if "Loaded:" in result.stdout:
            return "baremetal"
    except:
        pass

    return "unknown"


FRIGATE_INSTALL_TYPE = detect_install_type()
FRIGATE_SERVICE_NAME = os.getenv("FRIGATE_SERVICE_NAME", "frigate")

FRIGATE_VERSION = os.getenv("FRIGATE_VERSION", "0.17")
FRIGATE_API_ENABLED = True

# ---------------------------------------------------------
# FINAL PATH RESOLUTION USING DOCKER INSPECT
# ---------------------------------------------------------

FRIGATE_MEDIA_PATH, FRIGATE_CACHE_PATH, FRIGATE_CONFIG_PATH = detect_paths_from_docker(FRIGATE_CONTAINER_NAME)

# Fallbacks if docker inspect fails
if FRIGATE_MEDIA_PATH is None:
    FRIGATE_MEDIA_PATH = Path(r"C:\frigate\media\frigate")

if FRIGATE_CACHE_PATH is None:
    FRIGATE_CACHE_PATH = Path(r"C:\frigate\cache")

if FRIGATE_CONFIG_PATH is None:
    FRIGATE_CONFIG_PATH = Path(r"C:\frigate\config\config.yml")

GO2RTC_CONFIG_PATH = Path(r"C:\frigate\go2rtc.yaml")

print(f"[CONFIG] LAN IP: {LAN_IP} | Broadcast: {BROADCAST_IP}")
print(f"[CONFIG] Frigate container: {FRIGATE_CONTAINER_NAME}")
print(f"[CONFIG] go2rtc container: {GO2RTC_CONTAINER_NAME}")
print(f"[CONFIG] Install type: {FRIGATE_INSTALL_TYPE}")
print(f"[CONFIG] Media path: {FRIGATE_MEDIA_PATH}")
print(f"[CONFIG] Cache path: {FRIGATE_CACHE_PATH}")
print(f"[CONFIG] Config path: {FRIGATE_CONFIG_PATH}")
