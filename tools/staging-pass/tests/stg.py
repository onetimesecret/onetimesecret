"""Client helpers for the staging pass.

Everything goes through the proxy (https://secrets.staging.test -> Caddy ->
Puma) unless a test says otherwise. Results go to a JSONL ledger so each
check keeps an ID, what was expected and what was observed.
"""
import base64
import json
import os
import re
import subprocess
import sys
import time

import requests
from requests.adapters import HTTPAdapter

HERE = os.path.dirname(os.path.abspath(__file__))
# STAGING_ROOT contains the deployed tree, env files and logs; STAGING_STATE the
# generated secrets, the staging CA and the result ledgers (see ../README.md).
ROOT = os.environ.get('STAGING_ROOT', '/srv/ots-staging')
STAGING = os.environ.get('STAGING_STATE', os.path.join(ROOT, 'state'))
RESULTS = os.path.join(STAGING, 'results')
STACK = os.path.join(HERE, '..', 'stack.sh')
CA = os.path.join(STAGING, 'tls', 'ca.crt')
BASE = 'https://secrets.staging.test'
DIRECT = 'http://127.0.0.1:3000'
MAILPIT = 'http://127.0.0.1:8125'
RABBIT_API = 'http://127.0.0.1:15772/api'
PASSWORD = 'Correct-Horse-Battery-9'


def _secrets():
    out = {}
    with open(os.path.join(STAGING, 'secrets.env')) as fh:
        for line in fh:
            if '=' in line:
                k, v = line.strip().split('=', 1)
                out[k] = v
    return out


SECRETS = _secrets()


# --- ledger ---------------------------------------------------------------

class Ledger:
    def __init__(self, suite, path=None):
        self.suite = suite
        self.path = path or os.path.join(RESULTS, f'{suite}.jsonl')
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.fh = open(self.path, 'w')
        self.fails = 0
        self.count = 0

    def check(self, cid, desc, ok, observed=None, expected=None):
        self.count += 1
        ok = bool(ok)
        if not ok:
            self.fails += 1
        rec = {'suite': self.suite, 'id': cid, 'desc': desc, 'pass': ok,
               'expected': expected, 'observed': observed}
        self.fh.write(json.dumps(rec, default=str) + '\n')
        self.fh.flush()
        mark = 'PASS' if ok else 'FAIL'
        tail = '' if ok and observed is None else f' :: {str(observed)[:300]}'
        print(f'[{mark}] {cid} {desc}{tail}', flush=True)
        return ok

    def note(self, cid, desc, observed):
        """An observation recorded without a verdict."""
        rec = {'suite': self.suite, 'id': cid, 'desc': desc, 'pass': None, 'observed': observed}
        self.fh.write(json.dumps(rec, default=str) + '\n')
        self.fh.flush()
        print(f'[NOTE] {cid} {desc} :: {str(observed)[:400]}', flush=True)

    def done(self):
        print(f'== {self.suite}: {self.count - self.fails}/{self.count} passed, {self.fails} failed', flush=True)
        self.fh.close()
        return self.fails


# --- http -----------------------------------------------------------------

class SourceAdapter(HTTPAdapter):
    """Bind outgoing connections to one local address, so the proxy sees
    that address as the peer (its rate-limit and client-IP key)."""

    def __init__(self, source_ip, **kw):
        self.source_ip = source_ip
        super().__init__(**kw)

    def init_poolmanager(self, *a, **kw):
        kw['source_address'] = (self.source_ip, 0)
        return super().init_poolmanager(*a, **kw)


STATS = {'429': 0}


class PoliteSession(requests.Session):
    """Retries a 429 after its Retry-After, the way a well-behaved client
    would. Race tests switch this off (retry_429=False) and space their
    rounds instead, so a throttled request is visible as a 429."""

    retry_429 = True

    def request(self, method, url, **kw):
        for _ in range(8):
            r = super().request(method, url, **kw)
            if r.status_code != 429 or not self.retry_429:
                return r
            STATS['429'] += 1
            try:
                wait = float(r.headers.get('retry-after', '1'))
            except ValueError:
                wait = 1.0
            time.sleep(min(wait, 61) + 0.25)
        return r


def session(source_ip=None, retry_429=True):
    s = PoliteSession()
    s.retry_429 = retry_429
    s.trust_env = False          # ignore the sandbox's outbound proxy
    s.verify = CA
    s.headers.update({'Accept': 'application/json'})
    if source_ip:
        s.mount('https://', SourceAdapter(source_ip))
        s.mount('http://', SourceAdapter(source_ip))
    return s


def basic(user, token):
    return {'Authorization': 'Basic ' + base64.b64encode(f'{user}:{token}'.encode()).decode()}


class Browserish:
    """A cookie session that sends the CSRF token the way the SPA does."""

    def __init__(self, source_ip=None, base=BASE):
        self.s = session(source_ip)
        self.base = base
        self.csrf = None

    def _track(self, r):
        tok = r.headers.get('x-csrf-token')
        if tok:
            self.csrf = tok
        return r

    def prime(self):
        return self._track(self.s.get(self.base + '/', headers={'Accept': 'text/html'}))

    def req(self, method, path, **kw):
        headers = dict(kw.pop('headers', {}) or {})
        if self.csrf and method.upper() not in ('GET', 'HEAD', 'OPTIONS'):
            headers.setdefault('X-CSRF-Token', self.csrf)
        return self._track(self.s.request(method, self.base + path, headers=headers, **kw))

    def get(self, path, **kw):
        return self.req('GET', path, **kw)

    def post(self, path, **kw):
        return self.req('POST', path, **kw)

    def patch(self, path, **kw):
        return self.req('PATCH', path, **kw)

    def signup(self, email, password=PASSWORD):
        self.prime()
        r = self.post('/auth/create-account', json={'login': email, 'password': password, 'agree': True,
                                                    'shrimp': self.csrf, 'locale': 'en'})
        return r

    def verify_from_mail(self, email, timeout=40):
        m = mail_search(email, 'verify', timeout=timeout)
        if not m:
            return None
        key = re.search(r'verify-account\?key=(\S+)', m['Text']).group(1)
        return self.post('/auth/verify-account', json={'key': key, 'shrimp': self.csrf})

    def login(self, email, password=PASSWORD):
        if not self.csrf:
            self.prime()
        return self.post('/auth/login', json={'login': email, 'password': password, 'shrimp': self.csrf})

    def apitoken(self):
        r = self.post('/api/account/apitoken', json={})
        return r.json()['record']['apitoken'] if r.ok else None


def api_client(email, token, source_ip=None, retry_429=True):
    s = session(source_ip, retry_429)
    s.headers.update(basic(email, token))
    return s


# --- mail -----------------------------------------------------------------

def _plain():
    p = requests.Session()
    p.trust_env = False
    return p


def mail_search(to, subject_part=None, timeout=30, exclude_ids=()):
    """Poll mailpit for a message to `to`; return the full message JSON."""
    plain = _plain()
    deadline = time.time() + timeout
    while True:
        r = plain.get(f'{MAILPIT}/api/v1/search', params={'query': f'to:{to}'})
        for m in r.json().get('messages', []):
            if subject_part and subject_part.lower() not in m['Subject'].lower():
                continue
            if m['ID'] in exclude_ids:
                continue
            return plain.get(f"{MAILPIT}/api/v1/message/{m['ID']}").json()
        if time.time() >= deadline:
            return None
        time.sleep(0.5)


def mail_list(to):
    return _plain().get(f'{MAILPIT}/api/v1/search', params={'query': f'to:{to}'}).json().get('messages', [])


def mail_wait_count(to, n, timeout=30):
    deadline = time.time() + timeout
    while time.time() < deadline:
        got = len(mail_list(to))
        if got >= n:
            return got
        time.sleep(0.5)
    return len(mail_list(to))


# --- datastore / broker ---------------------------------------------------

def redis(*args, raw=False):
    cmd = ['redis-cli', '-p', '6479', '-a', SECRETS['VALKEY_PASSWORD'], '--no-auth-warning', *map(str, args)]
    out = subprocess.run(cmd, capture_output=True, text=True).stdout
    return out if raw else out.strip()


def redis_keys(pattern):
    out = redis('--scan', '--pattern', pattern)
    return [k for k in out.split('\n') if k]


def hget(key, field):
    """Field value, JSON-decoded when it is JSON (Familia v2 storage)."""
    v = redis('hget', key, field)
    try:
        return json.loads(v)
    except (ValueError, TypeError):
        return v


def rabbit(path, method='GET', **kw):
    p = _plain()
    try:
        return p.request(method, f'{RABBIT_API}{path}', auth=(SECRETS['RABBITMQ_USER'], SECRETS['RABBITMQ_PASS']), timeout=10, **kw)
    except requests.exceptions.RequestException:
        r = requests.Response()   # broker (or its management API) is down
        r.status_code = 0
        return r


def queue_depth(name='email.message.send'):
    r = rabbit(f'/queues/%2F/{name}')
    if r.status_code != 200:
        return None
    d = r.json()
    return {'ready': d.get('messages_ready'), 'unacked': d.get('messages_unacknowledged'),
            'consumers': d.get('consumers')}


def wait_for(fn, timeout=30, interval=0.5):
    deadline = time.time() + timeout
    last = None
    while time.time() < deadline:
        last = fn()
        if last:
            return last
        time.sleep(interval)
    return last


def conceal_body(value, ttl=3600, **extra):
    inner = {'secret': value, 'ttl': ttl}
    inner.update(extra)
    return {'secret': inner}


def ids(resp):
    """(receipt_id, secret_id) from a v2/v3 conceal or generate response."""
    rec = resp.json()['record']
    return rec['receipt']['identifier'], rec['secret']['identifier']


def zmember(key, member):
    """Score of a sorted-set member stored either raw or JSON-quoted."""
    return redis('zscore', key, member) or redis('zscore', key, json.dumps(member))


def smember(key, member):
    return redis('sismember', key, member) == '1' or redis('sismember', key, json.dumps(member)) == '1'
