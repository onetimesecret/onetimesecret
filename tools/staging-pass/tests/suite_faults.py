"""Fault injection on the creation commit and the proxy/app boundary.

  F01  idle datastore connections (Valkey --timeout 30, as the full compose sets)
  F02  process death during a creation burst (SIGKILL on Puma workers)
  F03  datastore outage during creation and consumption
  F04  upstream (Puma) down behind the proxy

Usage: suite_faults.py <run-id> <label>   (HEAD only: it signals native pids)
"""
import json
import os
import signal
import subprocess
import sys
import threading
import time

import audit
import stg

RUN, LABEL = sys.argv[1], sys.argv[2]
L = stg.Ledger(f'faults-{LABEL}')
FX = json.load(open(stg.RESULTS + f'/core-{LABEL}-fixtures.json'))
V2 = stg.BASE + '/api/v2'
STACK = stg.STACK


def rkey(rid):
    return f'receipt:{rid}:object'


def skey(sid):
    return f'secret:{sid}:object'


def puma_workers():
    master = int(open(stg.ROOT + '/logs/head-web.pid').read().strip())
    out = subprocess.run(['pgrep', '-P', str(master)], capture_output=True, text=True).stdout.split()
    return master, [int(x) for x in out]


# ------------------------------------------------------------ F01 idle
api = stg.api_client(FX['a_email'], FX['a_token'], '198.51.100.40')
api.post(V2 + '/secret/conceal', json=stg.conceal_body('warm', 3600))
time.sleep(45)   # longer than Valkey's 30s idle timeout
codes = []
for i in range(8):   # enough requests to reach both workers' idle connections
    r = stg.api_client(FX['a_email'], FX['a_token'], f'198.51.100.{41 + i % 4}').post(
        V2 + '/secret/conceal', json=stg.conceal_body(f'after idle {i}', 3600))
    codes.append(r.status_code)
L.check('F01a', 'first creations after the datastore closed idle connections all succeed', codes == [200] * 8, codes)
time.sleep(45)
r = api.post(V2 + '/secret/conceal', json=stg.conceal_body('reveal after idle', 3600))
rid, sid = stg.ids(r)
time.sleep(40)
rv = stg.session('198.51.100.45').post(f'{V2}/secret/{sid}/reveal', json={'continue': True})
L.check('F01b', 'a reveal after an idle period succeeds and consumes the secret',
        rv.status_code == 200 and rv.json()['record'].get('secret_value') == 'reveal after idle' and stg.redis('exists', skey(sid)) == '0',
        rv.status_code)

# ----------------------------------------------- F02 process death mid-burst
results = []
lock = threading.Lock()
stop = threading.Event()


def creator(n):
    s = stg.api_client(FX['a_email'], FX['a_token'], f'203.0.113.{21 + n}', retry_429=False)
    i = 0
    while not stop.is_set():
        i += 1
        value = f'burst-{RUN}-{n}-{i}'
        try:
            r = s.post(stg.DIRECT + '/api/v2/secret/conceal', json=stg.conceal_body(value, 3600),
                       headers={'Host': 'secrets.staging.test', 'X-Forwarded-Proto': 'https'}, timeout=20)
            rec = (r.status_code, stg.ids(r) if r.status_code == 200 else None, value)
        except Exception as ex:  # noqa: BLE001 - a dropped connection is a result
            rec = (type(ex).__name__, None, value)
        with lock:
            results.append(rec)


# straight at Puma: the kill is about the app's commit, and the proxy's
# shared rate-limit bucket would only thin the burst out
threads = [threading.Thread(target=creator, args=(n,)) for n in range(8)]
[t.start() for t in threads]
kills = 0
t_end = time.time() + 40
while time.time() < t_end:
    time.sleep(2.0)
    _, workers = puma_workers()
    if workers:
        try:
            os.kill(workers[kills % len(workers)], signal.SIGKILL)
            kills += 1
        except ProcessLookupError:
            pass
time.sleep(3)
stop.set()
[t.join() for t in threads]
time.sleep(5)
ok = [x for x in results if x[0] == 200]
dropped = [x for x in results if x[0] != 200]
missing = [x[2] for x in ok if stg.redis('exists', rkey(x[1][0])) != '1' or stg.redis('exists', skey(x[1][1])) != '1']
L.check('F02a', f'{kills} SIGKILLs on Puma workers during a creation burst: every creation answered 200 has its full pair',
        kills >= 10 and len(ok) > 50 and not missing,
        {'kills': kills, 'answered_200': len(ok), 'dropped_or_error': len(dropped), 'missing_pairs': missing[:5],
         'non_200': sorted({str(x[0]) for x in dropped})})
stats, problems = audit.audit_pairs()
L.check('F02b', 'and no request killed mid-commit left a secret without its receipt, a partial hash or a key without TTL',
        not problems, problems or stats)
_, workers = puma_workers()
r = api.post(V2 + '/secret/conceal', json=stg.conceal_body('after the kills', 3600))
L.check('F02c', 'Puma replaced the killed workers and serves again', len(workers) == 2 and r.status_code == 200, (len(workers), r.status_code))

# --------------------------------------------------- F03 datastore outage
r = api.post(V2 + '/secret/conceal', json=stg.conceal_body('survives the outage', 3600))
rid_o, sid_o = stg.ids(r)
subprocess.run(['docker', 'stop', '-t', '5', 'stg-valkey'], capture_output=True)
t = time.time()
r_c = api.post(V2 + '/secret/conceal', json=stg.conceal_body('during outage', 3600), timeout=60)
r_v = stg.session('198.51.100.45').post(f'{V2}/secret/{sid_o}/reveal', json={'continue': True}, timeout=60)
took = time.time() - t


def js(r):
    try:
        return r.json()
    except ValueError:
        return r.text[:160]


L.check('F03a', 'with the datastore down, creation and reveal answer a 5xx error, never a success',
        r_c.status_code >= 500 and r_v.status_code >= 500, {'conceal': (r_c.status_code, js(r_c)), 'reveal': (r_v.status_code, js(r_v)), 'seconds': round(took, 1)})
L.note('F03b', 'error bodies and Retry-After during the outage',
       {'conceal_retry_after': r_c.headers.get('retry-after'), 'reveal_retry_after': r_v.headers.get('retry-after'),
        'leaks_connection_details': any(x in (r_c.text + r_v.text) for x in ('6479', '127.0.0.1', 'redis://', stg.SECRETS['VALKEY_PASSWORD']))})
subprocess.run(['docker', 'start', 'stg-valkey'], capture_output=True)
stg.wait_for(lambda: stg.redis('ping') == 'PONG', timeout=30)
time.sleep(2)
r_after = api.post(V2 + '/secret/conceal', json=stg.conceal_body('after outage', 3600))
rv = stg.session('198.51.100.45').post(f'{V2}/secret/{sid_o}/reveal', json={'continue': True})
L.check('F03c', 'after the datastore returns (AOF persistence), the app recovers without a restart',
        r_after.status_code == 200, r_after.status_code)
L.check('F03d', 'the secret from before the outage is still there and reveals exactly once',
        rv.status_code == 200 and rv.json()['record'].get('secret_value') == 'survives the outage', rv.status_code)
stats, problems = audit.audit_pairs()
L.check('F03e', 'audit after the outage', not problems, problems or stats)

# ------------------------------------------------------ F04 upstream down
subprocess.run([STACK, 'down', 'head', 'web'], capture_output=True)
s = stg.session('198.51.100.46', retry_429=False)
r = s.post(V2 + '/secret/conceal', json=stg.conceal_body('no upstream', 3600), headers=stg.basic(FX['a_email'], FX['a_token']))
L.check('F04a', 'with Puma down the proxy answers 502 with a request id and no-store, not a hang',
        r.status_code == 502 and bool(r.headers.get('x-request-id')) and 'no-store' in (r.headers.get('cache-control') or ''),
        (r.status_code, r.headers.get('x-request-id'), r.headers.get('cache-control')))
subprocess.run([STACK, 'up', 'head', 'web'], capture_output=True)
ok_after = None
t = time.time()
while time.time() - t < 45:
    r = s.post(V2 + '/secret/conceal', json=stg.conceal_body('upstream back', 3600), headers=stg.basic(FX['a_email'], FX['a_token']))
    if r.status_code == 200:
        ok_after = round(time.time() - t, 1)
        break
    time.sleep(1)
L.check('F04b', 'the proxy serves again once Puma is back (passive health check, fail_duration 30s)', ok_after is not None, {'seconds_until_200': ok_after})
sys.exit(1 if L.done() else 0)
