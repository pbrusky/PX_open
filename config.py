import os
import socket
from pathlib import Path

def get_local_ip() -> str:
    """Get the host's LAN IP. Works on Windows and inside Docker."""
    env_ip = os.getenv("HOST_IP") or os.getenv("FRIGATE_SERVER_IP")
    if env_ip:
        return env_ip

    try:
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        s.connect(("8.8.8.8", 80))
        ip = s.getsockname()[0]
        s.close()
        return ip
    except Exception:
        pass

    try:
        return socket.gethostbyname(socket.gethostname())
    except:
        return "127.0.0.1"


# ====================== CONFIG ======================

LAN_IP = get_local_ip()

FRIGATE_HOST = LAN_IP
FRIGATE_PORT = 5000
FRIGATE_BASE = f"http://{FRIGATE_HOST}:{FRIGATE_PORT}"

FRIGATE_CONFIG_PATH = Path(r"C:\frigate\config\config.yml")

# ------------------- go2rtc -------------------
GO2RTC_HOST = os.getenv("GO2RTC_HOST", "127.0.0.1")
GO2RTC_PORT = int(os.getenv("GO2RTC_PORT", 1984))
GO2RTC_BASE = f"http://{GO2RTC_HOST}:{GO2RTC_PORT}"

GO2RTC_CONFIG_PATH = Path(r"C:\frigate\go2rtc.yaml")
GO2RTC_DOCKER_NAME = os.getenv("GO2RTC_DOCKER_NAME", "go2rtc")

HTTP_PORT = int(os.getenv("HTTP_PORT", 8001))
HTTPS_PORT = int(os.getenv("HTTPS_PORT", 8002))
MODULE_ID = os.getenv("MODULE_ID", "{66666666-7777-8888-9999-000000000000}")
SYSTEM_ID = os.getenv("SYSTEM_ID", "{11111111-2222-3333-4444-555555555555}")
SYSTEM_NAME = os.getenv("SYSTEM_NAME", "Frigate System")

PROGRESS_FILE = Path(os.getenv("PROGRESS_DIR", r"C:\PX")) / "onvif_progress.log"
