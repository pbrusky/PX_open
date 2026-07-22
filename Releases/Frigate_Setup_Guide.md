Frigate + PX Integration Setup Guide
How to prepare your Frigate system for PX Open and the PX Frigate Server Module

This guide explains how to configure your Frigate installation so it works with the PX Frigate Server Module and PX Open Client. Follow these steps on the device where Frigate is installed.

1. Requirements

To use PX Open with Frigate, you must have:

- Frigate installed and running
- go2rtc installed and running
- PX Frigate Server Module running on the same device as Frigate

Frigate can be installed using Docker, Home Assistant, or bare-metal Python.

go2rtc is required because it provides RTSP and WebRTC streams, allows PX Open to test camera streams, and exposes the /api/streams endpoint.

The PX Frigate Server Module must run on the same device as Frigate because it communicates with Frigate containers, restarts Frigate and go2rtc, reads Frigate configuration, performs ONVIF discovery, and exposes HTTP and HTTPS APIs.

2. Install go2rtc

If using Docker, add this to your docker-compose.yml:

go2rtc:
  image: alexxit/go2rtc:latest
  container_name: go2rtc
  restart: unless-stopped
  network_mode: host
  volumes:
    - /etc/go2rtc:/config

Start it with:
docker compose up -d go2rtc

Verify go2rtc is running by opening:
http://your-frigate-ip:1984

3. Install the PX Frigate Server Module

Copy frigate_server.exe to the device running Frigate. Example location:
C:\PX\Server Module\Frigate\

Run the module:
frigate_server.exe

You should see:
[CONFIG] LAN IP: your-ip
HTTP server running on port 8001
HTTPS server running on port 8002

This means the module is active.

4. Network Requirements

PX Open must be able to reach:

PX Frigate Server Module:
- HTTP port 8001
- HTTPS port 8002

Frigate:
- Port 5000

go2rtc:
- Port 1984

PX Open listens for module broadcasts on UDP port 3666.

Make sure your firewall allows:
UDP 3666
TCP 8001
TCP 8002
TCP 5000
TCP 1984

5. Verify Frigate API

Open:
http://your-frigate-ip:5000/api/config

You should see JSON output.

6. Verify go2rtc API

Open:
http://your-frigate-ip:1984/api/streams

You should see a list of streams.

7. Verify PX Frigate Server Module

Open:
http://your-frigate-ip:8001/api/moduleInformation

You should see:
id: frigate
name: Frigate Integration
status: online

If you see this, PX Open will detect the module.

8. Connect PX Open Client

Open PX Open. You should see:
Frigate Integration Module — Online

If not:
- Make sure the module is running
- Make sure UDP 3666 is open
- Make sure PX Open is on the same network
- Make sure the module shows the correct LAN IP

9. Add Cameras in PX Open

PX Open will:
- Discover ONVIF cameras
- Test RTSP streams using go2rtc
- Add cameras to Frigate
- Restart Frigate automatically
- Restart go2rtc if needed

10. Troubleshooting

PX Open does not detect the module:
- Module not running
- Wrong network
- UDP 3666 blocked
- Firewall blocking ports
- Module running on wrong device

Cameras fail RTSP test:
- go2rtc not installed
- Wrong RTSP URL
- Camera requires authentication
- Camera not reachable

Frigate does not show new cameras:
- Frigate config failed to update
- Frigate container name incorrect
- Module cannot restart Frigate
