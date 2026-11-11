"""The production proxy in front of the core secret path.

Caddy 2.11.4 built with the plugins docker/variants/caddy.dockerfile pins,
running etc/examples/Caddyfile-example unmodified. Usage:
  suite_proxy.py <run-id> [label]
Needs results/core-<label>-fixtures.json from suite_core (an account + token).
"""
import gzip
import json
import re
import subprocess
import sys
import time
import uuid

import stg

RUN = sys.argv[1] if len(sys.argv) > 1 else str(int(time.time()))
LABEL = sys.argv[2] if len(sys.argv) > 2 else 'head'
L = stg.Ledger(f'proxy-{LABEL}')
FX = json.load(open(stg.RESULTS + f'/core-{LABEL}-fixtures.json'))
V2 = stg.BASE + '/api/v2'
APP_LOG = stg.ROOT + '/logs/head-web.log' if not LABEL.startswith('v19') else None
CADDY_LOG = stg.ROOT + '/logs/caddy.log'


def curl(*args, source=None, resolve=None):
    """Raw response: (status, [(name, value)...], body bytes)."""
    cmd = ['curl', '-sS', '--noproxy', '*', '--cacert', stg.CA, '-D', '-', '-o', '/dev/stderr', '-m', '30']
    if source:
        cmd += ['--interface', source]
    if resolve:
        cmd += ['--resolve', resolve]
    cmd += list(args)
    p = subprocess.run(cmd, capture_output=True, env={'PATH': '/usr/bin:/bin', 'HOME': '/root'})
    head = p.stdout.decode('latin-1')
    blocks = [b for b in head.split('\r\n\r\n') if b.strip()]
    last = blocks[-1] if blocks else ''
    lines = last.split('\r\n')
    status = int(lines[0].split()[1]) if lines and lines[0].startswith('HTTP') else 0
    headers = [tuple(x.split(': ', 1)) if ': ' in x else (x.rstrip(':'), '') for x in lines[1:] if x]
    return status, headers, p.stderr


def hv(headers, name):
    return [v for k, v in headers if k.lower() == name.lower()]


def app_log_line(needle, timeout=8):
    if not APP_LOG:
        return None
    deadline = time.time() + timeout
    while time.time() < deadline:
        out = subprocess.run(['grep', '-a', needle, APP_LOG], capture_output=True, text=True).stdout
        if out:
            return out
        time.sleep(0.5)
    return ''


def tok(n=62):
    return (uuid.uuid4().hex + uuid.uuid4().hex)[:n]


# ----------------------------------------------------------------- P01 TLS
s, h, _ = curl('--tlsv1.3', V2 + '/status')
s12 = subprocess.run(['curl', '-s', '--noproxy', '*', '--cacert', stg.CA, '--tls-max', '1.2', '-o', '/dev/null', '-w', '%{http_code}',
                      V2 + '/status'], capture_output=True, text=True)
ver = subprocess.run(['curl', '-s', '--noproxy', '*', '--cacert', stg.CA, '-o', '/dev/null', '-w', '%{http_version} %{ssl_verify_result}',
                      V2 + '/status'], capture_output=True, text=True).stdout
L.check('P01a', 'TLS 1.3 handshake with the staged certificate verifies; HTTP/2 negotiated', s == 200 and ver.startswith('2 0'), (s, ver))
L.check('P01b', 'TLS 1.2 is refused', s12.returncode != 0, (s12.returncode, s12.stdout))
s, h, _ = curl('--http1.1', V2 + '/status')
L.check('P01c', 'HTTP/1.1 clients are served too', s == 200, s)
s, h, _ = curl('http://secrets.staging.test/api/v2/status')
L.check('P01d', 'plain HTTP is redirected to HTTPS, not served', s in (301, 308) and hv(h, 'location') == ['https://secrets.staging.test/api/v2/status'],
        (s, hv(h, 'location')))

# ------------------------------------------------------- P02 header hygiene
single = ['referrer-policy', 'x-content-type-options', 'x-frame-options', 'cache-control', 'x-request-id',
          'o-request-id', 'strict-transport-security', 'content-security-policy', 'content-type', 'permissions-policy',
          'x-xss-protection', 'pragma']
dups = {}
seen = {}
for label, args in (('api json', [V2 + '/status']), ('api 404', [V2 + '/secret/' + tok() + '/status']),
                    ('html', ['-H', 'Accept: text/html', stg.BASE + '/']),
                    ('api 400', ['-X', 'POST', '-H', 'Content-Type: application/json', '-d', '{', V2 + '/secret/conceal'])):
    s, h, _ = curl(*args)
    seen[label] = {n: hv(h, n) for n in single if hv(h, n)}
    for n in single:
        if len(hv(h, n)) > 1:
            dups[f'{label}:{n}'] = hv(h, n)
L.check('P02a', 'no security or cache header is duplicated between app and proxy', not dups, dups)
L.check('P02b', 'every API response through the proxy is no-store',
        all('no-store' in ','.join(seen[k].get('cache-control', [])) for k in ('api json', 'api 404', 'api 400')),
        {k: seen[k].get('cache-control') for k in seen})
L.check('P02c', 'no Server / X-Powered-By header leaks', not any(hv(h, 'server') or hv(h, 'x-powered-by') for h in [h]), hv(h, 'server'))
L.note('P02d', 'headers as delivered (api json)', seen['api json'])

# --------------------------------------------------------- P03 request IDs
fake = tok()
s, h, body = curl('-H', 'X-Request-ID: client-chosen-id', V2 + f'/secret/{fake}/status')
rid = hv(h, 'x-request-id')
oid = hv(h, 'o-request-id')
L.check('P03a', 'one X-Request-ID, a proxy UUID equal to O-Request-ID; the client-supplied value is replaced',
        len(rid) == 1 and rid == oid and re.fullmatch(r'[0-9a-f-]{36}', rid[0] or '') and rid[0] != 'client-chosen-id', (rid, oid))
s, h, body = curl('-X', 'POST', '-H', 'Content-Type: application/json', '-d', '{"continue":true}', V2 + f'/secret/{fake}/reveal')
rid = hv(h, 'x-request-id')
try:
    body_id = json.loads(body).get('request_id')
except ValueError:
    body_id = None
L.check('P03b', "the app's error body carries the same request id as the response header",
        s == 404 and rid and body_id == rid[0], (s, body_id, rid))
line = app_log_line(rid[0]) if rid else ''
L.check('P03c', 'and the app log has that id for the request', APP_LOG is None or bool(line), bool(line))

# ----------------------------------------------------------- P04 client IP
m1 = tok()
curl(V2 + f'/secret/{m1}/status', source='198.51.100.12')
line = app_log_line(m1) or ''
L.check('P04a', "app resolves the proxied client's address, not the proxy's (log shows the masked client /24)",
        APP_LOG is None or ('198.51.100.0' in line and '127.0.0.0' not in line), re.findall(r'ip: "[^"]+"', line)[:2])
m2 = tok()
curl('-H', 'X-Forwarded-For: 8.8.8.8', '-H', 'X-Real-IP: 8.8.4.4', V2 + f'/secret/{m2}/status', source='192.0.2.12')
line = app_log_line(m2) or ''
L.check('P04b', 'a forged X-Forwarded-For / X-Real-IP from a public client is discarded',
        APP_LOG is None or ('192.0.2.0' in line and '8.8.' not in line), re.findall(r'ip: "[^"]+"', line)[:2])
m3 = tok()
curl('-H', 'X-Forwarded-For: 198.51.100.77', V2 + f'/secret/{m3}/status', source='127.0.0.1',
     resolve='secrets.staging.test:443:127.0.0.1')
line = app_log_line(m3) or ''
L.note('P04c', "from a private-range peer (the Caddyfile trusts private_ranges) the forwarded address is taken as the client",
       re.findall(r'ip: "[^"]+"', line)[:2])
anon = stg.session('192.0.2.13')
before = set(stg.redis_keys('create_secret:attempts:ip:*'))
r = anon.post(V2 + '/guest/secret/conceal', json=stg.conceal_body('ip keyed', 3600))
keys = set(stg.redis_keys('create_secret:attempts:ip:*'))
L.check('P04d', "the anonymous-creation limiter is keyed on the client's masked network, not the proxy's",
        r.status_code == 200 and 'create_secret:attempts:ip:192.0.2.0' in keys and not any('127.0.0' in k for k in keys), sorted(keys))

# -------------------------------------------------- P05 public host / scheme
s, h, body = curl('-H', 'X-Forwarded-Host: evil.example', '-H', 'X-Forwarded-Proto: http', '-H', 'X-Forwarded-Port: 8443',
                  '-H', 'Forwarded: host=evil.example;proto=http', '-u', f"{FX['a_email']}:{FX['a_token']}",
                  '-X', 'POST', '-d', 'secret=host+check&ttl=3600', stg.BASE + '/api/v1/share')
try:
    d = json.loads(body)
except ValueError:
    d = {}
L.check('P05a', 'client-supplied forwarded host/proto/port do not change the display domain or generated URLs',
        s == 200 and hv(h, 'o-display-domain') == ['secrets.staging.test']
        and str(d.get('metadata_url', '')).startswith('https://secrets.staging.test/'),
        (s, hv(h, 'o-display-domain'), d.get('metadata_url', '')[:60]))
s, h, body = curl('-H', 'Host: evil.example', V2 + '/status')
L.check('P05b', 'a request for another Host never reaches the app (Caddy answers it empty itself)',
        not body and not hv(h, 'o-display-domain') and not hv(h, 'x-request-id'), (s, len(body), hv(h, 'o-display-domain')))

# ------------------------------------------------------ P06 bodies/encoding
api = stg.api_client(FX['a_email'], FX['a_token'], '198.51.100.13')
s, h, body = curl('-H', 'Accept-Encoding: gzip', '-u', f"{FX['a_email']}:{FX['a_token']}", V2 + '/receipt/recent')
enc = hv(h, 'content-encoding')
try:
    decoded = json.loads(gzip.decompress(body)) if enc == ['gzip'] else json.loads(body)
except Exception as ex:  # noqa: BLE001
    decoded = repr(ex)
L.check('P06a', 'a large JSON response is compressed by the proxy and decodes to the same JSON',
        s == 200 and enc == ['gzip'] and isinstance(decoded, dict) and 'records' in decoded, (s, enc, type(decoded).__name__))
s, h, body = curl('-u', f"{FX['a_email']}:{FX['a_token']}", '-H', 'Content-Type: application/json', '-H', 'Transfer-Encoding: chunked',
                  '-H', 'Expect: 100-continue', '--http1.1', '-d', json.dumps(stg.conceal_body('chunked body', 3600)), V2 + '/secret/conceal')
try:
    d = json.loads(body)
    sid = d['record']['secret']['identifier']
except Exception:  # noqa: BLE001
    sid = None
rr = stg.session('198.51.100.14').post(f'{V2}/secret/{sid}/reveal', json={'continue': True}) if sid else None
L.check('P06b', 'a chunked request body with Expect: 100-continue creates a secret that reveals intact',
        s == 200 and rr is not None and rr.status_code == 200 and rr.json()['record'].get('secret_value') == 'chunked body', s)
sizes = {}
for n in (1_000, 10_000, 100_000, 1_000_000, 5_000_000):
    value = ('0123456789abcdef' * (n // 16 + 1))[:n]
    rp = api.post(V2 + '/secret/conceal', json=stg.conceal_body(value, 3600))
    rd = stg.api_client(FX['a_email'], FX['a_token']).post(stg.DIRECT + '/api/v2/secret/conceal', json=stg.conceal_body(value, 3600),
                                                         headers={'X-Forwarded-Proto': 'https', 'Host': 'secrets.staging.test'})
    ok_round = None
    if rp.status_code == 200:
        sid_ = rp.json()['record']['secret']['identifier']
        rv = stg.session('198.51.100.14').post(f'{V2}/secret/{sid_}/reveal', json={'continue': True})
        ok_round = rv.status_code == 200 and rv.json()['record'].get('secret_value') == value
    sizes[n] = {'proxy': rp.status_code, 'direct': rd.status_code, 'round_trip': ok_round}
L.check('P06c', 'secret sizes: the proxy answers what the app answers, and accepted secrets reveal byte-identical',
        all(v['proxy'] == v['direct'] and v['round_trip'] in (True, None) for v in sizes.values())
        and sizes[1_000]['round_trip'] is True and all(v['proxy'] < 500 for v in sizes.values()), sizes)
uni = 'pässwörd \U0001F512 日本語 \r\n\ttab "quote" \\ <script>'
rp = api.post(V2 + '/secret/conceal', json=stg.conceal_body(uni, 3600))
rv = stg.session('198.51.100.14').post(f"{V2}/secret/{rp.json()['record']['secret']['identifier']}/reveal", json={'continue': True})
L.check('P06d', 'unicode, control characters and markup survive the round trip through the proxy',
        rv.status_code == 200 and rv.json()['record'].get('secret_value') == uni, rv.status_code)

# ---------------------------------------------------------- P08 methods
rh = stg.session('198.51.100.15').head(V2 + '/status')
L.check('P08a', 'HEAD on a non-one-time route is answered 200 with no body', rh.status_code == 200 and not rh.content, (rh.status_code, len(rh.content)))
s, h, body = curl('-X', 'TRACE', V2 + '/status')
L.check('P08b', 'TRACE is not echoed', s in (404, 405, 501) and b'TRACE' not in body, s)

# -------------------------------------------------------- P07 rate limits
time.sleep(61)  # let the one-minute auth zone drain
quiet = stg.session('203.0.113.50', retry_429=False)
noisy = stg.session('203.0.113.51', retry_429=False)
codes_noisy = [noisy.post(stg.BASE + '/auth/login', json={'login': f'nobody-{RUN}@staging.test', 'password': 'x'}).status_code for _ in range(6)]
r_quiet = quiet.post(stg.BASE + '/auth/login', json={'login': f'nobody2-{RUN}@staging.test', 'password': 'x'})
L.check('P07a', 'auth zone: the sixth login attempt from one address within a minute is throttled',
        codes_noisy[5] == 429 and 429 not in codes_noisy[:5], codes_noisy)
L.check('P07b', 'auth zone is per client: another address is not throttled by the first one\'s attempts',
        r_quiet.status_code != 429, (r_quiet.status_code, r_quiet.headers.get('retry-after')))
time.sleep(1.5)
burst = [noisy.get(V2 + '/status').status_code for _ in range(45)]
r_quiet2 = quiet.get(V2 + '/status')
L.note('P07c', 'general/api zone burst from one address: status counts', {c: burst.count(c) for c in sorted(set(burst))})
L.check('P07d', 'general zone is per client: another address is served while the first is throttled',
        burst.count(429) == 0 or r_quiet2.status_code == 200, (burst.count(429), r_quiet2.status_code))
before = len(stg.redis_keys('receipt:*:object'))
time.sleep(1.2)
anon2 = stg.session('203.0.113.52', retry_429=False)
res = [anon2.post(V2 + '/guest/secret/conceal', json=stg.conceal_body(f'burst-{i}', 3600)) for i in range(40)]
ok = [x for x in res if x.status_code == 200]
throttled = [x for x in res if x.status_code == 429]
after = len(stg.redis_keys('receipt:*:object'))
L.check('P07e', 'a throttled creation writes nothing: receipts created == 200 answers',
        after - before == len(ok) and len(ok) + len(throttled) == len(res), {'200': len(ok), '429': len(throttled), 'created': after - before})
time.sleep(61)

# ------------------------------------------------------- P10 log hygiene
marker_secret = f'PLAINTEXT-{uuid.uuid4().hex}'
marker_pass = f'PASSPHRASE-{uuid.uuid4().hex}'
rp = api.post(V2 + '/secret/conceal', json=stg.conceal_body(marker_secret, 3600, passphrase=marker_pass))
sid = rp.json()['record']['secret']['identifier']
stg.session('198.51.100.14').post(f'{V2}/secret/{sid}/reveal', json={'passphrase': 'wrong-' + marker_pass, 'continue': True})
stg.session('198.51.100.14').post(f'{V2}/secret/{sid}/reveal?passphrase={marker_pass}', json={'passphrase': marker_pass, 'continue': True})
time.sleep(2)
logs = [CADDY_LOG] + ([APP_LOG, stg.ROOT + '/logs/head-worker.log', stg.ROOT + '/logs/head-scheduler.log'] if APP_LOG else [])
hits = {}
for needle, name in ((marker_secret, 'secret value'), (marker_pass, 'passphrase'), (FX['a_token'], 'API token'), ('verify-account?key=', 'verification key in a URL')):
    for f in logs:
        n = int(subprocess.run(['grep', '-a', '-c', '-F', needle, f], capture_output=True, text=True).stdout.strip() or 0)
        if n:
            hits[f'{name} in {f.split("/")[-1]}'] = n
L.check('P10a', 'secret values, passphrases, API tokens and verification keys appear in no proxy or app log', not hits, hits)
n_q = int(subprocess.run(['grep', '-a', '-c', '-E', r'"uri":"[^"]*\?', CADDY_LOG], capture_output=True, text=True).stdout.strip() or 0)
L.check('P10b', 'proxy access log carries no query strings', n_q == 0, n_q)
n_id = int(subprocess.run(['grep', '-a', '-c', '-F', sid, CADDY_LOG], capture_output=True, text=True).stdout.strip() or 0)
n_id_app = int(subprocess.run(['grep', '-a', '-c', '-F', sid, APP_LOG], capture_output=True, text=True).stdout.strip() or 0) if APP_LOG else None
L.note('P10c', 'full secret identifiers (capability handles) in logs: proxy access log lines / app log lines', (n_id, n_id_app))

L.note('P89', 'proxy 429s the polite client waited out', stg.STATS['429'])
sys.exit(1 if L.done() else 0)
