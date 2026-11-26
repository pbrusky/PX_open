"""
remove_camera.py — Non-blocking camera removal.
Updates YAML immediately and triggers restart in a background thread.
"""
import yaml
import os
import shutil
import time
import subprocess
import threading
from pathlib import Path

from config import (
    FRIGATE_CONFIG_PATH,
    GO2RTC_CONFIG_PATH,
    FRIGATE_CONTAINER_NAME,
    GO2RTC_CONTAINER_NAME,
    FRIGATE_MEDIA_PATH,
    FRIGATE_CACHE_PATH,
)

def backup_file(path):
    p = Path(path)
    if not p.exists(): return
    try:
        backup = p.with_name(f"{p.name}.bak_{int(time.time())}")
        shutil.copy2(str(p), str(backup))
    except Exception as e:
        print(f"[backup] ERROR: {e}")

def load_yaml(path):
    try:
        p = Path(path)
        if not p.exists(): return {}, False
        with open(str(p), "r", encoding="utf-8") as f:
            data = yaml.safe_load(f)
        return (data if isinstance(data, dict) else {}), True
    except Exception:
        return {}, False

def save_yaml(path, data):
    try:
        with open(str(path), "w", encoding="utf-8") as f:
            yaml.safe_dump(data, f, default_flow_style=False, sort_keys=False, allow_unicode=True)
        return True
    except Exception:
        return False

def stream_keys(cam_id):
    cid = (cam_id or "").strip()
    return {
        cid, f"{cid}_main", f"{cid}_sub",
        cid.replace(" ", "_"), f"{cid.replace(' ', '_')}_main", f"{cid.replace(' ', '_')}_sub"
    }

def delete_stream_keys(streams, cam_id):
    if not isinstance(streams, dict): return {}, []
    wanted = {k.casefold() for k in stream_keys(cam_id)}
    removed = []
    for key in list(streams.keys()):
        if str(key).casefold() in wanted:
            del streams[key]
            removed.append(str(key))
    return streams, removed

def _do_docker_restart():
    """Background worker to handle the slow docker commands."""
    # Give the HTTP response a tiny head start to reach the client
    time.sleep(0.5)
    
    go2 = GO2RTC_CONTAINER_NAME or "go2rtc"
    fr = FRIGATE_CONTAINER_NAME or "frigate"
    
    exe = shutil.which("docker") or "docker"
    
    for name in [go2, fr]:
        if not name: continue
        print(f"[background-restart] Restarting {name}...")
        subprocess.run([exe, "restart", name], capture_output=True)

def remove_camera(cam_id):
    print(f"\n[remove_camera] Request for: {cam_id}")
    cam_id = (cam_id or "").strip()
    if not cam_id:
        return {"event": "cameraRemoveResult", "ok": False, "message": "Invalid name"}

    # 1. Update go2rtc.yaml
    p_go2 = Path(GO2RTC_CONFIG_PATH)
    if p_go2.exists():
        cfg, ok = load_yaml(p_go2)
        if ok:
            streams = cfg.get("streams")
            if isinstance(streams, dict):
                streams, removed = delete_stream_keys(streams, cam_id)
                if removed:
                    backup_file(p_go2)
                    cfg["streams"] = streams
                    save_yaml(p_go2, cfg)

    # 2. Update frigate.yml
    p_fr = Path(FRIGATE_CONFIG_PATH)
    cfg, ok = load_yaml(p_fr)
    changed = False
    if ok:
        wanted = {k.casefold() for k in stream_keys(cam_id)}
        
        # Remove from cameras
        cams = cfg.get("cameras")
        if isinstance(cams, dict):
            for key in list(cams.keys()):
                if str(key).casefold() in wanted:
                    del cams[key]
                    changed = True
        
        # Remove from embedded go2rtc
        go2_block = cfg.get("go2rtc")
        if isinstance(go2_block, dict) and isinstance(go2_block.get("streams"), dict):
            streams, removed = delete_stream_keys(go2_block["streams"], cam_id)
            if removed:
                cfg["go2rtc"]["streams"] = streams
                changed = True
        
        if changed:
            backup_file(p_fr)
            save_yaml(p_fr, cfg)

    # 3. Clean up media files
    search_names = stream_keys(cam_id)
    for root_dir in (FRIGATE_MEDIA_PATH, FRIGATE_CACHE_PATH):
        try:
            root = Path(root_dir)
            if not root.exists(): continue
            for name in search_names:
                if not name: continue
                folder = root / name
                if folder.exists() and folder.is_dir() and folder != root:
                    shutil.rmtree(folder, ignore_errors=True)
        except: pass

    # 4. Trigger Restart in Background Thread
    # This prevents the 10054 Connection Reset error
    threading.Thread(target=_do_docker_restart, daemon=True).start()

    print("[remove_camera] Config updated, restart triggered in background.")
    return {
        "event": "cameraRemoveResult",
        "ok": True,
        "message": f"Camera {cam_id} removed. System is restarting in the background."
    }