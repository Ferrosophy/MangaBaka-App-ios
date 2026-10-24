"""Capture public API samples for deterministic simulator checks. No credentials."""
import json
import pathlib
import urllib.request
import urllib.parse

root = pathlib.Path('Sources/Fixtures')
root.mkdir(parents=True, exist_ok=True)
report = []

def capture(path, page=1):
    query = urllib.parse.urlencode({'page': page, 'limit': 30}) if len(path.split('/')) > 3 else ''
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
