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
