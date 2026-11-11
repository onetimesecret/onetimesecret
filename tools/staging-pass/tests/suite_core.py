"""Full-mode core secret path, through the proxy.

Usage: suite_core.py <run-id> [label]
The run id makes account emails unique so the suite can be re-run on the
same datastore. All requests go client -> Caddy (TLS) -> Puma.
"""
import json
import sys
import threading
import time

import audit
import stg

RUN = sys.argv[1] if len(sys.argv) > 1 else str(int(time.time()))
LABEL = sys.argv[2] if len(sys.argv) > 2 else 'head'
L = stg.Ledger(f'core-{LABEL}')
A_EMAIL = f'core-a-{RUN}@staging.test'
B_EMAIL = f'core-b-{RUN}@staging.test'
V2 = stg.BASE + '/api/v2'
V3 = stg.BASE + '/api/v3'
V1 = stg.BASE + '/api/v1'


def j(r):
    try:
        return r.json()
    except ValueError:
        return {}


def rkey(rid):
    return f'receipt:{rid}:object'


def skey(sid):
    return f'secret:{sid}:object'


# ---------------------------------------------------------------- accounts
alice = stg.Browserish('198.51.100.10')
r = alice.signup(A_EMAIL)
L.check('C01a', 'sign-up answers verify_email', r.status_code == 200 and j(r).get('next_action') == 'verify_email',
        (r.status_code, r.text[:160]))
r = alice.verify_from_mail(A_EMAIL)
L.check('C01b', 'verification link from the queued email verifies the account',
        r is not None and r.status_code == 200, r is not None and (r.status_code, r.text[:120]))
r = alice.login(A_EMAIL)
cookie = next((c for c in alice.s.cookies if c.name == 'onetime.session'), None)
L.check('C01c', 'login sets a Secure session cookie',
        r.status_code == 200 and cookie is not None and cookie.secure,
        (r.status_code, cookie and {'secure': cookie.secure, 'rest': cookie._rest}))
a_token = alice.apitoken()
L.check('C01d', 'session mints an API token', bool(a_token), a_token and len(a_token))

bob = stg.Browserish('192.0.2.10')
bob.signup(B_EMAIL)
bob.verify_from_mail(B_EMAIL)
r = bob.login(B_EMAIL)
b_token = bob.apitoken()
L.check('C01e', 'second account ready', r.status_code == 200 and bool(b_token), r.status_code)

a_api = stg.api_client(A_EMAIL, a_token, '198.51.100.11')
b_api = stg.api_client(B_EMAIL, b_token, '192.0.2.11')
anon = stg.session('203.0.113.20')
a_custid = j(alice.get('/api/v3/receipt/recent')).get('custid')

# --------------------------------------------------- C02 session creation
r = alice.post('/api/v3/secret/conceal', json=stg.conceal_body('v3 session secret', 3600))
ok = r.status_code == 200
rid, sid = stg.ids(r) if ok else (None, None)
L.check('C02a', 'v3 session conceal succeeds', ok, (r.status_code, r.text[:200]))
if ok:
    s_ttl, r_ttl = int(stg.redis('ttl', skey(sid))), int(stg.redis('ttl', rkey(rid)))
    L.check('C02b', 'both hashes exist with TTLs (secret ~ttl, receipt ~2x)',
            3590 <= s_ttl <= 3600 and 7190 <= r_ttl <= 7200, {'secret_ttl': s_ttl, 'receipt_ttl': r_ttl})
    org = stg.hget(rkey(rid), 'org_id')
    owner = stg.hget(rkey(rid), 'owner_id')
    L.check('C02c', 'receipt carries owner and organization', owner == a_custid and bool(org),
            {'owner_matches': owner == a_custid, 'org': bool(org)})
    in_owner = stg.redis('zscore', f'customer:{owner}:receipts', json.dumps(rid)) or \
        stg.redis('zscore', f'customer:{owner}:receipts', rid)
    in_org = stg.redis('zscore', f'organization:{org}:receipts', rid)
    in_inst = stg.redis('zscore', 'receipt:instances', rid), stg.redis('zscore', 'secret:instances', sid)
    L.check('C02d', 'pair is registered: owner index, org index, both instances sets',
            bool(in_owner) and bool(in_org) and all(in_inst),
            {'owner': bool(in_owner), 'org': bool(in_org), 'instances': [bool(x) for x in in_inst]})
    back = stg.hget(skey(sid), 'receipt_identifier') == rid and stg.hget(rkey(rid), 'secret_identifier') == sid
    L.check('C02e', 'secret and receipt name each other', back)

# ---------------------------------------------------------- C03 CSRF gate
before = len(stg.redis_keys('receipt:*:object'))
r = alice.s.post(V3 + '/secret/conceal', json=stg.conceal_body('no csrf', 3600))  # no X-CSRF-Token
after = len(stg.redis_keys('receipt:*:object'))
L.check('C03', 'session-authenticated conceal without CSRF token is refused and writes nothing',
        r.status_code == 403 and after == before, (r.status_code, r.text[:120], after - before))

# ------------------------------------------------- C04 reveal exactly once
r1 = anon.post(f'{V3}/guest/secret/{sid}/reveal', json={'continue': True})
r2 = anon.post(f'{V3}/guest/secret/{sid}/reveal', json={'continue': True})
L.check('C04a', 'anonymous reveal returns the value once',
        r1.status_code == 200 and j(r1).get('record', {}).get('secret_value') == 'v3 session secret',
        (r1.status_code, r1.text[:160]))
L.check('C04b', 'second reveal is 404', r2.status_code == 404, (r2.status_code, r2.text[:120]))
state = stg.hget(rkey(rid), 'state')
L.check('C04c', 'receipt is revealed, pointer cleared, secret hash gone',
        state == 'revealed' and stg.hget(rkey(rid), 'secret_identifier') in ('', None)
        and stg.redis('exists', skey(sid)) == '0',
        {'state': state, 'secret_exists': stg.redis('exists', skey(sid))})
L.check('C04d', 'receipt TTL is not reset by the transition',
        int(stg.redis('ttl', rkey(rid))) <= 7200, stg.redis('ttl', rkey(rid)))

# ------------------------------------------------- C05 v2 basic + passphrase
r = a_api.post(V2 + '/secret/conceal', json=stg.conceal_body('v2 passphrase secret', 3600, passphrase='pw-1234'))
rid5, sid5 = stg.ids(r)
rw = anon.post(f'{V2}/secret/{sid5}/reveal', json={'passphrase': 'wrong', 'continue': True})
st_after_wrong = stg.hget(skey(sid5), 'state')
rr = anon.post(f'{V2}/secret/{sid5}/reveal', json={'passphrase': 'pw-1234', 'continue': True})
L.check('C05a', 'v2 Basic-auth conceal with passphrase', r.status_code == 200 and j(r)['record']['receipt']['has_passphrase'] is True, r.status_code)
L.check('C05b', 'wrong passphrase is refused and does not consume', rw.status_code in (403, 422) and st_after_wrong in ('new', 'previewed'),
        (rw.status_code, rw.text[:100], st_after_wrong))
L.check('C05c', 'right passphrase reveals', rr.status_code == 200 and j(rr)['record'].get('secret_value') == 'v2 passphrase secret', rr.status_code)

# ------------------------------------- C06 generate + HEAD on receipt read
r = a_api.post(V2 + '/secret/generate', json={'secret': {'ttl': 3600}})
rid6, sid6 = stg.ids(r)
h = a_api.head(f'{V2}/receipt/{rid6}')
L.check('C06a', 'HEAD on the receipt read is 405 with Allow, empty body',
        h.status_code == 405 and 'GET' in (h.headers.get('allow') or '') and not h.content,
        (h.status_code, h.headers.get('allow'), len(h.content)))
g1 = a_api.get(f'{V2}/receipt/{rid6}')
g2 = a_api.get(f'{V2}/receipt/{rid6}')
v1 = j(g1).get('details', {}).get('secret_value')
v2 = j(g2).get('details', {}).get('secret_value')
L.check('C06b', 'HEAD did not consume the one-time display: first GET shows the generated value',
        g1.status_code == 200 and isinstance(v1, str) and len(v1) >= 8, (g1.status_code, bool(v1)))
L.check('C06c', 'second GET no longer shows it', g2.status_code == 200 and v2 is None, (g2.status_code, v2))

# ------------------------------------------- C07 HEAD on the secret read
r = a_api.post(V2 + '/secret/conceal', json=stg.conceal_body('head must not consume', 3600))
rid7, sid7 = stg.ids(r)
codes = {}
for path in (f'{V2}/secret/{sid7}', f'{V3}/guest/secret/{sid7}', f'{V2}/guest/secret/{sid7}', f'{V2}/private/{rid7}',
             f'{V3}/guest/receipt/{rid7}'):
    hh = anon.head(path)
    codes[path.replace(stg.BASE, '').replace(sid7, ':sid').replace(rid7, ':rid')] = (hh.status_code, hh.headers.get('allow'))
L.check('C07a', 'HEAD on every one-time read route is 405', all(c[0] == 405 for c in codes.values()), codes)
L.check('C07b', 'secret untouched after the HEAD requests',
        stg.hget(skey(sid7), 'state') == 'new' and stg.hget(rkey(rid7), 'state') == 'new',
        (stg.hget(skey(sid7), 'state'), stg.hget(rkey(rid7), 'state')))
rr = anon.post(f'{V2}/secret/{sid7}/reveal', json={'continue': True})
L.check('C07c', 'and still reveals afterwards', rr.status_code == 200 and j(rr)['record'].get('secret_value') == 'head must not consume', rr.status_code)

# ------------------------------------------------------------- C08 burn
r = a_api.post(V2 + '/secret/conceal', json=stg.conceal_body('to burn', 3600))
rid8, sid8 = stg.ids(r)
rb = a_api.post(f'{V2}/receipt/{rid8}/burn', json={'continue': True})
ra = anon.post(f'{V2}/secret/{sid8}/reveal', json={'continue': True})
L.check('C08a', 'burn succeeds', rb.status_code == 200 and j(rb).get('record', {}).get('state') == 'burned', (rb.status_code, rb.text[:120]))
L.check('C08b', 'burned secret cannot be revealed; hash gone',
        ra.status_code == 404 and stg.redis('exists', skey(sid8)) == '0', (ra.status_code, stg.redis('exists', skey(sid8))))
L.check('C08c', 'receipt records burned with pointer cleared',
        stg.hget(rkey(rid8), 'state') == 'burned' and stg.hget(rkey(rid8), 'secret_identifier') in ('', None)
        and isinstance(stg.hget(rkey(rid8), 'burned'), int), stg.hget(rkey(rid8), 'state'))

# ------------------------------------------------------------- C09 memo
r = alice.post('/api/v3/secret/conceal', json=stg.conceal_body('memo target', 3600))
rid9, sid9 = stg.ids(r)
ttl_before = int(stg.redis('ttl', rkey(rid9)))
rm = alice.patch(f'/api/v3/receipt/{rid9}', json={'memo': 'first memo'})
ttl_after = int(stg.redis('ttl', rkey(rid9)))
L.check('C09a', 'memo edit on a new receipt is stored and answers with the receipt',
        rm.status_code == 200 and stg.hget(rkey(rid9), 'memo') == 'first memo'
        and j(rm).get('record', {}).get('identifier') == rid9 and j(rm)['record'].get('memo') == 'first memo',
        (rm.status_code, rm.text[:140]))
L.check('C09b', 'memo edit leaves state and TTL alone',
        stg.hget(rkey(rid9), 'state') == 'new' and ttl_before - 3 <= ttl_after <= ttl_before, (ttl_before, ttl_after))
anon.post(f'{V3}/guest/secret/{sid9}/reveal', json={'continue': True})
rm2 = alice.patch(f'/api/v3/receipt/{rid9}', json={'memo': 'after reveal'})
L.check('C09c', 'memo edit after reveal keeps the receipt revealed',
        rm2.status_code == 200 and stg.hget(rkey(rid9), 'state') == 'revealed' and stg.hget(rkey(rid9), 'memo') == 'after reveal',
        (rm2.status_code, stg.hget(rkey(rid9), 'state')))
ghost = 'z' * 62
rm3 = alice.patch(f'/api/v3/receipt/{ghost}', json={'memo': 'ghost'})
L.check('C09d', 'memo edit on a missing receipt is 404 and creates no key',
        rm3.status_code == 404 and stg.redis('exists', rkey(ghost)) == '0', (rm3.status_code, stg.redis('exists', rkey(ghost))))

# ------------------------------------------------------------- C10 lists
ra = j(a_api.get(V2 + '/receipt/recent'))
rb = j(b_api.get(V2 + '/receipt/recent'))
a_ids = {x['identifier'] for x in ra.get('records', [])}
states = {x['identifier']: x['state'] for x in ra.get('records', [])}
L.check('C10a', "owner's recent list has the receipts created above with their states",
        {rid, rid5, rid6, rid7, rid8, rid9} <= a_ids and states.get(rid) == 'revealed' and states.get(rid8) == 'burned',
        {'count': ra.get('count'), 'states': sorted(set(states.values()))})
L.check('C10b', "another account's list has none of them", not (a_ids & {x['identifier'] for x in rb.get('records', [])}), rb.get('count'))
ro = j(a_api.get(V2 + '/receipt/recent', params={'scope': 'org'}))
L.check('C10c', 'org-scoped list has them too', {rid, rid9} <= {x['identifier'] for x in ro.get('records', [])}, ro.get('count'))
rn = a_api.get(V2 + '/receipt/recent?scope[a]=b')
L.check('C10d', 'nested scope parameter is a 4xx, not a 500', 400 <= rn.status_code < 500, (rn.status_code, rn.text[:120]))
rv3 = alice.get('/api/v3/receipt/recent')
L.check('C10e', 'v3 session list answers with native types',
        rv3.status_code == 200 and isinstance(j(rv3).get('count'), int) and j(rv3)['count'] >= 6, (rv3.status_code, j(rv3).get('count')))

# --------------------------------------------------------------- C11 v1
r = a_api.post(V1 + '/share', data={'secret': 'v1 secret', 'ttl': 3600})
d = j(r)
L.check('C11a', 'v1 share', r.status_code == 200 and d.get('secret_key') and d.get('metadata_key'), (r.status_code, r.text[:120]))
if d.get('secret_key'):
    rp = a_api.post(f"{V1}/private/{d['metadata_key']}")
    rs = anon.post(f"{V1}/secret/{d['secret_key']}")
    rs2 = anon.post(f"{V1}/secret/{d['secret_key']}")
    L.check('C11b', 'v1 private shows the receipt', rp.status_code == 200 and j(rp).get('metadata_key') == d['metadata_key'], rp.status_code)
    L.check('C11c', 'v1 secret reveals once', rs.status_code == 200 and j(rs).get('value') == 'v1 secret' and rs2.status_code == 404,
            (rs.status_code, rs2.status_code))
r = a_api.post(V1 + '/generate', data={'ttl': 3600})
d = j(r)
L.check('C11d', 'v1 generate returns a value', r.status_code == 200 and bool(d.get('value')), r.status_code)
if d.get('metadata_key'):
    rb1 = a_api.post(f"{V1}/private/{d['metadata_key']}/burn")
    L.check('C11e', 'v1 burn', rb1.status_code == 200 and (j(rb1).get('state') or {}).get('state') == 'burned', (rb1.status_code, rb1.text[:120]))
rr = a_api.get(V1 + '/private/recent')
L.check('C11f', 'v1 recent lists receipts', rr.status_code == 200 and isinstance(j(rr) if rr.text.startswith('[') else None, list), (rr.status_code, rr.text[:80]))

# ---------------------------------------------------------- C12 OPTIONS
before = len(stg.redis_keys('receipt:*:object'))
o2 = anon.options(V2 + '/secret/conceal')
o3 = anon.options(V3 + '/secret/generate')
after = len(stg.redis_keys('receipt:*:object'))
L.check('C12', 'OPTIONS on conceal/generate is 204, grants no CORS and creates nothing',
        o2.status_code == 204 and o3.status_code == 204 and after == before
        and 'access-control-allow-origin' not in {k.lower() for k in o2.headers},
        (o2.status_code, o3.status_code, after - before))

# -------------------------------------- C13 body cannot redirect the path
ra_ = a_api.post(V2 + '/secret/conceal', json=stg.conceal_body('target A', 3600))
rb_ = a_api.post(V2 + '/secret/conceal', json=stg.conceal_body('bystander B', 3600))
ridA, sidA = stg.ids(ra_)
ridB, sidB = stg.ids(rb_)
r = anon.post(f'{V2}/secret/{sidA}/reveal', json={'identifier': sidB, 'key': sidB, 'continue': True})
L.check('C13a', 'reveal acts on the path identifier, not one in the JSON body',
        r.status_code == 200 and j(r)['record'].get('secret_value') == 'target A' and stg.hget(skey(sidB), 'state') == 'new',
        (r.status_code, j(r).get('record', {}).get('secret_value'), stg.hget(skey(sidB), 'state')))
r = a_api.post(f'{V2}/receipt/{ridA}/burn?identifier={ridB}', json={'identifier': ridB, 'continue': True})
L.check('C13b', 'burn acts on the path identifier, not the body or query one',
        stg.hget(rkey(ridB), 'state') == 'new' and stg.redis('exists', skey(sidB)) == '1',
        (r.status_code, stg.hget(rkey(ridB), 'state')))
r = alice.patch(f'/api/v3/receipt/{ridA}', json={'identifier': ridB, 'memo': 'for A only'})
L.check('C13c', 'memo edit acts on the path identifier',
        stg.hget(rkey(ridA), 'memo') == 'for A only' and stg.hget(rkey(ridB), 'memo') in ('', None),
        (r.status_code, stg.hget(rkey(ridB), 'memo')))

# ------------------------------------------------- C14 request validation
rm_ = a_api.post(V2 + '/secret/conceal', json=stg.conceal_body('memo type target', 3600))
ridM, sidM = stg.ids(rm_)
before = len(stg.redis_keys('receipt:*:object'))
JSONH = {'Content-Type': 'application/json'}
deep = '{"a":' * 300 + '1' + '}' * 300
cases = [
    ('truncated JSON', 'POST', V2 + '/secret/conceal', '{"secret":', JSONH, 400),
    ('truncated JSON v3 guest', 'POST', V3 + '/guest/secret/conceal', '{"secret":{"secret":"x"', JSONH, 400),
    ('truncated JSON incoming', 'POST', stg.BASE + '/api/incoming/secret', '{"x":', JSONH, 400),
    ('garbage JSON', 'POST', V2 + '/secret/generate', 'not json at all', JSONH, 400),
    ('empty JSON body', 'POST', V2 + '/secret/conceal', '', JSONH, None),
    ('JSON array', 'POST', V2 + '/secret/conceal', '[1,2,3]', JSONH, None),
    ('JSON string', 'POST', V2 + '/secret/conceal', '"just a string"', JSONH, None),
    ('JSON number', 'POST', V2 + '/secret/conceal', '42', JSONH, None),
    ('JSON null', 'POST', V2 + '/secret/conceal', 'null', JSONH, None),
    ('deeply nested JSON', 'POST', V2 + '/secret/conceal', deep, JSONH, None),
    ('NUL in JSON string', 'POST', V2 + '/secret/conceal', '{"secret":{"secret":"a\\u0000b","ttl":"\\u0000"}}', JSONH, None),
    ('invalid UTF-8 in JSON', 'POST', V2 + '/secret/conceal', b'{"secret":{"secret":"\xff\xfe"}}', JSONH, None),
    ('secret as array', 'POST', V2 + '/secret/conceal', '{"secret":["a","b"]}', JSONH, None),
    ('secret.secret as object', 'POST', V2 + '/secret/conceal', '{"secret":{"secret":{"x":1},"ttl":3600}}', JSONH, None),
    ('ttl as object', 'POST', V2 + '/secret/conceal', '{"secret":{"secret":"x","ttl":{"a":1}}}', JSONH, None),
    ('ttl negative', 'POST', V2 + '/secret/conceal', '{"secret":{"secret":"x","ttl":-5}}', JSONH, 'any'),
    ('passphrase as object', 'POST', V2 + '/secret/conceal', '{"secret":{"secret":"x","ttl":3600,"passphrase":{"a":1}}}', JSONH, None),
    ('recipient as nested object', 'POST', V2 + '/secret/conceal', '{"secret":{"secret":"x","ttl":3600,"recipient":{"a":{"b":1}}}}', JSONH, None),
    ('form: conflicting types', 'POST', V2 + '/secret/conceal', 'secret=1&secret[secret]=x', {'Content-Type': 'application/x-www-form-urlencoded'}, 400),
    ('form: bad percent-encoding', 'POST', V2 + '/secret/conceal', 'secret[secret]=%ZZ%', {'Content-Type': 'application/x-www-form-urlencoded'}, None),
    ('query: conflicting types', 'GET', V2 + '/receipt/recent?a=1&a[b]=2', None, {}, 400),
    ('query: conflicting types on reveal', 'POST', f'{V2}/secret/{sidB}/reveal?a=1&a[b]=2', '{"continue":true}', JSONH, 400),
    ('text/plain body', 'POST', V2 + '/secret/conceal', '{"secret":{"secret":"x","ttl":3600}}', {'Content-Type': 'text/plain'}, None),
    ('reveal: JSON array body', 'POST', f'{V2}/secret/{sidB}/reveal', '[]', JSONH, None),
    ('burn: garbage JSON', 'POST', f'{V2}/receipt/{ridB}/burn', '{{{{', JSONH, 400),
    ('memo: garbage JSON', 'PATCH', f'{V2}/receipt/{ridB}', '{"memo":', JSONH, 400),
    ('memo as object', 'PATCH', f'{V2}/receipt/{ridM}', '{"memo":{"a":1}}', JSONH, None),
    ('JSON true', 'POST', V2 + '/secret/conceal', 'true', JSONH, None),
    ('JSON false', 'POST', V2 + '/secret/conceal', 'false', JSONH, None),
    ('v3 guest: JSON array', 'POST', V3 + '/guest/secret/conceal', '[1]', JSONH, None),
    ('v3 guest: JSON string', 'POST', V3 + '/guest/secret/conceal', '"s"', JSONH, None),
    ('v3 guest reveal: JSON number', 'POST', f'{V3}/guest/secret/{sidB}/reveal', '7', JSONH, None),
    ('burn: JSON array', 'POST', f'{V2}/receipt/{ridB}/burn', '[]', JSONH, None),
    ('memo: JSON string', 'PATCH', f'{V2}/receipt/{ridB}', '"m"', JSONH, None),
]
five_xx, wrong, table = [], [], {}
for name, method, url, body, headers, want in cases:
    rr = a_api.request(method, url, data=body, headers=headers)
    table[name] = rr.status_code
    if rr.status_code >= 500:
        five_xx.append((name, rr.status_code, rr.text[:120]))
    if isinstance(want, int) and rr.status_code != want:
        wrong.append((name, rr.status_code, rr.text[:120]))
    if want == 400 and rr.status_code == 400:
        try:
            ok_shape = 'message' in rr.json()
        except ValueError:
            ok_shape = False
        if not ok_shape:
            wrong.append((name, 'bad 400 body', rr.text[:120]))
L.check('C14a', 'no malformed request body or query produces a 5xx', not five_xx, five_xx or table)
L.check('C14b', 'unparseable JSON, form and query input answers 400 with a JSON message', not wrong, wrong)
created = len(stg.redis_keys('receipt:*:object')) - before
creating = [n for n, m, u, *_ in cases if u.endswith('/conceal') or u.endswith('/generate') or u.endswith('/incoming/secret')]
ok_created = sum(1 for k in creating if table[k] == 200)
L.check('C14c', 'only requests answered 200 created anything', created == ok_created,
        {'created': created, 'creating_requests_answered_200': [k for k in creating if table[k] == 200]})
L.note('C14e', 'malformed-but-parseable input the API accepted (200), and what a memo object was stored as',
       {'accepted': [k for k, v in table.items() if v == 200], 'memo_object_stored_as': stg.hget(rkey(ridM), 'memo')})
L.note('C14f', 'status per case', table)
L.check('C14d', 'bystander secret B survived every malformed reveal/burn/memo',
        stg.hget(skey(sidB), 'state') == 'new' and stg.hget(rkey(ridB), 'state') == 'new' and stg.hget(rkey(ridB), 'memo') in ('', None),
        (stg.hget(skey(sidB), 'state'), stg.hget(rkey(ridB), 'state'), stg.hget(rkey(ridB), 'memo')))

# --------------------------------------------------------------- C15 races
IPS = [f'203.0.113.{i}' for i in range(21, 45)]


def parallel(fns):
    barrier = threading.Barrier(len(fns))
    out = [None] * len(fns)

    def run(i, fn):
        barrier.wait()
        try:
            out[i] = fn()
        except Exception as ex:  # noqa: BLE001 - a transport error is a result here
            out[i] = ex
    ts = [threading.Thread(target=run, args=(i, fn)) for i, fn in enumerate(fns)]
    [t.start() for t in ts]
    [t.join() for t in ts]
    return out


def code(x):
    return getattr(x, 'status_code', repr(x))


# a) N concurrent reveals: exactly one value
winners_bad = []
for rnd in range(6):
    r = a_api.post(V2 + '/secret/conceal', json=stg.conceal_body(f'race-{rnd}', 3600))
    rid_, sid_ = stg.ids(r)
    sess = [stg.session(ip, retry_429=False) for ip in IPS[:12]]
    time.sleep(1.2)
    res = parallel([lambda s=s: s.post(f'{V2}/secret/{sid_}/reveal', json={'continue': True}) for s in sess])
    got = [x for x in res if code(x) == 200 and j(x).get('record', {}).get('secret_value') == f'race-{rnd}']
    others = sorted({code(x) for x in res if x not in got})
    if len(got) != 1 or stg.hget(rkey(rid_), 'state') != 'revealed' or stg.redis('exists', skey(sid_)) != '0':
        winners_bad.append((rnd, len(got), others, stg.hget(rkey(rid_), 'state')))
L.check('C15a', '12 concurrent reveals x6: exactly one gets the value, receipt ends revealed', not winners_bad, winners_bad)

# b) burn racing reveal: exactly one wins and the receipt agrees with the winner
bad = []
tally = {'reveal': 0, 'burn': 0}
for rnd in range(20):
    r = a_api.post(V2 + '/secret/conceal', json=stg.conceal_body(f'br-{rnd}', 3600))
    rid_, sid_ = stg.ids(r)
    s1, s2 = stg.session(IPS[rnd % 12], retry_429=False), stg.api_client(A_EMAIL, a_token, IPS[12 + rnd % 12], retry_429=False)
    time.sleep(0.3)
    res = parallel([
        lambda: s1.post(f'{V2}/secret/{sid_}/reveal', json={'continue': True}),
        lambda: s2.post(f'{V2}/receipt/{rid_}/burn', json={'continue': True}),
    ])
    revealed = code(res[0]) == 200 and j(res[0]).get('record', {}).get('secret_value') == f'br-{rnd}'
    burned = code(res[1]) == 200 and j(res[1]).get('success') is True and j(res[1]).get('record', {}).get('state') == 'burned'
    state = stg.hget(rkey(rid_), 'state')
    gone = stg.redis('exists', skey(sid_)) == '0'
    if revealed and not burned and state == 'revealed' and gone:
        tally['reveal'] += 1
    elif burned and not revealed and state == 'burned' and gone:
        tally['burn'] += 1
    else:
        bad.append({'round': rnd, 'reveal': code(res[0]), 'revealed': revealed, 'burn': code(res[1]), 'burned': burned,
                    'burn_body': getattr(res[1], 'text', '')[:160], 'state': state, 'secret_gone': gone})
L.check('C15b', 'burn racing reveal x20: one winner each time, receipt state matches it, secret destroyed', not bad, bad or tally)

# c) memo edits racing the terminal transition: state is never reverted
bad = []
for rnd in range(15):
    r = alice.post('/api/v3/secret/conceal', json=stg.conceal_body(f'mr-{rnd}', 3600))
    rid_, sid_ = stg.ids(r)
    ttl0 = int(stg.redis('ttl', rkey(rid_)))
    s1 = stg.session(IPS[rnd % 12], retry_429=False)
    time.sleep(0.4)
    memos = [f'memo-{rnd}-{k}' for k in range(3)]
    api_m = [stg.api_client(A_EMAIL, a_token, IPS[12 + (rnd + k) % 12], retry_429=False) for k in range(3)]
    res = parallel([lambda: s1.post(f'{V2}/secret/{sid_}/reveal', json={'continue': True})] +
                   [lambda m=m, c=c: c.patch(f'{V2}/receipt/{rid_}', json={'memo': m}) for m, c in zip(memos, api_m)])
    state = stg.hget(rkey(rid_), 'state')
    memo = stg.hget(rkey(rid_), 'memo')
    ttl1 = int(stg.redis('ttl', rkey(rid_)))
    okm = [m for m, x in zip(memos, res[1:]) if code(x) == 200]
    if not (code(res[0]) == 200 and state == 'revealed' and stg.hget(rkey(rid_), 'secret_identifier') in ('', None)
            and (memo in okm or (not okm and memo in ('', None))) and ttl1 <= ttl0
            and isinstance(stg.hget(rkey(rid_), 'revealed'), int)):
        bad.append({'round': rnd, 'codes': [code(x) for x in res], 'state': state, 'memo': memo, 'ttl': (ttl0, ttl1)})
L.check('C15c', 'memo edits racing reveal x15: receipt ends revealed with its timestamp, memo is one of the accepted edits, TTL not extended',
        not bad, bad)

# ---------------------------------------------------------- final audit
stats, problems = audit.audit_pairs()
L.note('C89', 'proxy 429s the polite client had to wait out during this suite', stg.STATS['429'])
L.check('C90', 'datastore audit: every secret has its receipt, every key has a TTL, owned receipts are indexed', not problems, problems or stats)
with open(stg.RESULTS + f'/core-{LABEL}-fixtures.json', 'w') as fh:
    json.dump({'run': RUN, 'a_email': A_EMAIL, 'a_token': a_token, 'b_email': B_EMAIL, 'b_token': b_token, 'custid': a_custid}, fh)
sys.exit(1 if L.done() else 0)
