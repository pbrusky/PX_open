import ssl
import json
from fastapi import FastAPI
from fastapi.responses import JSONResponse
from wsdiscovery import WSDiscovery
from wsdiscovery import QName
from onvif import ONVIFCamera

app = FastAPI()

def discover_onvif_devices():
    """
    Performs WS-Discovery to find ONVIF cameras on the network.
    Returns a list of dicts matching your QML + FrigateAPI.cpp.
    """

    devices = []
    wsd = WSDiscovery()
    wsd.start()

    # ONVIF device type
    onvif_type = QName("http://www.onvif.org/ver10/device/wsdl", "Device")

    found = wsd.searchServices(types=[onvif_type])

    for service in found:
        addr = service.getXAddrs()[0] if service.getXAddrs() else None
        if not addr:
            continue

        # Extract IP from URL
        # Example: http://10.36.24.115:80/onvif/device_service
        try:
            ip = addr.split("//")[1].split("/")[0].split(":")[0]
        except:
            ip = "Unknown"

        # Build NX-style RTSP path
        rtsp = f"rtsp://{ip}/Streaming/Channels/101"

        # Try to read ONVIF device info (optional)
        username = ""
        password = ""

        try:
            cam = ONVIFCamera(ip, 80, username, password)
            dev_info = cam.devicemgmt.GetDeviceInformation()
            model = dev_info.Model
        except:
            model = "Unknown"

        devices.append({
            "address": ip,
            "username": username,
            "password": password,
            "rtsp": rtsp,
            "model": model
        })

    wsd.stop()
    return devices


@app.get("/api/onvifDiscover")
def onvif_discover():
    """
    API endpoint your Qt client calls.
    """
    devices = discover_onvif_devices()
    return JSONResponse({"devices": devices})


# HTTPS server startup
if __name__ == "__main__":
    import uvicorn

    ssl_ctx = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
    ssl_ctx.load_cert_chain("cert.pem", "key.pem")  # your cert + key

    uvicorn.run(
        "onvif_module:app",
        host="0.0.0.0",
        port=7001,
        ssl_context=ssl_ctx
    )
