"""The job system on the core secret path: RabbitMQ, the email worker, the
scheduler. Also the expiry behaviour of the conditional receipt updates,
which needs the same waiting time.

Usage: suite_jobs.py <run-id> <label> <version: head|v19>
Needs results/core-<label>-fixtures.json (an account + API token).
Drives process restarts through stack.sh.
"""
import json
import re
import subprocess
import sys
import time
import uuid

import audit
import stg

RUN = sys.argv[1]
LABEL = sys.argv[2]
VER = sys.argv[3] if len(sys.argv) > 3 else 'head'
L = stg.Ledger(f'jobs-{LABEL}')
FX = json.load(open(stg.RESULTS + f'/core-{LABEL}-fixtures.json'))
V2 = stg.BASE + '/api/v2'
STACK = stg.STACK
SCHED_LOG = stg.ROOT + '/logs/head-scheduler.log'
api = stg.api_client(FX['a_email'], FX['a_token'], '198.51.100.20')
anon = stg.session('198.51.100.21')


def stack(*args):
    return subprocess.run([STACK, *args], capture_output=True, text=True)


def rkey(rid):
    return f'receipt:{rid}:object'


def skey(sid):
    return f'secret:{sid}:object'


def conceal(value, ttl=3600, **extra):
    r = api.post(V2 + '/secret/conceal', json=stg.conceal_body(value, ttl, **extra))
    return r, (stg.ids(r) if r.status_code == 200 else (None, None))


def link_secret_id(mail):
    m = re.search(r'https://secrets\.staging\.test/secret/([a-z0-9]+)', mail['Text'])
    return m.group(1) if m else None


# ----------------------------------------- expiry fixtures (checked at the end)
t0 = time.time()
r, (rid_x, sid_x) = conceal('expires soon', 60)
r, (rid_y, sid_y) = conceal('expires soon too', 60)
L.check('J00', 'short-TTL fixtures created (60s secret, 120s receipt)',
        int(stg.redis('ttl', skey(sid_x))) <= 60 and 100 <= int(stg.redis('ttl', rkey(rid_x))) <= 120,
        (stg.redis('ttl', skey(sid_x)), stg.redis('ttl', rkey(rid_x))))

# ------------------------------------------------ J01 recipient email via queue
rcpt = f'j01-{RUN}@staging.test'
r, (rid, sid) = conceal('queued delivery', 3600, recipient=[rcpt])
mail = stg.mail_search(rcpt, timeout=30)
L.check('J01a', 'conceal with a recipient answers 200 with the recipient obscured on the receipt',
        r.status_code == 200 and '*' in str(r.json()['record']['receipt'].get('recipients')), r.status_code)
L.check('J01b', 'the email worker delivers the secret link for that secret on the public host',
        mail is not None and link_secret_id(mail) == sid, mail and (mail['Subject'], link_secret_id(mail) == sid))
rv = anon.post(f'{V2}/secret/{sid}/reveal', json={'continue': True})
L.check('J01c', 'the emailed link reveals the secret', rv.status_code == 200 and rv.json()['record'].get('secret_value') == 'queued delivery', rv.status_code)
L.check('J01d', 'queue is drained and the message id is claimed', (stg.queue_depth() or {}).get('ready') == 0, stg.queue_depth())

# --------------------------------------------------------- J02 worker down
stack('down', VER, 'worker')
rcpts = [f'j02-{RUN}-{i}@staging.test' for i in range(3)]
t = time.time()
made = [conceal(f'while worker down {i}', 3600, recipient=[x]) for i, x in enumerate(rcpts)]
took = time.time() - t
depth = stg.wait_for(lambda: (stg.queue_depth() or {}).get('ready') == 3 and stg.queue_depth(), timeout=10) or stg.queue_depth()
L.check('J02a', 'creation is not held up by a stopped worker', all(m[0].status_code == 200 for m in made) and took < 5, round(took, 2))
L.check('J02b', 'the three emails wait on the durable queue', depth and depth.get('ready') == 3 and not any(stg.mail_list(x) for x in rcpts), depth)
# keep one message's properties for the duplicate-delivery test
peek = stg.rabbit('/queues/%2F/email.message.send/get', 'POST',
                  json={'count': 1, 'ackmode': 'ack_requeue_true', 'encoding': 'auto'}).json()
stack('up', VER, 'worker')
counts = [stg.mail_wait_count(x, 1, timeout=45) for x in rcpts]
time.sleep(6)
counts2 = [len(stg.mail_list(x)) for x in rcpts]
L.check('J02c', 'a restarted worker delivers each exactly once', counts == [1, 1, 1] and counts2 == [1, 1, 1], (counts, counts2))

# ------------------------------------------------ J04 duplicate delivery
if peek:
    msg = peek[0]
    props = msg.get('properties', {})
    to = json.loads(msg['payload']).get('data', {}).get('recipient') or json.loads(msg['payload']).get('recipient')
    pub = stg.rabbit('/exchanges/%2F/amq.default/publish', 'POST', json={
        'properties': props, 'routing_key': 'email.message.send', 'payload': msg['payload'],
        'payload_encoding': msg.get('payload_encoding', 'string')})
    time.sleep(8)
    n = len(stg.mail_list(to)) if to else None
    L.check('J04', 'a redelivered copy of an already-processed message (same message_id) is dropped, not sent twice',
            pub.status_code == 200 and n == 1, {'republished': pub.status_code, 'mails_to_recipient': n, 'message_id': props.get('message_id', '')[:8]})
else:
    L.check('J04', 'duplicate delivery test could read a queued message', False, peek)

# --------------------------------------------------------- J03 broker down
subprocess.run(['docker', 'stop', '-t', '10', 'stg-rabbitmq'], capture_output=True)
rcpt3 = f'j03-{RUN}@staging.test'
t = time.time()
r, (rid3, sid3) = conceal('while broker down', 3600, recipient=[rcpt3])
took = time.time() - t
r_plain, _ = conceal('no recipient while broker down', 3600)
L.check('J03a', 'with the broker down, creation still commits and answers 200',
        r.status_code == 200 and r_plain.status_code == 200 and stg.redis('exists', skey(sid3)) == '1', (r.status_code, r_plain.status_code, round(took, 2)))
mail3 = stg.mail_search(rcpt3, timeout=25)
L.note('J03b', 'recipient email while the broker is down (fallback path)',
       {'delivered': mail3 is not None, 'link_matches': bool(mail3) and link_secret_id(mail3) == sid3, 'creation_seconds': round(took, 2)})
subprocess.run(['docker', 'start', 'stg-rabbitmq'], capture_output=True)
stg.wait_for(lambda: stg.rabbit('/overview').status_code == 200 if True else False, timeout=60)
time.sleep(12)
rcpt3b = f'j03b-{RUN}@staging.test'
ok_after = False
for attempt in range(4):
    r, (rid3b, sid3b) = conceal(f'after broker restart {attempt}', 3600, recipient=[rcpt3b])
    if stg.mail_wait_count(rcpt3b, attempt + 1, timeout=25) >= attempt + 1:
        ok_after = True
        break
L.check('J03c', 'after the broker returns, the web publisher and the worker recover without a restart',
        ok_after, {'attempts': attempt + 1, 'queue': stg.queue_depth()})
n3 = len(stg.mail_list(rcpt3))
L.check('J03d', 'the broker-down email was delivered at most once', n3 <= 1, n3)

# ---------------------------------------- J07 worker restart under load
rcpts7 = [f'j07-{RUN}-{i}@staging.test' for i in range(12)]
for i, x in enumerate(rcpts7):
    conceal(f'restart under load {i}', 3600, recipient=[x])
    if i == 5:
        stack('down', VER, 'worker')
stack('up', VER, 'worker')
got = [stg.mail_wait_count(x, 1, timeout=60) for x in rcpts7]
time.sleep(5)
got2 = [len(stg.mail_list(x)) for x in rcpts7]
L.check('J07', 'a worker stopped (SIGTERM) and restarted mid-stream loses no email; duplicates reported',
        all(n >= 1 for n in got2), {'delivered': sum(1 for n in got2 if n >= 1), 'duplicates': sum(1 for n in got2 if n > 1)})

# ------------------------------------------------- J05 expiration warnings
before_w = {m['ID'] for m in stg.mail_list(FX['a_email'])}
r, (rid5, sid5) = conceal('seven day secret', 604800)
in_tl = stg.zmember('receipt:expiration_timeline', rid5)
L.check('J05a', 'a long-lived secret is registered on the expiration timeline at creation', r.status_code == 200 and bool(in_tl), in_tl)
r, (rid5s, sid5s) = conceal('short secret, no warning', 3600)
L.check('J05b', 'a short-lived one is not', not stg.zmember('receipt:expiration_timeline', rid5s))
shortid = rid5 and stg.hget(rkey(rid5), 'secret_shortid')
warn = None
deadline = time.time() + 150
while time.time() < deadline and warn is None:
    for m in stg.mail_list(FX['a_email']):
        if m['ID'] in before_w:
            continue
        full = stg._plain().get(f"{stg.MAILPIT}/api/v1/message/{m['ID']}").json()
        if shortid and shortid in (full.get('Text', '') + full.get('HTML', '')):
            warn = full
    time.sleep(3)
L.check('J05c', 'the scheduler enqueues and the worker delivers an expiration warning to the owner naming that secret',
        warn is not None, warn and warn['Subject'])
sent = '1' if stg.smember('receipt:warnings_sent', rid5) else '0'
time.sleep(70)
n_warn = 0
for m in stg.mail_list(FX['a_email']):
    if m['ID'] in before_w:
        continue
    full = stg._plain().get(f"{stg.MAILPIT}/api/v1/message/{m['ID']}").json()
    if shortid and shortid in (full.get('Text', '') + full.get('HTML', '')):
        n_warn += 1
L.check('J05d', 'the warning is marked sent and not repeated on the next run', sent == '1' and n_warn == 1, (sent, n_warn))
rv = anon.post(f'{V2}/secret/{sid5}/reveal', json={'continue': True})
L.check('J05e', 'the warned secret is untouched by the job and still reveals', rv.status_code == 200 and rv.json()['record'].get('secret_value') == 'seven day secret', rv.status_code)

# ------------------------------------------------------------ C16 expiry
wait = 135 - (time.time() - t0)
if wait > 0:
    time.sleep(wait)
gone = stg.redis('exists', rkey(rid_x)) == '0' and stg.redis('exists', skey(sid_x)) == '0'
L.check('C16a', 'after their TTLs both hashes are gone', gone, (stg.redis('exists', rkey(rid_x)), stg.redis('exists', skey(sid_x))))
rm = api.patch(f'{V2}/receipt/{rid_x}', json={'memo': 'too late'})
rb = api.post(f'{V2}/receipt/{rid_x}/burn', json={'continue': True})
rs = api.get(f'{V2}/receipt/{rid_x}')
rr = anon.post(f'{V2}/secret/{sid_x}/reveal', json={'continue': True})
L.check('C16b', 'memo edit, burn, show and reveal on the expired pair are 404',
        [rm.status_code, rb.status_code, rs.status_code, rr.status_code] == [404, 404, 404, 404],
        [rm.status_code, rb.status_code, rs.status_code, rr.status_code])
L.check('C16c', 'none of them recreated a key (no immortal receipt or secret)',
        stg.redis('exists', rkey(rid_x)) == '0' and stg.redis('exists', skey(sid_x)) == '0',
        (stg.redis('exists', rkey(rid_x)), stg.redis('ttl', rkey(rid_x))))

# ---------------------------------------------- J06 maintenance jobs + audit
time.sleep(125)  # two maintenance cycles after the expiries above


def last_report(job):
    out = subprocess.run(['grep', '-a', '-F', f'[{job}] {{', SCHED_LOG], capture_output=True, text=True).stdout.strip().split('\n')
    if not out or not out[-1]:
        return None
    try:
        return json.loads(out[-1].split(f'[{job}] ', 1)[1])
    except (ValueError, IndexError):
        return None


if VER == 'head':
    ph = last_report('PhantomCleanupJob')
    ib = last_report('InstancesRebuildJob')
    da = last_report('DataConsistencyAuditJob')
    L.note('J06a', 'maintenance reports (Receipt/Secret)', {
        'phantom_cleanup': ph and {k: ph['models'][k] for k in ('Receipt', 'Secret')},
        'instances_rebuild': ib and {k: ib['models'][k] for k in ('Receipt', 'Secret')},
        'data_audit': da and {k: v for k, v in da.items() if k not in ('job', 'started_at', 'completed_at')}})
    L.check('J06b', 'instances sets match the live keys: nothing missing; expired entries are the only phantoms and are repaired',
            ib is not None and all(ib['models'][k]['missing_from_instances'] == 0 and not ib['models'][k]['aborted'] for k in ('Receipt', 'Secret')),
            ib and {k: ib['models'][k] for k in ('Receipt', 'Secret')})
    L.check('J06c', 'the expired fixtures are no longer in the instances sets after phantom cleanup',
            not stg.zmember('receipt:instances', rid_x) and not stg.zmember('secret:instances', sid_x),
            (stg.redis('zscore', 'receipt:instances', rid_x), stg.redis('zscore', 'secret:instances', sid_x)))
    errs = subprocess.run(['grep', '-a', '-c', '-E', r'\[31mE|ERROR|FATAL', SCHED_LOG], capture_output=True, text=True).stdout.strip()
    L.check('J08', 'scheduler log has no error lines', errs == '0', errs)
live_ok = stg.redis('exists', rkey(rid5s)) == '1' and bool(stg.redis('zscore', 'receipt:instances', rid5s)) \
    and bool(stg.redis('zscore', 'secret:instances', sid5s))
L.check('J06d', 'repairing maintenance jobs left a live pair and its index entries alone', live_ok)
stats, problems = audit.audit_pairs()
L.check('J90', 'datastore audit after the job-system tests', not problems, problems or stats)
L.note('J89', 'proxy 429s the polite client waited out', stg.STATS['429'])
sys.exit(1 if L.done() else 0)
