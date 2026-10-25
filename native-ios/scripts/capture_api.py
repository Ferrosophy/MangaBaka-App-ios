"""Capture public API samples for deterministic simulator checks. No credentials."""
import json
import pathlib
import urllib.request
import urllib.parse

root = pathlib.Path('Sources/Fixtures')
root.mkdir(parents=True, exist_ok=True)
report = []

def capture(path, page=1):
    if path.endswith('/similar'):
        params = {'limit': 20}
    elif path.endswith('/readers-also-like'):
        params = {'limit': 24}
    elif path.endswith(('/images', '/relationships', '/works', '/collections')):
        params = {'page': page, 'limit': 30}
    else:
        params = {}
    query = urllib.parse.urlencode(params)
    request = urllib.request.Request('https://api.mangabaka.org/' + path + ('?' + query if query else ''), headers={'User-Agent': 'MangaBakaNative-M2-validation/0.2'})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
        if not isinstance(payload, dict) or 'data' not in payload:
            raise ValueError('missing data envelope')
        (root / (path.replace('/', '-') + f'-{page}.json')).write_text(json.dumps(payload, ensure_ascii=False))
        report.append({'path': path, 'page': page, 'ok': True, 'items': len(payload['data']) if isinstance(payload['data'], list) else 1})
        return payload
    except Exception as error:
        report.append({'path': path, 'page': page, 'ok': False, 'error': str(error)})
        return None

series = capture('v1/series/1677')
for resource in ['links', 'images', 'relationships', 'similar', 'news', 'collections', 'works']:
    payload = capture('v1/series/1677/' + resource)
    if payload and resource == 'collections' and payload.get('data'):
        capture('v1/collections/' + str(payload['data'][0]['id']) + '/works')
capture('v2/series/1677/readers-also-like')
capture('v1/tags')
pathlib.Path('api-validation.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))
if series:
    data = series.get('data', {})
    print('SERIES_SHAPE', json.dumps({k: data.get(k) for k in ['native_title', 'anime', 'published', 'authors', 'tags']}, ensure_ascii=False)[:6000])
if not series:
    raise SystemExit('Core series API could not be captured; see api-validation.json')

# M4 public endpoints; report independently from authenticated account checks.
for endpoint, params in [
    ('v2/series/search', {'limit': 3, 'schema': 'full', 'sort_by': 'popularity_asc', 'type': 'manga'}),
    ('v2/news', {'limit': 2}),
    ('v2/series/mix', {'series': 1677, 'strict': 'false', 'limit': 3}),
    ('v1/series/mix/seeds', {'series': [1677, 1078]}),
    ('v1/tags', {'is_genre': 'true', 'limit': 100}),
]:
    try:
        url = 'https://api.mangabaka.org/' + endpoint + '?' + urllib.parse.urlencode(params, doseq=True)
        request = urllib.request.Request(url, headers={'User-Agent': 'MangaBakaNative-M4/0.4'})
        with urllib.request.urlopen(request, timeout=30) as response:
            payload = json.load(response)
        if not isinstance(payload, dict) or not isinstance(payload.get('data'), list):
            raise ValueError('missing list envelope')
        (root / ('m4-' + endpoint.replace('/', '-') + '.json')).write_text(json.dumps(payload, ensure_ascii=False))
        report.append({'path': endpoint, 'ok': True, 'items': len(payload['data'])})
    except Exception as error:
        report.append({'path': endpoint, 'ok': False, 'error': str(error)})
pathlib.Path('api-validation.json').write_text(json.dumps(report, indent=2))
print(json.dumps(report, indent=2))


# Bitmap aspect ratios intentionally differ to exercise fill/clipping on simulator.
import zlib, struct
for name, width, height, color in [('portrait', 80, 160, (35, 140, 90)), ('landscape', 180, 80, (90, 100, 210)), ('square', 100, 100, (220, 140, 40))]:
    def chunk(kind, data):
        return struct.pack('!I', len(data)) + kind + data + struct.pack('!I', zlib.crc32(kind + data) & 0xffffffff)
    pixels = b''.join(b'\x00' + bytes(color) * width for _ in range(height))
    image = b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', struct.pack('!2I5B', width, height, 8, 2, 0, 0, 0)) + chunk(b'IDAT', zlib.compress(pixels)) + chunk(b'IEND', b'')
    (root / ('layout-' + name + '.png')).write_bytes(image)
