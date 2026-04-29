# IOT Scooter Application - Raspberry Pi Deployment Guide

## Prerequisites
- Raspberry Pi with Raspbian OS
- Flutter and Dart SDK installed on Raspberry Pi (or cross-compile on Mac)
- Python 3.7+
- Screen or HDMI display connected

## Architecture Overview

### Components
1. **Flutter App** (`lib/main.dart`)
   - Displays offline-first map (Tuyap, Douz - 33.9197°N, 9.0211°E)
   - Shows vehicle telemetry data (battery, speed, acceleration, error status)
   - 6 error indicator circles (green = no error, red = error present)
   - Connects to localhost:8080 for tiles and telemetry

2. **Python Backend Service** (`python_service/map_backend_service.py`)
   - Runs on localhost:8080
   - Provides `/telemetry` endpoint (random data for now, will integrate CAN bus later)
   - Serves map tiles at `/tiles/{style}/{z}/{x}/{y}.png`
   - Caches tiles locally for offline access
   - Supports multiple tile styles: dark, standard, satellite, terrain

## Deployment Steps

### 1. Prepare Raspberry Pi

```bash
# SSH into Raspberry Pi
ssh pi@<raspberry-pi-ip>

# Update system
sudo apt-get update && sudo apt-get upgrade -y

# Install Python dependencies
sudo apt-get install -y python3 python3-pip

# Install Flutter (if not already installed)
# See https://docs.flutter.dev/get-started/install/linux
```

### 2. Transfer Application

From your Mac workstation:

```bash
# Create directory structure on Raspberry Pi
ssh pi@<raspberry-pi-ip> "mkdir -p /home/pi/iot-scooter/{app,python_service}"

# Transfer Flutter app
scp -r lib pubspec.yaml analysis_options.yaml LICENSE README.md \
  pi@<raspberry-pi-ip>:/home/pi/iot-scooter/app/

# Transfer Python service
scp python_service/map_backend_service.py \
  pi@<raspberry-pi-ip>:/home/pi/iot-scooter/python_service/

# Transfer download_tiles.py (for future tile cache prepopulation)
scp python_service/download_tiles.py \
  pi@<raspberry-pi-ip>:/home/pi/iot-scooter/python_service/
```

### 3. Build Flutter App for Raspberry Pi

```bash
# On Raspberry Pi
cd /home/pi/iot-scooter/app

# Get dependencies
flutter pub get

# Build the Linux executable for Raspberry Pi
flutter build linux --release
```

### 4. Create systemd Services

#### Python Backend Service

Create `/etc/systemd/system/iot-map-backend.service`:

```ini
[Unit]
Description=IOT Scooter Map Backend Service
After=network.target

[Service]
Type=simple
User=pi
WorkingDirectory=/home/pi/iot-scooter/python_service
ExecStart=/usr/bin/python3 /home/pi/iot-scooter/python_service/map_backend_service.py
Restart=on-failure
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:

```bash
sudo systemctl daemon-reload
sudo systemctl enable iot-map-backend.service
sudo systemctl start iot-map-backend.service
sudo systemctl status iot-map-backend.service
```

#### Flutter App Service (Linux executable)

Create `/etc/systemd/system/iot-app.service`:

```ini
[Unit]
Description=IOT Scooter Flutter App
After=iot-map-backend.service
Requires=iot-map-backend.service

[Service]
Type=simple
User=pi
Environment="DISPLAY=:0"
Environment="XDG_RUNTIME_DIR=/run/user/1000"
ExecStart=/home/pi/iot-scooter/app/build/linux/arm64/release/bundle/map_application
Restart=on-failure
RestartSec=5

[Install]
WantedBy=multi-user.target
```

### 5. Test Deployment

```bash
# Test Python service
curl http://127.0.0.1:8080/health
curl http://127.0.0.1:8080/telemetry | json_pp

# View service logs
sudo journalctl -u iot-map-backend.service -f
sudo journalctl -u iot-app.service -f

# Manual service start for debugging
cd /home/pi/iot-scooter/python_service
python3 map_backend_service.py
```

## Offline Map Support

### Option A: Pre-populate Tile Cache (Recommended)

**On your Mac workstation:**

```bash
cd /Users/mackbook/Projects/MapApplicationIotrocop/python_service

# Download tiles for the area
python3 download_tiles.py \
  --url-template "https://{s}.tile.openstreetmap.org/{z}/{x}/{y}.png" \
  --subdomains "a,b,c" \
  --style dark \
  --min-zoom 10 --max-zoom 15 \
  --min-lat 33.70 --min-lon 8.70 --max-lat 34.20 --max-lon 9.50 \
  --concurrency 8

# Optional: Create tarball for transfer
tar czf tile_cache_douz.tar.gz tile_cache/

# Transfer to Raspberry Pi
scp tile_cache_douz.tar.gz pi@<raspberry-pi-ip>:/home/pi/iot-scooter/python_service/
ssh pi@<raspberry-pi-ip> "cd /home/pi/iot-scooter/python_service && tar xzf tile_cache_douz.tar.gz"
```

**Or use rsync for continuous sync:**

```bash
rsync -av --progress python_service/tile_cache/ \
  pi@<raspberry-pi-ip>:/home/pi/iot-scooter/python_service/tile_cache/
```

### Option B: On-Demand Caching

The Python service will automatically:
1. Check local cache for requested tile
2. If not cached, fetch from remote source (requires WiFi)
3. Save to local cache for future offline access

## First Run Scenario (Offline from Start)

1. **Ensure tiles are cached** (use Option A above)
2. **Turn off WiFi on Raspberry Pi**
3. **Power on the app**
4. **Expected behavior:**
   - Default location: Tuyap, Douz
   - Map displays cached tiles offline
   - Telemetry shows random data (from Python service)
   - 6 error circles visible in top-left (green if no error, red if error present)
   - Speed and vehicle stats visible in HUD

## CAN Bus Integration (Future)

The current telemetry endpoint generates random data. To integrate real CAN bus data:

1. Modify `python_service/map_backend_service.py`:
   - Replace `TelemetryData.generate()` with actual CAN bus reading
   - Use `python-can` library to read from CAN interface

Example:
```python
import can

bus = can.interface.Bus(channel='can0', bustype='socketcan')

@staticmethod
def generate():
    msg = bus.recv(timeout=0.1)
    if msg:
        return {
            'battery_level': parse_battery(msg),
            'speed': parse_speed(msg),
            'error_level': parse_error(msg),
            ...
        }
```

## Troubleshooting

### App doesn't connect to Python service
```bash
# Check if service is running
curl http://127.0.0.1:8080/health

# Check firewall
sudo ufw status

# Restart service
sudo systemctl restart iot-map-backend.service
```

### Tiles not displaying
```bash
# Check tile cache directory exists
ls -la /home/pi/iot-scooter/python_service/tile_cache/

# Manually download tiles
cd /home/pi/iot-scooter/python_service
python3 download_tiles.py --style dark ...

# Check service logs
sudo journalctl -u iot-map-backend.service -f
```

### Flutter app crashes
```bash
# Run with flutter logs
flutter logs

# Or check systemd logs
sudo journalctl -u iot-app.service -f
```

## File Locations Reference

```
/home/pi/iot-scooter/
├── app/
│   ├── lib/
│   │   └── main.dart
│   ├── pubspec.yaml
│   └── build/
│       └── linux/arm64/release/bundle/map_application  (after flutter build linux --release)
├── python_service/
│   ├── map_backend_service.py
│   ├── download_tiles.py
│   └── tile_cache/
│       └── dark/
│           └── {z}/{x}/{y}.png
└── logs/
```

## Additional Notes

- Default location (Tuyap, Douz): 33.9197°N, 9.0211°E
- Error levels: 0-6 (0 = no error, 6 = critical error)
- Acceleration: -10 (tilted back) to +10 (tilted forward)
- Battery, speed, and other telemetry update every 2 seconds
- All network requests timeout after 800ms (uses local fallback if timeout)
