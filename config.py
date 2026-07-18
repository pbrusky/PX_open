import os
import socket
import struct
import psutil
from pathlib import Path

# ---------------------------------------------------------
# NETWORK DETECTION
# ---------------------------------------------------------

def get_local_ip() -> str:
    """Get best available LAN IP"""
    # Priority 1: Environment override
    env_ip = os.getenv("HOST_IP") or os.getenv("FRIGATE_SERVER_IP")
    if env_ip:
        return env_ip

    # Priority 2: Standard method
    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        if not ip.startswith("169.254"):
            return ip
    except:
        pass

    # Priority 3: psutil (more reliable on Windows)
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
    """Return (ip, subnet_mask)"""
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

FRIGATE_HOST = LAN_IP
FRIGATE_PORT = 5000
FRIGATE_BASE = f"http://{FRIGATE_HOST}:{FRIGATE_PORT}"

FRIGATE_CONFIG_PATH = Path(r"C:\frigate\config\config.yml")
GO2RTC_CONFIG_PATH = Path(r"C:\frigate\go2rtc.yaml")

GO2RTC_HOST = "127.0.0.1"
GO2RTC_PORT = 1984
GO2RTC_BASE = f"http://{GO2RTC_HOST}:{GO2RTC_PORT}"

HTTP_PORT = int(os.getenv("HTTP_PORT", 8001))
HTTPS_PORT = int(os.getenv("HTTPS_PORT", 8002))

SYSTEM_ID = "{11111111-2222-3333-4444-555555555555}"
MODULE_ID = "{66666666-7777-8888-9999-000000000000}"
SYSTEM_NAME = "Frigate System"

PROGRESS_FILE = Path(r"C:\PX\onvif_progress.log")

print(f"[CONFIG] LAN IP: {LAN_IP} | Broadcast: {BROADCAST_IP}")