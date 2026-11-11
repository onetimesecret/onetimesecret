"""Two-direction test, writer half: run under version A, in full mode,
through the proxy, with A's worker and scheduler. Leaves accounts, sessions,
an API token, secrets in every state and one queued email for version B.

Usage: xdir_write.py <tag> <version: head|v19>
Writes results/xdir-<tag>.json (fixtures) for xdir_read.py.
"""
import json
import subprocess
import sys
import time

import stg

TAG, VER = sys.argv[1], sys.argv[2]
L = stg.Ledger(f'xdir-{TAG}-write-{VER}')
V1, V2, V3 = stg.BASE + '/api/v1', stg.BASE + '/api/v2', stg.BASE + '/api/v3'
STACK = stg.STACK
EMAIL = f'xd-{TAG}@staging.test'
fx = {'tag': TAG, 'writer': VER, 'email': EMAIL, 'password': stg.PASSWORD, 'secrets': {}, 'shapes': {}}


def stack(*args):
    return subprocess.run([STACK, *args], capture_output=True, text=True)


def keys_of(d):
    return sorted(d.keys()) if isinstance(d, dict) else type(d).__name__


# ---------------------------------------------------------------- account
web = stg.Browserish('198.51.100.30')
r = web.signup(EMAIL)
L.check('W01', 'sign-up', r.status_code == 200, (r.status_code, r.text[:120]))
r = web.verify_from_mail(EMAIL)
L.check('W02', 'verify through the emailed link (queue -> worker -> SMTP)', r is not None and r.status_code == 200, r is not None and r.status_code)
r = web.login(EMAIL)
L.check('W03', 'login', r.status_code == 200, r.status_code)
fx['token'] = web.apitoken()
fx['custid'] = web.get('/api/v3/receipt/recent').json().get('custid')
# a second, untouched browser session whose cookie the other version must accept
keep = stg.Browserish('198.51.100.31')
keep.login(EMAIL)
fx['kept_cookie'] = keep.s.cookies.get('onetime.session')
fx['kept_csrf'] = keep.csrf
L.check('W04', 'API token and a second logged-in session', bool(fx['token']) and bool(fx['kept_cookie']), None)

api = stg.api_client(EMAIL, fx['token'], '198.51.100.32')
anon = stg.session('198.51.100.33')


def put(name, resp, value=None, **more):
    ok = resp.status_code == 200
    if ok:
        rid, sid = stg.ids(resp)
        fx['secrets'][name] = {'rid': rid, 'sid': sid, 'value': value, **more}
    L.check(f'W10:{name}', f'create {name}', ok, None if ok else (resp.status_code, resp.text[:120]))
    return fx['secrets'].get(name, {})


# ------------------------------------------------------------- the secrets
r = web.post('/api/v3/secret/conceal', json=stg.conceal_body('plain via v3 session', 7200))
put('plain_v3', r, 'plain via v3 session')
fx['shapes']['v3_conceal_receipt'] = keys_of(r.json()['record']['receipt']) if r.ok else None

r = api.post(V2 + '/secret/conceal', json=stg.conceal_body('with passphrase', 7200, passphrase='xd-pass-77'))
put('passphrase', r, 'with passphrase', passphrase='xd-pass-77')
fx['shapes']['v2_conceal'] = {k: keys_of(v) for k, v in r.json()['record'].items()} if r.ok else None

put('generated', api.post(V2 + '/secret/generate', json={'secret': {'ttl': 7200}}))

rcpt = f'xd-{TAG}-rcpt@staging.test'
s = put('recipient', api.post(V2 + '/secret/conceal', json=stg.conceal_body('emailed by the writer', 7200, recipient=[rcpt])),
        'emailed by the writer', recipient=rcpt)
m = stg.mail_search(rcpt, timeout=30)
L.check('W11', "writer's worker delivered the recipient email", m is not None and s.get('sid', 'x') in m['Text'], m and m['Subject'])

put('to_burn', api.post(V2 + '/secret/conceal', json=stg.conceal_body('burn me later', 7200)), 'burn me later')

s = put('revealed', api.post(V2 + '/secret/conceal', json=stg.conceal_body('revealed by writer', 7200)), 'revealed by writer')
rv = anon.post(f"{V2}/secret/{s['sid']}/reveal", json={'continue': True})
L.check('W12', 'reveal one under the writer', rv.status_code == 200, rv.status_code)

s = put('burned', api.post(V2 + '/secret/conceal', json=stg.conceal_body('burned by writer', 7200)), 'burned by writer')
rb = api.post(f"{V2}/receipt/{s['rid']}/burn", json={'continue': True})
L.check('W13', 'burn one under the writer', rb.status_code == 200 and rb.json().get('record', {}).get('state') == 'burned', rb.status_code)

s = put('memo', api.post(V2 + '/secret/conceal', json=stg.conceal_body('has a memo', 7200)), 'has a memo', memo='written by ' + VER)
rm = api.patch(f"{V2}/receipt/{s['rid']}", json={'memo': 'written by ' + VER})
L.check('W14', 'memo set under the writer', rm.status_code == 200, rm.status_code)

r = api.post(V1 + '/share', data={'secret': 'v1 shared', 'ttl': 7200})
ok = r.status_code == 200
if ok:
    d = r.json()
    fx['secrets']['v1'] = {'rid': d['metadata_key'], 'sid': d['secret_key'], 'value': 'v1 shared'}
L.check('W10:v1', 'create v1', ok, None if ok else r.status_code)

put('guest', anon.post(V2 + '/guest/secret/conceal', json=stg.conceal_body('guest made', 7200)), 'guest made')

uni = 'unicöde \U0001F510 漢字 line1\nline2'
put('unicode', api.post(V2 + '/secret/conceal', json=stg.conceal_body(uni, 7200)), uni)

s = put('previewed', api.post(V2 + '/secret/conceal', json=stg.conceal_body('looked at, not revealed', 7200)), 'looked at, not revealed')
anon.get(f"{V2}/secret/{s['sid']}")
api.get(f"{V2}/receipt/{s['rid']}")
fx['secrets']['previewed']['state_at_writer'] = stg.hget(f"receipt:{s['rid']}:object", 'state')

# listing as the writer sees it
rl = api.get(V2 + '/receipt/recent').json()
fx['list_at_writer'] = {x['identifier']: x['state'] for x in rl.get('records', [])}
fx['shapes']['v2_recent_record'] = keys_of(rl['records'][0]) if rl.get('records') else None
rs = api.get(f"{V2}/receipt/{fx['secrets']['memo']['rid']}").json()
fx['shapes']['v2_receipt_show'] = {'record': keys_of(rs.get('record')), 'details': keys_of(rs.get('details'))}
ss = anon.get(f"{V2}/secret/{fx['secrets']['to_burn']['sid']}").json()
fx['shapes']['v2_secret_show'] = {'record': keys_of(ss.get('record')), 'details': keys_of(ss.get('details'))}

# -------------------------- left for the other version's scheduler and worker
stack('down', VER, 'scheduler')
s = put('week', api.post(V2 + '/secret/conceal', json=stg.conceal_body('seven days', 604800)), 'seven days')
L.check('W15', 'long-lived secret is on the expiration timeline, not yet warned',
        bool(stg.zmember('receipt:expiration_timeline', s.get('rid', ''))) and not stg.smember('receipt:warnings_sent', s.get('rid', '')),
        None)
stack('down', VER, 'worker')
time.sleep(1)
qr = f'xd-{TAG}-queued@staging.test'
put('queued', api.post(V2 + '/secret/conceal', json=stg.conceal_body('email left on the queue', 7200, recipient=[qr])),
    'email left on the queue', recipient=qr)
depth = stg.wait_for(lambda: (stg.queue_depth() or {}).get('ready', 0) >= 1 and stg.queue_depth(), timeout=10)
L.check('W16', "one email is left on the queue for the other version's worker", bool(depth) and not stg.mail_list(qr), depth)

json.dump(fx, open(stg.RESULTS + f'/xdir-{TAG}.json', 'w'), indent=1)
sys.exit(1 if L.done() else 0)
