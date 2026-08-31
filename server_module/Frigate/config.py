"""
config.py — single config.json for Windows and Linux.

On first run, writes config.json next to this module with OS-appropriate
defaults. Docker mount detection overrides paths when containers are found.
Env vars always win for a given key when set.
"""
import os
import sys
import socket
import struct
import json
import platform
import psutil
from pathlib import Path
import subprocess

# ---------------------------------------------------------
# APP DIRECTORY (source or frozen binary)
# ---------------------------------------------------------

def get_app_dir() -> Path:
    if getattr(sys, "frozen", False):
        return Path(sys.executable).resolve().parent
    return Path(__file__).resolve().parent


APP_DIR = get_app_dir()
CONFIG_FILE = APP_DIR / "config.json"
IS_WINDOWS = platform.system() == "Windows"


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
        skip = ("Virtual", "VMware", "Hyper-V", "Loopback", "Docker", "vEthernet", "VPN", "veth", "br-")
        for iface, addrs in psutil.net_if_addrs().items():
            if any(x in iface for x in skip):
                continue
            for addr in addrs:
                if addr.family == socket.AF_INET and not addr.address.startswith("169.254"):
                    return addr.address
    except Exception:
        pass

    return "127.0.0.1"


def get_ip_and_mask():
    skip = ("Virtual", "VMware", "Hyper-V", "Loopback", "Docker", "vEthernet", "VPN", "veth", "br-")
    for iface, addrs in psutil.net_if_addrs().items():
        if any(x in iface for x in skip):
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
            text=True,
            timeout=15,
        )
        if result.returncode != 0 or not result.stdout.strip():
            return None, None, None
        data = json.loads(result.stdout)[0]
        mounts = data.get("Mounts", [])

        media_path = None
        cache_path = None
        config_path = None

        for m in mounts:
            dest = m.get("Destination", "")
            src = m.get("Source", "")
            if not src:
                continue
            if dest in ("/media/frigate", "/media"):
                media_path = Path(src)
            if dest in ("/tmp/cache", "/cache"):
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
            text=True,
            timeout=15,
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
            text=True,
            timeout=15,
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
            text=True,
            timeout=10,
        )
        if "Loaded:" in result.stdout:
            return "baremetal"
    except Exception:
        pass

    return "unknown"


def platform_path_defaults() -> dict:
    """OS-specific fallback paths when Docker does not reveal mounts."""
    if IS_WINDOWS:
        return {
            "frigate_media_path": r"C:\frigate\media",
            "frigate_cache_path": r"C:\frigate\cache",
            "frigate_config_path": r"C:\frigate\config\config.yml",
            "go2rtc_config_path": r"C:\frigate\go2rtc.yaml",
            "progress_file": str(APP_DIR / "onvif_progress.log"),
        }

    candidates_config = [
        Path("/config/config.yml"),
        Path("/opt/frigate/config/config.yml"),
        Path.home() / "frigate" / "config" / "config.yml",
        Path("/etc/frigate/config.yml"),
    ]
    candidates_go2rtc = [
        Path("/config/go2rtc.yaml"),
        Path("/opt/frigate/go2rtc.yaml"),
        Path.home() / "frigate" / "go2rtc.yaml",
        Path("/etc/go2rtc/go2rtc.yaml"),
    ]
    candidates_media = [
        Path("/media/frigate"),
        Path("/opt/frigate/media"),
        Path.home() / "frigate" / "media",
    ]
    candidates_cache = [
        Path("/tmp/cache"),
        Path("/opt/frigate/cache"),
        Path.home() / "frigate" / "cache",
    ]

    def first_existing(paths, fallback: Path) -> str:
        for p in paths:
            if p.exists():
                return str(p)
        return str(fallback)

    return {
        "frigate_media_path": first_existing(candidates_media, Path("/media/frigate")),
        "frigate_cache_path": first_existing(candidates_cache, Path("/tmp/cache")),
        "frigate_config_path": first_existing(candidates_config, Path("/config/config.yml")),
        "go2rtc_config_path": first_existing(candidates_go2rtc, Path("/config/go2rtc.yaml")),
        "progress_file": str(APP_DIR / "onvif_progress.log"),
    }


def path_looks_foreign(path_str: str) -> bool:
    """True if path is clearly for the other OS (e.g. C:\\ on Linux)."""
    if not path_str:
        return False
    s = str(path_str)
    if IS_WINDOWS:
        return s.startswith("/") and not s.startswith("//")
    return len(s) >= 2 and s[1] == ":" and s[0].isalpha()


# ---------------------------------------------------------
# BUILD DEFAULTS
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
    os_paths = platform_path_defaults()

    media_path = str(media) if media else os_paths["frigate_media_path"]
    cache_path = str(cache) if cache else os_paths["frigate_cache_path"]
    config_path = str(config) if config else os_paths["frigate_config_path"]

    go2rtc_path = os_paths["go2rtc_config_path"]
    if config:
        sibling = Path(config).parent / "go2rtc.yaml"
        if sibling.exists():
            go2rtc_path = str(sibling)

    return {
        "http_port": int(os.getenv("HTTP_PORT", 8001)),
        "https_port": int(os.getenv("HTTPS_PORT", 8002)),
        "system_id": "{11111111-2222-3333-4444-555555555555}",
        "module_id": "{66666666-7777-8888-9999-000000000000}",
        "system_name": "Frigate System",
        "progress_file": os_paths["progress_file"],

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

        "frigate_media_path": media_path,
        "frigate_cache_path": cache_path,
        "frigate_config_path": config_path,
        "go2rtc_config_path": go2rtc_path,
    }


# ---------------------------------------------------------
# LOAD / CREATE USER CONFIG (one file both OS)
# ---------------------------------------------------------

def load_user_config() -> dict:
    defaults = build_defaults()

    if not CONFIG_FILE.exists():
        try:
            with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                json.dump(defaults, f, indent=4)
            print(f"[CONFIG] Created default config → {CONFIG_FILE}")
            print(f"[CONFIG] Platform: {platform.system()}")
        except Exception as e:
            print(f"[CONFIG] Could not write default config: {e}")
        return defaults

    try:
        with open(CONFIG_FILE, "r", encoding="utf-8") as f:
            user = json.load(f)
        if not isinstance(user, dict):
            print("[CONFIG] config.json is not an object — using defaults")
            return defaults

        merged = {**defaults, **user}

        path_keys = (
            "frigate_media_path",
            "frigate_cache_path",
            "frigate_config_path",
            "go2rtc_config_path",
            "progress_file",
        )
        fixed = False
        for key in path_keys:
            val = str(merged.get(key, ""))
            if path_looks_foreign(val):
                print(f"[CONFIG] {key} looks wrong for {platform.system()} ({val}) — using default")
                merged[key] = defaults[key]
                fixed = True

        if fixed:
            try:
                with open(CONFIG_FILE, "w", encoding="utf-8") as f:
                    json.dump(merged, f, indent=4)
                print(f"[CONFIG] Updated path(s) in {CONFIG_FILE} for this OS")
            except Exception as e:
                print(f"[CONFIG] Could not rewrite config.json: {e}")

        return merged
    except Exception as e:
        print(f"[CONFIG] Failed to read {CONFIG_FILE}: {e}")
        print("[CONFIG] Falling back to defaults")
        return defaults


# ---------------------------------------------------------
# FINAL VALUES
# ---------------------------------------------------------

_cfg = load_user_config()

LAN_IP = get_local_ip()
if LAN_IP == "127.0.0.1":
    LAN_IP, SUBNET_MASK = get_ip_and_mask()
else:
    SUBNET_MASK = "255.255.255.0"

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

if os.getenv("FRIGATE_CONFIG_PATH"):
    FRIGATE_CONFIG_PATH = Path(os.getenv("FRIGATE_CONFIG_PATH"))
if os.getenv("GO2RTC_CONFIG_PATH"):
    GO2RTC_CONFIG_PATH = Path(os.getenv("GO2RTC_CONFIG_PATH"))
if os.getenv("FRIGATE_MEDIA_PATH"):
    FRIGATE_MEDIA_PATH = Path(os.getenv("FRIGATE_MEDIA_PATH"))
if os.getenv("FRIGATE_CACHE_PATH"):
    FRIGATE_CACHE_PATH = Path(os.getenv("FRIGATE_CACHE_PATH"))

print(f"[CONFIG] Config file : {CONFIG_FILE}")
print(f"[CONFIG] Platform    : {platform.system()}")
print(f"[CONFIG] LAN IP      : {LAN_IP} | Mask: {SUBNET_MASK} | Broadcast: {BROADCAST_IP}")
print(f"[CONFIG] HTTP/HTTPS  : {HTTP_PORT} / {HTTPS_PORT}")
print(f"[CONFIG] Frigate ctr : {FRIGATE_CONTAINER_NAME}")
print(f"[CONFIG] go2rtc ctr  : {GO2RTC_CONTAINER_NAME}")
print(f"[CONFIG] Install type: {FRIGATE_INSTALL_TYPE}")
print(f"[CONFIG] Media path  : {FRIGATE_MEDIA_PATH}")
print(f"[CONFIG] Cache path  : {FRIGATE_CACHE_PATH}")
print(f"[CONFIG] Config path : {FRIGATE_CONFIG_PATH}")
print(f"[CONFIG] go2rtc path : {GO2RTC_CONFIG_PATH}")