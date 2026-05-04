#!/usr/bin/env python3

import json
import os
import threading
import time
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse

SERVICE_PORT = 8080
SERVICE_HOST = '0.0.0.0'
TILE_CACHE_ROOT = os.path.join(os.path.dirname(__file__), 'tile_cache')

# Environment toggle and guarded hardware imports so the server
# can run on macOS (or other systems) without python-can/gpiod.
DISABLE_HW = os.environ.get('DISABLE_HW', '0') in ('1', 'true', 'True')
CAN_AVAILABLE = False
GPIO_AVAILABLE = False

try:
    if not DISABLE_HW:
        import can  # type: ignore
        CAN_AVAILABLE = True
except Exception:
    can = None  # type: ignore

try:
    if not DISABLE_HW:
        import gpiod  # type: ignore
        GPIO_AVAILABLE = True
except Exception:
    gpiod = None  # type: ignore

CHANNEL   = 'can0'
BITRATE   = 250000
STM32_ID  = 0x400

GPIO_CHIP = '/dev/gpiochip0'
BTN1_PIN  = 4
BTN2_PIN  = 5

can_state = {
    'timestamp':        None,
    'battery_level':    0,
    'speed':            0,
    'voltage':          0,
    'current':          0,
    'accel_front_back': 0,
    'tilt_direction':   'front',
    'error_level':      0,
    'is_reversing':     0,
    'is_rotating':      0,
    'gps_accuracy':     'Good',
    'btn1':             0,
    'btn2':             0,
}
can_lock = threading.Lock()


def parse_stm32(data: bytes):
    voltage = (data[0] << 8) | data[1]
    current = (data[2] << 8) | data[3]
    gaz     = data[4]
    soc     = data[5]
    hata_id = data[6]
    egim    = data[7] if data[7] < 128 else data[7] - 256

    with can_lock:
        can_state['timestamp']        = datetime.now().isoformat()
        can_state['voltage']          = voltage
        can_state['current']          = current
        can_state['speed']            = gaz
        can_state['battery_level']    = soc
        can_state['error_level']      = hata_id
        can_state['accel_front_back'] = egim
        can_state['tilt_direction']   = 'front' if egim >= 0 else 'back'
        can_state['is_reversing']     = 0
        can_state['is_rotating']      = 0


def can_listener_thread():
    try:
        os.system(f'sudo ip link set {CHANNEL} down')
        os.system(f'sudo ip link set {CHANNEL} up type can bitrate {BITRATE}')

        try:
            bus = can.Bus(channel=CHANNEL, interface='socketcan')
        except AttributeError:
            bus = can.interface.Bus(channel=CHANNEL, bustype='socketcan')

        print(f"CAN bus {CHANNEL} başlatıldı")

        while True:
            msg = bus.recv(timeout=1.0)
            if msg and msg.arbitration_id == STM32_ID and msg.dlc == 8:
                parse_stm32(msg.data)

    except Exception as e:
        print(f"CAN thread hatası: {e}")


def gpio_listener_thread():
    try:
        request = gpiod.request_lines(
            GPIO_CHIP,
            consumer='map_backend',
            config={
                (BTN1_PIN, BTN2_PIN): gpiod.LineSettings(
                    direction=gpiod.line.Direction.INPUT
                )
            }
        )
        print("GPIO başlatıldı")

        while True:
            b1 = request.get_value(BTN1_PIN)
            b2 = request.get_value(BTN2_PIN)

            with can_lock:
                can_state['btn1'] = 1 if b1 == gpiod.line.Value.ACTIVE else 0
                can_state['btn2'] = 1 if b2 == gpiod.line.Value.ACTIVE else 0

            time.sleep(0.05)

    except Exception as e:
        print(f"GPIO thread hatası: {e}")


class MapBackendHandler(BaseHTTPRequestHandler):

    def do_GET(self):
        parsed_path = urlparse(self.path)
        path = parsed_path.path

        if path == '/health':
            self._send_json({'ok': True, 'service': 'map_backend', 'version': '1.0'})
            return

        if path == '/telemetry':
            with can_lock:
                data = dict(can_state)
            if data['timestamp'] is None:
                data['timestamp'] = datetime.now().isoformat()
            self._send_json(data)
            return

        if path.startswith('/tiles/'):
            self._handle_tile_request(path)
            return

        self._send_json({'error': 'Not found'}, status=404)

    def _handle_tile_request(self, path):
        parts = path.strip('/').split('/')
        if len(parts) != 5:
            self._send_json({'error': 'Invalid tile path'}, status=400)
            return

        style, z, x, y_png = parts[1], parts[2], parts[3], parts[4]
        if not y_png.endswith('.png'):
            self._send_json({'error': 'Invalid tile format'}, status=400)
            return

        y = y_png.replace('.png', '')
        cache_dir  = os.path.join(TILE_CACHE_ROOT, style, z, x)
        cache_file = os.path.join(cache_dir, f'{y}.png')

        if os.path.exists(cache_file):
            try:
                with open(cache_file, 'rb') as f:
                    self._send_file(f.read(), 'image/png')
                return
            except Exception as e:
                print(f'Cache read error: {e}')

        tile_content = self._fetch_remote_tile(style, z, x, y)
        if tile_content:
            try:
                os.makedirs(cache_dir, exist_ok=True)
                with open(cache_file, 'wb') as f:
                    f.write(tile_content)
            except Exception as e:
                print(f'Cache write error: {e}')
            self._send_file(tile_content, 'image/png')
            return

        self._send_blank_tile()

    def _fetch_remote_tile(self, style, z, x, y):
        try:
            import urllib.request
            tile_sources = {
                'dark':      'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                'standard':  'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                'satellite': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                'terrain':   'https://tile.opentopomap.org/{z}/{x}/{y}.png',
            }
            if style not in tile_sources:
                return None
            url = tile_sources[style].format(z=z, x=x, y=y)
            req = urllib.request.Request(url, headers={'User-Agent': 'IOT-Scooter-MapBackend/1.0'})
            response = urllib.request.urlopen(req, timeout=5)
            content = response.read()
            return content if content and len(content) > 100 else None
        except Exception as e:
            print(f'Remote tile fetch error: {e}')
            return None

    def _send_blank_tile(self):
        gray_png = bytes([
            0x89,0x50,0x4E,0x47,0x0D,0x0A,0x1A,0x0A,
            0x00,0x00,0x00,0x0D,0x49,0x48,0x44,0x52,
            0x00,0x00,0x00,0x01,0x00,0x00,0x00,0x01,
            0x08,0x02,0x00,0x00,0x00,0x90,0x77,0x53,0xDE,
            0x00,0x00,0x00,0x0C,0x49,0x44,0x41,0x54,
            0x08,0x99,0x01,0x01,0x00,0x00,0xFE,0xFF,
            0x00,0x00,0x00,0x02,0x00,0x01,0x33,0x01,
            0x1E,0x8F,0x64,0xC9,
            0x00,0x00,0x00,0x00,0x49,0x45,0x4E,0x44,0xAE,0x42,0x60,0x82,
        ])
        self._send_file(gray_png, 'image/png')

    def _send_json(self, data, status=200):
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())

    def _send_file(self, content, content_type):
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(content)))
        self.send_header('Cache-Control', 'public, max-age=604800')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(content)

    def log_message(self, format, *args):
        pass


def main():
    # Start CAN listener only if available and not disabled
    if not DISABLE_HW and CAN_AVAILABLE:
        t_can = threading.Thread(target=can_listener_thread, daemon=True)
        t_can.start()
        print("CAN listener started")
    else:
        print("CAN listener not started (disabled or not available)")

    # Start GPIO listener only if available and not disabled
    if not DISABLE_HW and GPIO_AVAILABLE:
        t_gpio = threading.Thread(target=gpio_listener_thread, daemon=True)
        t_gpio.start()
        print("GPIO listener started")
    else:
        print("GPIO listener not started (disabled or not available)")

    server = ThreadingHTTPServer((SERVICE_HOST, SERVICE_PORT), MapBackendHandler)
    print(f"Map backend: http://0.0.0.0:{SERVICE_PORT}")
    print(f"Telemetry  : http://127.0.0.1:{SERVICE_PORT}/telemetry")

    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()


if __name__ == '__main__':
    main()
