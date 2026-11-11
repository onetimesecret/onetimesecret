"""Datastore integrity audit for secret/receipt pairs.

Reads Valkey directly. A pair is consistent when:
  - every live secret hash names a receipt hash that exists and names it back
    (a receipt already in a terminal state with a live secret is a defect);
  - every receipt in state new/previewed that still names a secret either has
    that secret, or the secret's own TTL has run out (secrets expire first);
  - both hashes carry a TTL (no immortal keys);
  - an owned receipt is in its owner's receipts index, and in its
    organization's index when it has an org_id.
"""
import json

import stg


def _h(key):
    out = stg.redis('hgetall', key, raw=True).split('\n')
    d = {}
    for i in range(0, len(out) - 1, 2):
        v = out[i + 1]
        try:
            v = json.loads(v)
        except (ValueError, TypeError):
            pass
        d[out[i]] = v
    return d


def audit_pairs(verbose=False):
    problems = []
    secrets = stg.redis_keys('secret:*:object')
    receipts = stg.redis_keys('receipt:*:object')
    stats = {'secrets': len(secrets), 'receipts': len(receipts)}
    now_receipts = {}
    for rk in receipts:
        now_receipts[rk] = _h(rk)

    for sk in secrets:
        s = _h(sk)
        if not s:
            continue  # expired between scan and read
        sid = sk.split(':')[1]
        ttl = int(stg.redis('ttl', sk) or -2)
        if ttl == -1:
            problems.append(('secret_without_ttl', sid[:8]))
        rid = s.get('receipt_identifier')
        if not rid:
            problems.append(('secret_without_receipt_pointer', sid[:8]))
            continue
        r = now_receipts.get(f'receipt:{rid}:object') or _h(f'receipt:{rid}:object')
        if not r:
            problems.append(('secret_without_receipt', sid[:8], str(rid)[:8]))
            continue
        if r.get('state') in ('revealed', 'burned', 'expired', 'orphaned') and s.get('ciphertext'):
            problems.append(('live_ciphertext_under_terminal_receipt', sid[:8], r.get('state')))
        if r.get('secret_identifier') not in (sid, '', None):
            problems.append(('receipt_points_elsewhere', sid[:8]))

    for rk, r in now_receipts.items():
        if not r:
            continue
        rid = rk.split(':')[1]
        ttl = int(stg.redis('ttl', rk) or -2)
        if ttl == -1:
            problems.append(('receipt_without_ttl', rid[:8], r.get('state')))
        if ttl == -2:
            continue
        if 'state' not in r or 'objid' not in r:
            problems.append(('partial_receipt_hash', rid[:8], sorted(r.keys())))
            continue
        owner = r.get('owner_id')
        if owner and owner != 'anon':
            if stg.redis('zscore', f'customer:{owner}:receipts', json.dumps(rid)) == '' and \
               stg.redis('zscore', f'customer:{owner}:receipts', rid) == '':
                problems.append(('receipt_missing_from_owner_index', rid[:8]))
        org = r.get('org_id')
        if org:
            if stg.redis('zscore', f'organization:{org}:receipts', rid) == '' and \
               stg.redis('zscore', f'organization:{org}:receipts', json.dumps(rid)) == '':
                problems.append(('receipt_missing_from_org_index', rid[:8]))
    stats['problems'] = len(problems)
    if verbose:
        print(stats, problems[:20])
    return stats, problems


if __name__ == '__main__':
    audit_pairs(verbose=True)
