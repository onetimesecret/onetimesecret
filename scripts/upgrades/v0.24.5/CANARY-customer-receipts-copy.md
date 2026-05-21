# Canary procedure: copy_customer_receipts_zset

## 1. Goal

Dry-run preview reads source state but never opens a write path on the target.
That hides three failure modes:

- **Auth/cluster** — wrong `--target-url`, missing AUTH/ACL, or wrong DB index.
- **Pipelined-write surface** — `pipelined(exception: false)` swallows individual
  command errors; only an executed write reveals them.
- **Score clobbering** — if a target ZSET already has the same member at a
  different score, `ZADD` overwrites with the source score. No way to detect
  this without writing.

The canary procedure runs the real copier against a single, well-understood
customer, then runs the paired validator against the same scope.

## 2. Prerequisites

- Source URL reachable: `redis-cli -u "$SRC" PING` returns `PONG`.
- Target URL reachable: `redis-cli -u "$TGT" PING` returns `PONG`.
- Lookup files exist:
  - `data/upgrades/v0.24.5/customer/email_to_objid.json`
  - `data/upgrades/v0.24.5/organization/customer_objid_to_org_objid.json`
- Working directory is the project root.

```bash
export SRC='redis://v1-redis:6379/6'
export TGT='redis://v2-valkey:6379/0'
```

## 3. Procedure

### 3a. Pick the canary customer

Criteria: known email; ~5–20 receipts; has an org mapping. Confirm:

```bash
EMAIL='canary@example.com'

# 1. has receipts (5–20 ideal)
redis-cli -u "$SRC" ZCARD "customer:${EMAIL}:metadata"

# 2. resolves to a cust_objid
CUST_OBJID=$(jq -r --arg e "$EMAIL" '.[$e] // empty' \
  data/upgrades/v0.24.5/customer/email_to_objid.json)
echo "cust_objid=${CUST_OBJID:?email not in customer lookup}"

# 3. has an org mapping
ORG_OBJID=$(jq -r --arg c "$CUST_OBJID" '.[$c] // empty' \
  data/upgrades/v0.24.5/organization/customer_objid_to_org_objid.json)
echo "org_objid=${ORG_OBJID:?cust_objid not in org lookup}"
```

### 3b. Snapshot v1 source state

```bash
redis-cli -u "$SRC" ZCARD "customer:${EMAIL}:metadata"
redis-cli -u "$SRC" ZRANGE "customer:${EMAIL}:metadata" 0 -1 WITHSCORES \
  > /tmp/canary-src-zrange.txt
wc -l /tmp/canary-src-zrange.txt
```

### 3c. Snapshot v2 target state (may be empty)

```bash
redis-cli -u "$TGT" ZCARD "customer:${CUST_OBJID}:receipts"
redis-cli -u "$TGT" ZCARD "organization:${ORG_OBJID}:receipts"
redis-cli -u "$TGT" ZRANGE "customer:${CUST_OBJID}:receipts" 0 -1 WITHSCORES \
  > /tmp/canary-tgt-pre.txt
```

If `customer:${CUST_OBJID}:receipts` is non-empty pre-copy, sample one of its
members and verify its current score. After the copy, if that member's score
changed, you have score-clobbering. The validator surfaces this automatically;
this manual check is your sanity tie-break.

### 3d. Build single-entry lookup files

```bash
TMPDIR=$(mktemp -d)
jq -n --arg e "$EMAIL" --arg o "$CUST_OBJID" '{($e): $o}' \
  > "$TMPDIR/email_to_objid.json"
jq -n --arg c "$CUST_OBJID" --arg o "$ORG_OBJID" '{($c): $o}' \
  > "$TMPDIR/customer_objid_to_org_objid.json"
cat "$TMPDIR/email_to_objid.json" "$TMPDIR/customer_objid_to_org_objid.json"
```

### 3e. Run the copier (canary scope, --execute)

```bash
ruby scripts/upgrades/v0.24.5/copy_customer_receipts_zset.rb \
  --source-url="$SRC" \
  --target-url="$TGT" \
  --customer-lookup="$TMPDIR/email_to_objid.json" \
  --org-lookup="$TMPDIR/customer_objid_to_org_objid.json" \
  --execute --verbose
echo "exit=$?"
```

The copier still SCANs all `customer:*:metadata` on source, but only writes for
keys whose email is in the temp lookup — the others fall through as
`missing_customer_lookup`.

### 3f. Run the paired validator (same scope)

```bash
ruby scripts/upgrades/v0.24.5/validate_customer_receipts_copy.rb \
  --source-url="$SRC" \
  --target-url="$TGT" \
  --customer-lookup="$TMPDIR/email_to_objid.json" \
  --org-lookup="$TMPDIR/customer_objid_to_org_objid.json" \
  --sample-size=20 --verbose
echo "exit=$?"
```

### 3g. Promote to full copy

Only after both step 3e and 3f exit 0 and the validator prints `RESULT: PASS`:

```bash
ruby scripts/upgrades/v0.24.5/copy_customer_receipts_zset.rb \
  --source-url="$SRC" --target-url="$TGT" --execute
ruby scripts/upgrades/v0.24.5/validate_customer_receipts_copy.rb \
  --source-url="$SRC" --target-url="$TGT"
```

## 4. Pass / fail criteria

| Signal | Meaning | Action |
|---|---|---|
| Copier exit 0, summary `Errors: 0` | Pipeline writes succeeded | Continue |
| Copier exit 1, errors listed | Per-key Redis error | Inspect; do NOT continue |
| Validator exit 0, `RESULT: PASS` | Full parity, sampled scores match | Promote |
| Validator `Score mismatches > 0` | **Score clobber** — pre-existing target had different score | STOP. Investigate target provenance before promoting |
| Validator `Member missing target` | Copier didn't write or write was lost | Re-run copier; if persistent, investigate ACL/connectivity |
| Validator `ZCARD mismatch` (target > source, not from re-copy) | Target was pre-seeded from elsewhere | STOP. Decide whether `--allow-target-superset` is acceptable |
| Validator `Participation missing` | Reverse index gap; Familia v2 `destroy!` will leak | STOP. Re-run copier; if persistent, file bug |

`ZRANGE WITHSCORES` outputs alternating member/score lines (member on odd lines,
score on even). Diff `/tmp/canary-src-zrange.txt` against
`redis-cli -u "$TGT" ZRANGE "customer:${CUST_OBJID}:receipts" 0 -1 WITHSCORES`
for a manual verification of the canary key.

## 5. Rollback (canary only)

The copier is additive and idempotent on `(score, member)` matches. "Rollback"
means deleting the target keys for the canary customer only. **Do not run these
during a real migration** — they remove production state.

```bash
# Confirm scope first
echo "Will DEL: customer:${CUST_OBJID}:receipts organization:${ORG_OBJID}:receipts"

# Per-receipt participation entries (one DEL per receipt objid)
redis-cli -u "$TGT" ZRANGE "customer:${CUST_OBJID}:receipts" 0 -1 \
  | while read -r OBJID; do
      [ -n "$OBJID" ] && redis-cli -u "$TGT" SREM \
        "receipt:${OBJID}:participations" "organization:${ORG_OBJID}:receipts"
    done

# Then drop the ZSETs
redis-cli -u "$TGT" DEL "customer:${CUST_OBJID}:receipts"
redis-cli -u "$TGT" DEL "organization:${ORG_OBJID}:receipts"
```

`SREM` (not `DEL`) on `receipt:{objid}:participations` because that set may
contain other key references (e.g. `custom_domain:{id}:receipts`) written by a
different pipeline stage. Dropping the whole key would corrupt v2 cleanup state.

Cleanup the temp lookup dir when done:

```bash
rm -rf "$TMPDIR"
```
