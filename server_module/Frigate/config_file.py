"""
config_file.py — read / write Frigate and go2rtc config files for the PX editor.

Uses paths from config.py. Always creates a timestamped backup before overwrite.
"""
from __future__ import annotations

import time
import shutil
from pathlib import Path

from config import (
    FRIGATE_CONFIG_PATH,
    GO2RTC_CONFIG_PATH,
    FRIGATE_CONTAINER_NAME,
    GO2RTC_CONTAINER_NAME,
)

try:
    import yaml
except Exception:
    yaml = None


def _read_text(path: Path) -> tuple[bool, str, str]:
    try:
        if not path.exists():
            return False, "", f"File not found: {path}"
        text = path.read_text(encoding="utf-8")
        return True, text, ""
    except Exception as e:
        return False, "", str(e)


def _backup(path: Path) -> str | None:
    if not path.exists():
        return None
    backup = path.with_name(f"{path.name}.bak_{int(time.time())}")
    shutil.copy2(path, backup)
    print(f"[config_file] backup → {backup}")
    return str(backup)


def _validate_yaml(content: str) -> tuple[bool, str]:
    if yaml is None:
        return True, ""
    try:
        data = yaml.safe_load(content)
        if content.strip() and data is None:
            return False, "YAML parsed to empty/null"
        return True, ""
    except Exception as e:
        return False, f"Invalid YAML: {e}"


def _write_text(path: Path, content: str) -> tuple[bool, str]:
    try:
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(content, encoding="utf-8")
        return True, ""
    except Exception as e:
        return False, str(e)


def _restart_named(name: str) -> bool:
    if not name or not str(name).strip():
        return True
    import subprocess
    try:
        r = subprocess.run(
            ["docker", "restart", str(name).strip()],
            capture_output=True,
            text=True,
            timeout=180,
        )
        if r.returncode == 0:
            print(f"[config_file] restarted {name}")
            return True
        print(f"[config_file] restart failed {name}: {r.stderr or r.stdout}")
        r2 = subprocess.run(
            ["docker", "start", str(name).strip()],
            capture_output=True,
            text=True,
            timeout=120,
        )
        return r2.returncode == 0
    except Exception as e:
        print(f"[config_file] restart error {name}: {e}")
        return False


def get_frigate_config() -> dict:
    path = Path(FRIGATE_CONFIG_PATH)
    ok, content, err = _read_text(path)
    return {
        "ok": ok,
        "event": "getFrigateConfig",
        "path": str(path),
        "content": content if ok else "",
        "message": "ok" if ok else err,
    }


def get_go2rtc_config() -> dict:
    path = Path(GO2RTC_CONFIG_PATH)
    ok, content, err = _read_text(path)
    if not ok and "not found" in err.lower():
        return {
            "ok": True,
            "event": "getGo2rtcConfig",
            "path": str(path),
            "content": "streams: {}\n",
            "message": "file missing — returning empty template",
        }
    return {
        "ok": ok,
        "event": "getGo2rtcConfig",
        "path": str(path),
        "content": content if ok else "",
        "message": "ok" if ok else err,
    }


def save_frigate_config(content, restart: bool = True) -> dict:
    if content is None:
        return {
            "ok": False,
            "event": "saveFrigateConfig",
            "message": "Missing content",
        }
    text = content if isinstance(content, str) else str(content)
    path = Path(FRIGATE_CONFIG_PATH)

    valid, verr = _validate_yaml(text)
    if not valid:
        return {
            "ok": False,
            "event": "saveFrigateConfig",
            "path": str(path),
            "message": verr,
        }

    try:
        backup = _backup(path)
    except Exception as e:
        return {
            "ok": False,
            "event": "saveFrigateConfig",
            "path": str(path),
            "message": f"Backup failed: {e}",
        }

    wok, werr = _write_text(path, text)
    if not wok:
        return {
            "ok": False,
            "event": "saveFrigateConfig",
            "path": str(path),
            "message": f"Write failed: {werr}",
        }

    restart_ok = True
    if restart:
        restart_ok = _restart_named(FRIGATE_CONTAINER_NAME)

    msg = f"Saved {path}"
    if backup:
        msg += f" (backup {backup})"
    if restart and not restart_ok:
        msg += " — restart Frigate failed (config was written)"

    return {
        "ok": True,
        "event": "saveFrigateConfig",
        "path": str(path),
        "backup": backup,
        "restarted": bool(restart and restart_ok),
        "message": msg,
    }


def save_go2rtc_config(content, restart: bool = True) -> dict:
    if content is None:
        return {
            "ok": False,
            "event": "saveGo2rtcConfig",
            "message": "Missing content",
        }
    text = content if isinstance(content, str) else str(content)
    path = Path(GO2RTC_CONFIG_PATH)

    valid, verr = _validate_yaml(text)
    if not valid:
        return {
            "ok": False,
            "event": "saveGo2rtcConfig",
            "path": str(path),
            "message": verr,
        }

    try:
        backup = _backup(path)
    except Exception as e:
        return {
            "ok": False,
            "event": "saveGo2rtcConfig",
            "path": str(path),
            "message": f"Backup failed: {e}",
        }

    wok, werr = _write_text(path, text)
    if not wok:
        return {
            "ok": False,
            "event": "saveGo2rtcConfig",
            "path": str(path),
            "message": f"Write failed: {werr}",
        }

    restart_ok = True
    if restart:
        name = str(GO2RTC_CONTAINER_NAME or "").strip()
        if name:
            restart_ok = _restart_named(name)
        else:
            restart_ok = _restart_named(FRIGATE_CONTAINER_NAME)

    msg = f"Saved {path}"
    if backup:
        msg += f" (backup {backup})"
    if restart and not restart_ok:
        msg += " — restart failed (config was written)"

    return {
        "ok": True,
        "event": "saveGo2rtcConfig",
        "path": str(path),
        "backup": backup,
        "restarted": bool(restart and restart_ok),
        "message": msg,
    }