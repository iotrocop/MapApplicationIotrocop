import os, urllib.request, time, math

TILE_CACHE_ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), 'tile_cache')

TARGET_LAT = 41.0364
TARGET_LNG = 28.9849

def lat_lng_to_tile(lat, lng, zoom):
    n = 2 ** zoom
    x = int((lng + 180) / 360 * n)
    y = int((1 - math.log(math.tan(math.radians(lat)) + 1/math.cos(math.radians(lat))) / math.pi) / 2 * n)
    return x, y

tile_sources = {
    'dark':     'https://basemaps.cartocdn.com/dark_all/{z}/{x}/{y}.png',
    'standard': 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
    'terrain':  'https://tile.opentopomap.org/{z}/{x}/{y}.png',
}

zoom_config = {
    10: 3,
    11: 4,
    12: 5,
    13: 6,
    14: 7,
    15: 8,
    16: 10,
    17: 12,
    18: 14,
}

headers = {'User-Agent': 'IOT-Scooter/1.0'}
total = 0

print("Istanbul tile downloader - started")
print(f"Cache: {TILE_CACHE_ROOT}\n")

for style, url_tmpl in tile_sources.items():
    print(f"=== {style} ===")
    c = 0
    for zoom, radius in zoom_config.items():
        cx, cy = lat_lng_to_tile(TARGET_LAT, TARGET_LNG, zoom)
        grid = (radius*2+1)**2
        print(f"  zoom {zoom}: {grid} tiles to check...")
        for dx in range(-radius, radius+1):
            for dy in range(-radius, radius+1):
                x, y, z = cx+dx, cy+dy, zoom
                d = os.path.join(TILE_CACHE_ROOT, style, str(z), str(x))
                f = os.path.join(d, f'{y}.png')
                if os.path.exists(f):
                    continue
                try:
                    os.makedirs(d, exist_ok=True)
                    req = urllib.request.Request(
                        url_tmpl.format(z=z, x=x, y=y),
                        headers=headers
                    )
                    content = urllib.request.urlopen(req, timeout=10).read()
                    if content and len(content) > 100:
                        open(f, 'wb').write(content)
                        c += 1
                        total += 1
                        if c % 50 == 0:
                            print(f"    {c} tiles downloaded so far...")
                        time.sleep(0.1)
                except Exception as e:
                    pass
    print(f"  {style} done: {c} tiles\n")

print(f"FINISHED - Total: {total} tiles")
print(f"Size: {TILE_CACHE_ROOT}")
os.system(f"du -sh {TILE_CACHE_ROOT}")