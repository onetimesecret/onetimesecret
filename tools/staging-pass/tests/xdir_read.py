"""Two-direction test, reader half: run under version B on the datastores
version A wrote. B's web is up; this script starts B's worker and scheduler
when it gets to the queued email and the expiration warning.

Usage: xdir_read.py <tag> <version: head|v19>
"""
import json
import subprocess
import sys
import time

import audit
import stg

TAG, VER = sys.argv[1], sys.argv[2]
fx = json.load(open(stg.RESULTS + f'/xdir-{TAG}.json'))
L = stg.Ledger(f'xdir-{TAG}-read-{VER}')
V1, V2, V3 = stg.BASE + '/api/v1', stg.BASE + '/api/v2', stg.BASE + '/api/v3'
STACK = stg.STACK
S = fx['secrets']
EMAIL = fx['email']


def stack(*args):
    return subprocess.run([STACK, *args], capture_output=True, text=True)


def keys_of(d):
    return sorted(d.keys()) if isinstance(d, dict) else type(d).__name__


def rkey(rid):
    return f'receipt:{rid}:object'


def skey(sid):
    return f'secret:{sid}:object'


def reveal(sid, **body):
    body.setdefault('continue', True)
    return anon.post(f'{V2}/secret/{sid}/reveal', json=body)


def value_of(r):
    try:
        return r.json()['record'].get('secret_value')
    except (ValueError, KeyError):
        return None


anon = stg.session('192.0.2.30')

# ------------------------------------------------------ identity continuity
kept = stg.Browserish('192.0.2.31')
kept.s.cookies.set('onetime.session', fx['kept_cookie'], domain='secrets.staging.test', path='/', secure=True)
r = kept.get('/api/v3/receipt/recent')
L.check('R01', "a session cookie issued by the writer is still an authenticated session",
        r.status_code == 200 and r.json().get('custid') == fx['custid'], (r.status_code, r.text[:100]))
kept.prime()
r = kept.post('/api/v3/secret/conceal', json=stg.conceal_body('made on the old session', 3600))
L.check('R02', 'and can create a secret (CSRF token issued by the reader)', r.status_code == 200, (r.status_code, r.text[:100]))
web = stg.Browserish('192.0.2.32')
r = web.login(EMAIL, fx['password'])
L.check('R03', "password login works against the writer's account", r.status_code == 200, (r.status_code, r.text[:100]))
api = stg.api_client(EMAIL, fx['token'], '192.0.2.33')
rl = api.get(V2 + '/receipt/recent')
L.check('R04', "the writer's API token authenticates", rl.status_code == 200 and rl.json().get('custid') == fx['custid'], rl.status_code)

# ------------------------------------------------------------------ listing
now_list = {x['identifier']: x for x in rl.json().get('records', [])} if rl.ok else {}
missing = [k for k in fx['list_at_writer'] if k not in now_list]
changed = {k[:8]: (v, now_list[k]['state']) for k, v in fx['list_at_writer'].items() if k in now_list and now_list[k]['state'] != v}
L.check('R05', "every receipt in the writer's list is in the reader's list with the same state", not missing and not changed,
        {'missing': [m[:8] for m in missing], 'changed': changed, 'count': len(now_list)})
ro = api.get(V2 + '/receipt/recent', params={'scope': 'org'})
org_ids = {x['identifier'] for x in ro.json().get('records', [])} if ro.ok else set()
owned = [v['rid'] for k, v in S.items() if k not in ('guest', 'v1')]
L.check('R06', 'org-scoped list has the owned receipts', ro.status_code == 200 and set(owned) <= org_ids,
        {'status': ro.status_code, 'missing': [x[:8] for x in owned if x not in org_ids]})
shapes = {}
shapes['v2_recent_record'] = keys_of(next(iter(now_list.values()))) if now_list else None
rs = api.get(f"{V2}/receipt/{S['memo']['rid']}")
shapes['v2_receipt_show'] = {'record': keys_of(rs.json().get('record')), 'details': keys_of(rs.json().get('details'))} if rs.ok else None
ss = anon.get(f"{V2}/secret/{S['to_burn']['sid']}")
shapes['v2_secret_show'] = {'record': keys_of(ss.json().get('record')), 'details': keys_of(ss.json().get('details'))} if ss.ok else None
rc = api.post(V2 + '/secret/conceal', json=stg.conceal_body('shape probe', 3600, passphrase='shape-pw'))
shapes['v2_conceal'] = {k: keys_of(v) for k, v in rc.json()['record'].items()} if rc.ok else None
r3 = web.post('/api/v3/secret/conceal', json=stg.conceal_body('shape probe v3', 3600))
shapes['v3_conceal_receipt'] = keys_of(r3.json()['record']['receipt']) if r3.ok else None
diff = {}
for k, v in fx['shapes'].items():
    if shapes.get(k) != v:
        a = json.dumps(v, sort_keys=True)
        b = json.dumps(shapes.get(k), sort_keys=True)
        diff[k] = {'writer_only': sorted(set(str(v).replace("'", '').replace('[', '').replace(']', '').split(', ')) -
                                           set(str(shapes.get(k)).replace("'", '').replace('[', '').replace(']', '').split(', '))),
                   'reader_only': sorted(set(str(shapes.get(k)).replace("'", '').replace('[', '').replace(']', '').split(', ')) -
                                           set(str(v).replace("'", '').replace('[', '').replace(']', '').split(', ')))} if a != b else {}
L.note('R07', 'response field sets that differ between the two versions (v2 list/show/conceal, v3 conceal)', diff or 'none')

# ----------------------------------------------------------- receipt reads
rs = api.get(f"{V2}/receipt/{S['memo']['rid']}")
L.check('R10', "memo written by the writer is shown", rs.status_code == 200 and rs.json()['record'].get('memo') == S['memo']['memo'],
        rs.status_code == 200 and rs.json()['record'].get('memo'))
rs = api.get(f"{V2}/receipt/{S['revealed']['rid']}")
L.check('R11', "receipt of the writer-revealed secret reads as revealed",
        rs.status_code == 200 and rs.json()['record'].get('state') == 'revealed' and rs.json()['record'].get('is_revealed') is True,
        rs.status_code == 200 and rs.json()['record'].get('state'))
rs = api.get(f"{V2}/receipt/{S['burned']['rid']}")
L.check('R12', "receipt of the writer-burned secret reads as burned",
        rs.status_code == 200 and rs.json()['record'].get('state') == 'burned', rs.status_code == 200 and rs.json()['record'].get('state'))
rs = api.get(f"{V2}/receipt/{S['recipient']['rid']}")
L.check('R13', 'recipient receipt keeps its obscured recipient', rs.status_code == 200 and '*' in str(rs.json()['record'].get('recipients')),
        rs.status_code == 200 and rs.json()['record'].get('recipients'))
rs = api.get(f"{V2}/receipt/{S['passphrase']['rid']}")
L.check('R14', 'passphrase receipt knows it has a passphrase',
        rs.status_code == 200 and rs.json()['record'].get('has_passphrase') is True, rs.status_code)
g1 = api.get(f"{V2}/receipt/{S['generated']['rid']}")
g2 = api.get(f"{V2}/receipt/{S['generated']['rid']}")
gv = g1.json().get('details', {}).get('secret_value') if g1.ok else None
L.check('R15', "the creator's one-time display of a generated value survives the version change, once",
        isinstance(gv, str) and len(gv) >= 8 and g2.ok and g2.json().get('details', {}).get('secret_value') is None, (g1.status_code, bool(gv)))
S['generated']['value'] = gv

# ---------------------------------------------------------------- reveals
for name in ('plain_v3', 'recipient', 'guest', 'unicode', 'previewed', 'generated'):
    r = reveal(S[name]['sid'])
    L.check(f'R20:{name}', f'reveal {name}: value intact', r.status_code == 200 and value_of(r) == S[name]['value'], r.status_code)
    r2 = reveal(S[name]['sid'])
    st = stg.hget(rkey(S[name]['rid']), 'state')
    L.check(f'R21:{name}', f'{name}: second reveal 404, receipt revealed, secret hash gone',
            r2.status_code == 404 and st == 'revealed' and stg.redis('exists', skey(S[name]['sid'])) == '0', (r2.status_code, st))
rw = reveal(S['passphrase']['sid'], passphrase='wrong')
rr = reveal(S['passphrase']['sid'], passphrase=S['passphrase']['passphrase'])
L.check('R22', "passphrase set under the writer: wrong refused, right reveals",
        rw.status_code in (403, 422) and rr.status_code == 200 and value_of(rr) == S['passphrase']['value'], (rw.status_code, rr.status_code))
r = anon.post(f"{V1}/secret/{S['v1']['sid']}")
L.check('R23', 'v1 secret reveals through v1', r.status_code == 200 and r.json().get('value') == S['v1']['value'], r.status_code)
r = reveal(S['revealed']['sid'])
L.check('R24', 'a secret the writer already revealed stays gone', r.status_code == 404, r.status_code)

# ------------------------------------------- conditional updates on old data
ttl0 = int(stg.redis('ttl', rkey(S['memo']['rid'])))
rm = api.patch(f"{V2}/receipt/{S['memo']['rid']}", json={'memo': 'edited by ' + VER})
ttl1 = int(stg.redis('ttl', rkey(S['memo']['rid'])))
L.check('R30', "memo edit on a writer-created receipt: stored, state kept, TTL not extended",
        rm.status_code == 200 and stg.hget(rkey(S['memo']['rid']), 'memo') == 'edited by ' + VER
        and stg.hget(rkey(S['memo']['rid']), 'state') == 'new' and ttl1 <= ttl0, (rm.status_code, ttl0, ttl1))
rm = api.patch(f"{V2}/receipt/{S['revealed']['rid']}", json={'memo': 'on a revealed one'})
L.check('R31', 'memo edit on the writer-revealed receipt keeps it revealed',
        rm.status_code == 200 and stg.hget(rkey(S['revealed']['rid']), 'state') == 'revealed', (rm.status_code, stg.hget(rkey(S['revealed']['rid']), 'state')))
rb = api.post(f"{V2}/receipt/{S['to_burn']['rid']}/burn", json={'continue': True})
L.check('R32', 'burn a writer-created secret',
        rb.status_code == 200 and rb.json().get('record', {}).get('state') == 'burned'
        and stg.redis('exists', skey(S['to_burn']['sid'])) == '0' and reveal(S['to_burn']['sid']).status_code == 404, rb.status_code)
rb = api.post(f"{V2}/receipt/{S['memo']['rid']}/burn", json={'continue': True})
L.check('R33', 'burn the memo receipt: state burned, memo kept',
        rb.status_code == 200 and stg.hget(rkey(S['memo']['rid']), 'state') == 'burned'
        and stg.hget(rkey(S['memo']['rid']), 'memo') == 'edited by ' + VER, (rb.status_code, stg.hget(rkey(S['memo']['rid']), 'memo')))

# ------------------------------------------------------- job system handover
stack('up', VER, 'worker')
qr = S['queued']['recipient']
m = stg.mail_search(qr, timeout=60)
sid_q = S['queued']['sid']
L.check('R40', "the email the writer left on the queue is delivered by the reader's worker with the right link",
        m is not None and sid_q in m['Text'], m and m['Subject'])
time.sleep(5)
L.check('R41', 'exactly once', len(stg.mail_list(qr)) == 1, len(stg.mail_list(qr)))
r = reveal(sid_q)
L.check('R42', 'and its link reveals', r.status_code == 200 and value_of(r) == S['queued']['value'], r.status_code)
rcpt = f'xd-{TAG}-reader-rcpt@staging.test'
rn = api.post(V2 + '/secret/conceal', json=stg.conceal_body('emailed by the reader', 3600, recipient=[rcpt]))
m = stg.mail_search(rcpt, timeout=45)
L.check('R43', "a new recipient email goes out under the reader", rn.status_code == 200 and m is not None, (rn.status_code, bool(m)))

before_w = {x['ID'] for x in stg.mail_list(EMAIL)}
stack('up', VER, 'scheduler')
shortid = stg.hget(rkey(S['week']['rid']), 'secret_shortid')
warn = None
deadline = time.time() + 170
while time.time() < deadline and warn is None:
    for x in stg.mail_list(EMAIL):
        if x['ID'] in before_w:
            continue
        full = stg._plain().get(f"{stg.MAILPIT}/api/v1/message/{x['ID']}").json()
        if shortid and shortid in (full.get('Text', '') + full.get('HTML', '')):
            warn = full
    time.sleep(3)
L.check('R44', "the reader's scheduler warns about the long-lived secret the writer registered",
        warn is not None and stg.smember('receipt:warnings_sent', S['week']['rid']), warn and warn['Subject'])
r = reveal(S['week']['sid'])
L.check('R45', 'that secret still reveals', r.status_code == 200 and value_of(r) == S['week']['value'], r.status_code)

stats, problems = audit.audit_pairs()
L.check('R90', "datastore audit after the reader worked on the writer's data", not problems, problems or stats)
L.note('R89', 'proxy 429s the polite client waited out', stg.STATS['429'])
sys.exit(1 if L.done() else 0)
