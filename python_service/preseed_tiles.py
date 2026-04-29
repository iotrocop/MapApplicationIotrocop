#!/usr/bin/env python3
"""
Tile Pre-seeder Script
Pre-loads map tiles for Tuyap area (33.9197, 9.0211) to enable offline-first functionality
Run this ONCE before starting the service: python3 preseed_tiles.py
"""

import os
import urllib.request
import time
from pathlib import Path
import math

# Configuration
TILE_CACHE_ROOT = os.path.join(os.path.dirname(__file__), 'tile_cache')
TARGET_LAT = 33.9197  # Tuyap, Douz
TARGET_LNG = 9.0211

def lat_lng_to_tile(lat, lng, zoom):
    """Convert latitude/longitude to tile coordinates"""
    n = 2 ** zoom
    x = int((lng + 180) / 360 * n)
    y = int((1 - math.log(math.tan(math.radians(lat)) + 1 / math.cos(math.radians(lat))) / math.pi) / 2 * n)
    return x, y

def preseed_tiles(zoom_levels=[10, 11, 12, 13]):
    """Pre-load tiles for the target location at multiple zoom levels"""
    
    tile_sources = {
        'dark': 'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
        'standard': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
        'terrain': 'https://tile.opentopomap.org/{z}/{x}/{y}.png',
    }
    
    headers = {'User-Agent': 'IOT-Scooter-PreSeeder/1.0'}
    total_tiles = 0
    
    for style, url_template in tile_sources.items():
        print(f"\n🌍 Pre-seeding '{style}' style tiles...")
        style_count = 0
        
        for zoom in zoom_levels:
            # Get the center tile for this zoom level
            center_x, center_y = lat_lng_to_tile(TARGET_LAT, TARGET_LNG, zoom)
            
            # Also grab surrounding tiles (3x3 grid around center)
            tiles_to_fetch = []
            for dx in [-1, 0, 1]:
                for dy in [-1, 0, 1]:
                    tiles_to_fetch.append((center_x + dx, center_y + dy, zoom))
            
            for x, y, z in tiles_to_fetch:
                url = url_template.format(z=z, x=x, y=y)
                cache_dir = os.path.join(TILE_CACHE_ROOT, style, str(z), str(x))
                cache_file = os.path.join(cache_dir, f'{y}.png')
                
                # Skip if already cached
                if os.path.exists(cache_file):
                    continue
                
                try:
                    os.makedirs(cache_dir, exist_ok=True)
                    req = urllib.request.Request(url, headers=headers)
                    response = urllib.request.urlopen(req, timeout=5)
                    content = response.read()
                    
                    if content and len(content) > 100:
                        with open(cache_file, 'wb') as f:
                            f.write(content)
                        style_count += 1
                        total_tiles += 1
                        print(f"  ✓ {style} z{z}: ({x},{y})")
                        time.sleep(0.2)  # Rate limiting
                    
                except Exception as e:
                    print(f"  ⚠ Failed to fetch {style} z{z}: {e}")
        
        print(f"  ➜ Cached {style_count} tiles for '{style}'")
    
    print(f"\n✅ Pre-seeding complete! Total tiles cached: {total_tiles}")
    print(f"📁 Cache location: {TILE_CACHE_ROOT}")

if __name__ == '__main__':
    print("=" * 60)
    print("IOT Scooter Map - Tile Pre-Seeder")
    print("=" * 60)
    print(f"Target: Tuyap, Douz ({TARGET_LAT}°N, {TARGET_LNG}°E)")
    print(f"Zoom levels: 10-13 (3x3 grid at each level)")
    print("=" * 60)
    
    preseed_tiles()
    print("\n🚀 Ready for offline-first operation!")
