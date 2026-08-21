import os
import sys
import socket
import struct
import json
import psutil
from pathlib import Path
import subprocess

# ---------------------------------------------------------
# APP DIRECTORY (works both from source and frozen .exe)
# ---------------------------------------------------------

def get_app_dir() -> Path:
    if getattr(sys, "frozen", False):
        # Running as PyInstaller .exe → folder that contains the .exe
        return Path(sys.executable).resolve().parent
    # Running from source
    return Path(__file__).resolve().parent


APP_DIR = get_app_dir()
CONFIG_FILE = APP_DIR / "config.json"

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
    except Exception:
        pass

    try:
        for iface, addrs in psutil.net_if_addrs().items():
            if any(x in iface for x in ["Virtual", "VMware", "Hyper-V", "Loopback", "Docker", "vEthernet", "VPN"]):
                continue
            for addr in addrs:
                if addr.family == socket.AF_INET and not addr.address.startswith("169.254"):
                    return addr.address
    except Exception:
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
    except Exception:
        return None


# ---------------------------------------------------------
# DOCKER HELPERS
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


def auto_detect_container(name_hint: str):
    try:
        result = subprocess.run(
            ["docker", "ps", "-a", "--format", "{{.Names}}|{{.Image}}"],
            capture_output=True,
            text=True
        )
        entries = result.stdout.strip().splitlines()
        hint = name_hint.lower()

        for entry in entries:
            if not entry.strip():
                continue
            parts = entry.split("|", 1)
            if len(parts) != 2:
                continue
            name = parts[0].strip()
            image = parts[1].strip().lower()
            if hint in name.lower() or hint in image:
                return name
    except Exception:
        pass
    return None


def detect_install_type():
    if os.path.exists("/data/options.json"):
        return "hassio"

    try:
        result = subprocess.run(
            ["docker", "ps", "-a", "--format", "{{.Names}}|{{.Image}}"],
            capture_output=True,
            text=True
        )
        for line in result.stdout.splitlines():
            if "frigate" in line.lower() or "go2rtc" in line.lower():
                return "docker"
    except Exception:
        pass

    try:
        result = subprocess.run(
            ["systemctl", "status", "frigate"],
            capture_output=True,
            text=True
        )
        if "Loaded:" in result.stdout:
            return "baremetal"
    except Exception:
        pass

    return "unknown"


# ---------------------------------------------------------
# BUILD DEFAULTS (auto-detection)
# ---------------------------------------------------------

def build_defaults() -> dict:
    lan_ip = get_local_ip()
    if lan_ip == "127.0.0.1":
        lan_ip, subnet_mask = get_ip_and_mask()
    else:
        subnet_mask = "255.255.255.0"

    broadcast = compute_broadcast(lan_ip, subnet_mask)

    frigate_container = os.getenv("FRIGATE_CONTAINER_NAME", "frigate")
    go2rtc_container = os.getenv("GO2RTC_CONTAINER_NAME", "go2rtc")

    detected_frigate = auto_detect_container("frigate")
    if detected_frigate:
        frigate_container = detected_frigate

    detected_go2rtc = auto_detect_container("go2rtc")
    if detected_go2rtc:
        go2rtc_container = detected_go2rtc

    media, cache, config = detect_paths_from_docker(frigate_container)

    return {
        "http_port": int(os.getenv("HTTP_PORT", 8001)),
        "https_port": int(os.getenv("HTTPS_PORT", 8002)),
        "system_id": "{11111111-2222-3333-4444-555555555555}",
        "module_id": "{66666666-7777-8888-9999-000000000000}",
        "system_name": "Frigate System",
        "progress_file": r"C:\PX\onvif_progress.log",

        # Network overrides (empty string = auto-detect)
        "lan_ip": "",
        "subnet_mask": "",
        "broadcast_ip": "",

        "auto_detect_frigate_container": True,
        "auto_detect_go2rtc_container": True,
        "frigate_container_name": frigate_container,
        "go2rtc_container_name": go2rtc_container,

        "frigate_service_name": os.getenv("FRIGATE_SERVICE_NAME", "frigate"),
        "frigate_version": os.getenv("FRIGATE_VERSION", "0.17"),
        "frigate_api_enabled": True,

        # Paths – auto-detected values used as defaults
        "frigate_media_path": str(media) if media else r"C:\frigate\media",
        "frigate_cache_path": str(cache) if cache else r"C:\frigate\cache",
        "frigate_config_path": str(config) if config else r"C:\frigate\config\config.yml",
        "go2rtc_config_path": r"C:\frigate\go2rtc.yaml",
    }


# ---------------------------------------------------------
# LOAD / CREATE USER CONFIG
# ---------------------------------------------------------

def load_user_config() -> dict:
    defaults = build_defaults()

    if not CONFIG_FILE.exists():
        # First run → write a nice template for the user
        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(defaults, f, indent=4)
            print(f"[CONFIG] Created default config → {CONFIG_FILE}")
        except Exception as e:
            print(f"[CONFIG] Could not write default config: {e}")
        return defaults

    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            user = json.load(f)
        # Merge: user values win, missing keys keep defaults
        merged = {**defaults, **user}
        return merged
    except Exception as e:
        print(f"[CONFIG] Failed to read {CONFIG_FILE}: {e}")
        print("[CONFIG] Falling back to defaults")
        return defaults


# ---------------------------------------------------------
# FINAL VALUES (what the rest of the code imports)
# ---------------------------------------------------------

_cfg = load_user_config()

# --- Network (same logic as original working config) ---
LAN_IP = get_local_ip()
if LAN_IP == "127.0.0.1":
    LAN_IP, SUBNET_MASK = get_ip_and_mask()
else:
    # Original behaviour: always assume /24 when we already have a good IP
    SUBNET_MASK = "255.255.255.0"

# Optional overrides from config.json
if _cfg.get("lan_ip"):
    LAN_IP = str(_cfg["lan_ip"]).strip()
if _cfg.get("subnet_mask"):
    SUBNET_MASK = str(_cfg["subnet_mask"]).strip()

BROADCAST_IP = compute_broadcast(LAN_IP, SUBNET_MASK)
if _cfg.get("broadcast_ip"):
    val = str(_cfg["broadcast_ip"]).strip()
    BROADCAST_IP = val if val else BROADCAST_IP

HTTP_PORT = int(_cfg["http_port"])
HTTPS_PORT = int(_cfg["https_port"])

SYSTEM_ID = _cfg["system_id"]
MODULE_ID = _cfg["module_id"]
SYSTEM_NAME = _cfg["system_name"]

PROGRESS_FILE = Path(_cfg["progress_file"])

FRIGATE_CONTAINER_NAME = _cfg["frigate_container_name"]
GO2RTC_CONTAINER_NAME = _cfg["go2rtc_container_name"]
FRIGATE_SERVICE_NAME = _cfg["frigate_service_name"]

FRIGATE_INSTALL_TYPE = detect_install_type()
FRIGATE_VERSION = _cfg["frigate_version"]
FRIGATE_API_ENABLED = bool(_cfg["frigate_api_enabled"])

FRIGATE_MEDIA_PATH = Path(_cfg["frigate_media_path"])
FRIGATE_CACHE_PATH = Path(_cfg["frigate_cache_path"])
FRIGATE_CONFIG_PATH = Path(_cfg["frigate_config_path"])
GO2RTC_CONFIG_PATH = Path(_cfg["go2rtc_config_path"])

# ---------------------------------------------------------
# STARTUP LOG
# ---------------------------------------------------------

print(f"[CONFIG] Config file : {CONFIG_FILE}")
print(f"[CONFIG] LAN IP      : {LAN_IP} | Mask: {SUBNET_MASK} | Broadcast: {BROADCAST_IP}")
print(f"[CONFIG] HTTP/HTTPS  : {HTTP_PORT} / {HTTPS_PORT}")
print(f"[CONFIG] Frigate ctr : {FRIGATE_CONTAINER_NAME}")
print(f"[CONFIG] go2rtc ctr  : {GO2RTC_CONTAINER_NAME}")
print(f"[CONFIG] Install type: {FRIGATE_INSTALL_TYPE}")
print(f"[CONFIG] Media path  : {FRIGATE_MEDIA_PATH}")
print(f"[CONFIG] Cache path  : {FRIGATE_CACHE_PATH}")
print(f"[CONFIG] Config path : {FRIGATE_CONFIG_PATH}")
print(f"[CONFIG] go2rtc path : {GO2RTC_CONFIG_PATH}")