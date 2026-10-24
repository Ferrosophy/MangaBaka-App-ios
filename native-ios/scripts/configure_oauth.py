"""Inject a registered public OAuth client. Never accepts client secrets."""
import os, urllib.parse, yaml
from pathlib import Path
p = Path('project.yml')
d = yaml.safe_load(p.read_text())
settings = d['targets']['MangaBakaNative']['settings']['base']
client = os.environ.get('MANGABAKA_CLIENT_ID', '').strip()
redirect = os.environ.get('MANGABAKA_REDIRECT_URI', '').strip()
if client or redirect:
    uri = urllib.parse.urlparse(redirect)
    if not client or not uri.scheme or uri.scheme in ('http', 'https') or not uri.netloc or uri.query or uri.fragment:
        raise SystemExit('Supply both a registered public client ID and a custom-scheme redirect URI.')
    settings['MANGABAKA_CLIENT_ID'] = client
    settings['MANGABAKA_REDIRECT_URI'] = redirect
    settings['MANGABAKA_CALLBACK_SCHEME'] = uri.scheme
    p.write_text(yaml.safe_dump(d, sort_keys=False))
    print('Registered OAuth configuration supplied. Real login still requires device verification.')
else:
    print('OAuth configuration missing: build is a review preview; account login is unavailable.')
