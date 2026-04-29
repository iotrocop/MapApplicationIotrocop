#!/usr/bin/env python3
"""
IOT Scooter Map Backend Service
Provides telemetry data and tile caching for offline-first map
"""

import json
import os
import random
import threading
from datetime import datetime
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import urlparse, parse_qs
from pathlib import Path

# Configuration
SERVICE_PORT = 8080
SERVICE_HOST = '0.0.0.0'
TILE_CACHE_ROOT = os.path.join(os.path.dirname(__file__), 'tile_cache')

class TelemetryData:
    """Generate random telemetry data for the scooter"""
    request_count = 0  # Track requests for alternating values
    
    @staticmethod
    def generate():
        """Generate random telemetry data with alternating toggle states"""
        TelemetryData.request_count += 1
        
        # Alternate: 1,0,1,0... for reversing and 0,1,0,1... for rotating
        is_reversing = 1 if TelemetryData.request_count % 2 == 1 else 0
        is_rotating = 0 if TelemetryData.request_count % 2 == 1 else 1
        
        return {
            'timestamp': datetime.now().isoformat(),
            'battery_level': random.randint(20, 100),
            'speed': random.randint(0, 50),
            'gps_accuracy': random.choice(['Excellent', 'Good', 'Fair']),
            'accel_front_back': random.randint(-10, 10),  # -10 = back tilt, +10 = front tilt (التوازن)
            'tilt_direction': 'front' if random.choice([True, False]) else 'back',
            'error_level': random.randint(0, 6),  # 0 = no error, 6 = max error
            'is_reversing': is_reversing,  # Alternates: 1,0,1,0... (ريوس)
            'is_rotating': is_rotating,    # Alternates: 0,1,0,1... (دوران)
        }

class MapBackendHandler(BaseHTTPRequestHandler):
    """Handle HTTP requests for telemetry and tiles"""
    
    def do_GET(self):
        """Handle GET requests"""
        parsed_path = urlparse(self.path)
        path = parsed_path.path
        
        # Health check
        if path == '/health':
            self._send_json({'ok': True, 'service': 'map_backend', 'version': '1.0'})
            return
        
        # Telemetry endpoint
        if path == '/telemetry':
            telemetry = TelemetryData.generate()
            self._send_json(telemetry)
            return
        
        # Tile serving (cache or serve from remote)
        if path.startswith('/tiles/'):
            self._handle_tile_request(path)
            return
        
        # Not found
        self._send_json({'error': 'Not found'}, status=404)
    
    def _handle_tile_request(self, path):
        """Handle tile requests: /tiles/style/z/x/y.png"""
        parts = path.strip('/').split('/')
        if len(parts) != 5 or not parts[0] == 'tiles':
            self._send_json({'error': 'Invalid tile path'}, status=400)
            return
        
        style, z, x, y_png = parts[1], parts[2], parts[3], parts[4]
        
        # Remove .png extension
        if not y_png.endswith('.png'):
            self._send_json({'error': 'Invalid tile format'}, status=400)
            return
        
        y = y_png.replace('.png', '')
        
        # Build cache path
        cache_dir = os.path.join(TILE_CACHE_ROOT, style, z, x)
        cache_file = os.path.join(cache_dir, f'{y}.png')
        
        # Try to serve from cache
        if os.path.exists(cache_file):
            try:
                with open(cache_file, 'rb') as f:
                    self._send_file(f.read(), 'image/png')
                return
            except Exception as e:
                print(f'Cache read error: {e}')
        
        # If not in cache, try to fetch from remote source
        tile_content = self._fetch_remote_tile(style, z, x, y)
        if tile_content:
            # Save to cache
            try:
                os.makedirs(cache_dir, exist_ok=True)
                with open(cache_file, 'wb') as f:
                    f.write(tile_content)
            except Exception as e:
                print(f'Cache write error: {e}')
            
            self._send_file(tile_content, 'image/png')
            return
        
        # Serve a blank tile or error placeholder
        self._send_blank_tile()
    
    def _fetch_remote_tile(self, style, z, x, y):
        """Fetch tile from remote source"""
        try:
            import urllib.request
            
            # Map styles to tile sources
            tile_sources = {
                'dark': 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
                'standard': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
                'satellite': 'https://server.arcgisonline.com/ArcGIS/rest/services/World_Imagery/MapServer/tile/{z}/{y}/{x}',
                'terrain': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
            }
            
            if style not in tile_sources:
                return None
            
            url_template = tile_sources[style]
            
            # Handle satellite/arcgis which uses different URL format
            if style == 'satellite':
                url = url_template.format(z=z, x=x, y=y)
            else:
                url = url_template.format(z=z, x=x, y=y)
            
            headers = {
                'User-Agent': 'IOT-Scooter-MapBackend/1.0 (+local)',
            }
            
            req = urllib.request.Request(url, headers=headers)
            response = urllib.request.urlopen(req, timeout=5)
            content = response.read()
            
            if content and len(content) > 100:  # Ensure it's a real tile
                return content
        except Exception as e:
            print(f'Remote tile fetch error for {style}/{z}/{x}/{y}: {e}')
        
        return None
    
    def _send_blank_tile(self):
        """Send a blank/gray tile for missing tiles"""
        # Create a simple gray PNG (1x1 pixel, gray)
        # PNG header + gray pixel data
        gray_png = bytes([
            0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A,  # PNG signature
            0x00, 0x00, 0x00, 0x0D,  # IHDR chunk length
            0x49, 0x48, 0x44, 0x52,  # IHDR
            0x00, 0x00, 0x00, 0x01,  # width = 1
            0x00, 0x00, 0x00, 0x01,  # height = 1
            0x08, 0x02,  # bit depth, color type
            0x00, 0x00, 0x00,  # compression, filter, interlace
            0x90, 0x77, 0x53, 0xDE,  # CRC
            0x00, 0x00, 0x00, 0x0C,  # IDAT chunk length
            0x49, 0x44, 0x41, 0x54,  # IDAT
            0x08, 0x99, 0x01, 0x01, 0x00, 0x00, 0xFE, 0xFF,
            0x00, 0x00, 0x00, 0x02, 0x00, 0x01, 0x33, 0x01,
            0x1E, 0x8F, 0x64, 0xC9,  # CRC (adjusted)
            0x00, 0x00, 0x00, 0x00,  # IEND chunk length
            0x49, 0x45, 0x4E, 0x44,  # IEND
            0xAE, 0x42, 0x60, 0x82,  # CRC
        ])
        self._send_file(gray_png, 'image/png')
    
    def _send_json(self, data, status=200):
        """Send JSON response"""
        self.send_response(status)
        self.send_header('Content-Type', 'application/json')
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(json.dumps(data).encode())
    
    def _send_file(self, content, content_type):
        """Send file response"""
        self.send_response(200)
        self.send_header('Content-Type', content_type)
        self.send_header('Content-Length', str(len(content)))
        self.send_header('Cache-Control', 'public, max-age=604800')  # 1 week cache
        self.send_header('Access-Control-Allow-Origin', '*')
        self.end_headers()
        self.wfile.write(content)
    
    def log_message(self, format, *args):
        """Suppress default logging"""
        # Uncomment for debugging:
        # print(f"[{self.client_address[0]}] {format % args}")
        pass

def main():
    """Start the map backend service"""
    server = ThreadingHTTPServer((SERVICE_HOST, SERVICE_PORT), MapBackendHandler)
    
    print(f"Map backend service listening on http://0.0.0.0:{SERVICE_PORT}")
    print(f"Health check: http://127.0.0.1:{SERVICE_PORT}/health")
    print(f"Telemetry: http://127.0.0.1:{SERVICE_PORT}/telemetry")
    print(f"Tiles: http://127.0.0.1:{SERVICE_PORT}/tiles/dark/13/4088/2728.png")
    print(f"Tile cache root: {TILE_CACHE_ROOT}")
    print("Press Ctrl+C to stop")
    
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        print("\nShutting down...")
        server.shutdown()

if __name__ == '__main__':
    main()
