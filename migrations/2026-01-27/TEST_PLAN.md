# Migration Test Plan - v0.23 to v0.24

## Overview

Test strategy for the Redis data migration pipeline that transforms v1 (email-based identifiers) to v2 (UUIDv7-based identifiers).

**Data volumes:**
- DB6: 727 keys (customers, custom domains)
- DB7: 2,507 keys (metadata/receipts)
- DB8: 741 keys (secrets)

## Pipeline Architecture

This migration (2026-01-27) uses a hybrid approach:

- **Extract/Transform phases**: Use scripts from `../2026-01-26/`
- **Load phase**: Uses `load_keys.rb` (this directory)
- **Shared infrastructure**: `lib/` provides common utilities

### Script Locations

| Phase | Script | Location |
|-------|--------|----------|
| 1. Dump | `dump_keys.rb` | `../2026-01-26/` |
| 2. Enrich IDs | `enrich_with_identifiers.rb` | `../2026-01-26/` |
| 3. Transform | `01-customer/transform.rb` | `../2026-01-26/` |
| 3. Transform | `02-organization/generate.rb` | `../2026-01-26/` |
| 3. Transform | `03-customdomain/transform.rb` | `../2026-01-26/` |
| 3. Transform | `04-receipt/transform.rb` | `../2026-01-26/` |
| 3. Transform | `05-secret/transform.rb` | `../2026-01-26/` |
| 4. Enrich Original | `enrich_with_original_record.rb` | `../2026-01-26/` |
| 5. Create Indexes | `*/create_indexes.rb` | `../2026-01-26/` |
| 6. Load | `load_keys.rb` | This directory |

## 1. Unit Tests

### 1.1 IdentifierEnricher (`../2026-01-26/enrich_with_identifiers.rb`)

Location: `../2026-01-26/try/identifier_enricher_try.rb`

```
Test Cases:
- UUIDv7 generation from timestamp produces valid format
- UUIDv7 timestamp bytes match input seconds
- ExtID derivation is deterministic (same input -> same output)
- ExtID prefix matches model (customer->ur, customdomain->cd)
- ExtID length is 27 chars (2 prefix + 25 base36)
- Only :object records with created field are enriched
- Key renames: :metadata -> :receipts suffix
- Records without created field are skipped
- JSON parse errors are collected, not thrown
- Dry-run mode counts without writing
```

### 1.2 KeyDumper (`../2026-01-26/dump_keys.rb`)

Location: `../2026-01-26/try/key_dumper_try.rb`

```
Test Cases:
- Model mapping routes keys to correct output files
- DUMP data is valid base64
- TTL preservation (-1 for no expiry, positive for expiry)
- Created timestamp extracted from hash :object records
- Keys expiring during scan are skipped gracefully
- Manifest includes accurate statistics
- Password redacted in manifest source_url
```

### 1.3 CustomerTransformer (`../2026-01-26/01-customer/transform.rb`)

Location: `../2026-01-26/try/customer_transformer_try.rb`

```
Test Cases:
- custid transformed from email to objid
- v1_custid preserves original email
- objid/extid taken from enriched JSONL, not hash
- v1_identifier tracks original key
- migration_status set to 'completed'
- migrated_at timestamp present
- Related keys renamed: customer:{email}:* -> customer:{objid}:*
- :metadata suffix renamed to :receipts
- Records without :object are skipped with error logged
- Records without objid are skipped
```

### 1.4 CustomDomainTransformer (`../2026-01-26/03-customdomain/transform.rb`)

Location: `../2026-01-26/try/customdomain_transformer_try.rb`

```
Test Cases:
- Key prefix changes: customdomain -> custom_domain
- custid (email) -> org_id (via email_to_org lookup)
- v1_custid preserves original email
- Missing org mapping logged to followup file
- FQDN->objid mapping written for downstream
- V1 index keys (owners, display_domains) skipped
- Related hashes (brand, logo, icon) renamed correctly
```

### 1.5 ReceiptTransformer (`../2026-01-26/04-receipt/transform.rb`)

Location: `../2026-01-26/try/receipt_transformer_try.rb`

```
Test Cases:
- Key renamed: metadata:{id}:object -> receipt:{id}:object
- State transforms: 'viewed'->'previewed', 'received'->'revealed'
- viewed/received fields copied to previewed/revealed (backward compat)
- Anonymous receipts (custid=anon) get owner_id='anon'
- Non-anonymous: owner_id from email_to_customer lookup
- org_id from email_to_org lookup
- domain_id from fqdn_to_domain lookup (when share_domain set)
- Missing lookups tracked separately
```

### 1.6 OriginalRecordEnricher (`../2026-01-26/enrich_with_original_record.rb`)

Location: `../2026-01-26/try/original_record_enricher_try.rb`

```
Test Cases:
- _original_record JSON contains: object, data_types, key, db, exported_at
- Binary fields (secrets) encoded as {"_binary": "<base64>"}
- Invalid UTF-8 strings handled via base64 encoding
- v1_identifier used to lookup original record
- Related records (non-:object) pass through unchanged
- Missing v1 records logged, not fatal
```

### 1.7 Index Creators (`../2026-01-26/*/create_indexes.rb`)

Location: `../2026-01-26/try/index_creator_try.rb`

```
Test Cases:
- customer:instances ZADD with created timestamp score
- customer:email_index HSET values are JSON-encoded
- customer:extid_lookup and objid_lookup populated
- customer:role_index:{role} SADD for valid roles
- Counter aggregation (secrets_created, etc.)
- Backfill for customers missing from v1 instance index
- organization:contact_email_index maps email->org_objid
- custom_domain:display_domain_index maps fqdn->domain_objid
```

### 1.8 KeyLoader (`load_keys.rb`)

Location: `try/key_loader_try.rb`

```
Test Cases:
- RESTORE uses correct TTL (0 for no expiry, ms for expiry)
- RESTORE with REPLACE flag overwrites existing
- ZADD/HSET/SADD/INCRBY commands executed correctly
- Unknown commands rejected
- Model-specific DB targeting (customer->6, receipt->7, secret->8)
- Dependency order: customer -> organization -> customdomain -> receipt -> secret
- Dry-run mode skips Redis connection entirely
```

## 2. Integration Tests

### 2.1 Pipeline Order Validation

Location: `../2026-01-26/try/pipeline_order_try.rb`

```
Test Cases:
- Running phase 3 (customdomain) without phase 2 (organization) fails with clear error
- Running phase 4 (receipt) without phase 1-3 fails with missing index error
- Full pipeline in order succeeds
- Index files exist after each phase completes
```

### 2.2 Lookup Consistency

Location: `../2026-01-26/try/lookup_consistency_try.rb`

```
Test Cases:
- email_to_org_objid.json entries match organization_indexes.jsonl
- email_to_objid.json entries match customer_indexes.jsonl
- fqdn_to_objid.json entries match customdomain_indexes.jsonl
- All lookup files are valid JSON
- Bidirectional lookups resolve correctly
```

### 2.3 Data Integrity

Location: `../2026-01-26/try/data_integrity_try.rb`

```
Test Cases:
- Encrypted fields (secret ciphertext) unchanged through transform
- Base64 DUMP data round-trips: DUMP->base64->decode->RESTORE
- TTL preserved across pipeline stages
- No data loss: input record count == output record count per model
- Hash field values match after RESTORE
```

### 2.4 Audit Trail Completeness

Location: `../2026-01-26/try/audit_trail_try.rb`

```
Test Cases:
- All :object records have v1_identifier
- All :object records have _original_record after enrichment
- _original_record.object matches v1 hash fields
- migration_status == 'completed' for all transformed records
- migrated_at timestamp present and valid
```

## 3. Regression Tests (Known Issues)

### 3.1 Missing Lookup Handling

Location: `../2026-01-26/try/missing_lookup_try.rb`

```
Test Cases:
- Customer with email not in v1 data: transform proceeds, org_id null
- Domain with custid not in org mapping: logged to followup_unmapped_custids.json
- Receipt with custid not in customer mapping: owner_id null, logged
- Receipt with share_domain not in domain mapping: domain_id null, logged
- Pipeline does not abort on missing lookups
```

### 3.2 Duplicate Email Handling

Location: `../2026-01-26/try/duplicate_handling_try.rb`

```
Test Cases:
- Two customers with same email: last-write-wins in email_index
- Warning logged for duplicate email mappings
- Both customer records transformed (different objids)
```

### 3.3 Binary Data Preservation

Location: `../2026-01-26/try/binary_preservation_try.rb`

```
Test Cases:
- Secret ciphertext with non-UTF8 bytes preserved exactly
- Binary field round-trip: original bytes == restored bytes
- _original_record binary encoding/decoding correct
```

### 3.4 Phase Ordering Violations

Location: `../2026-01-26/try/phase_ordering_try.rb`

```
Test Cases:
- Running transform.rb before enrich_with_identifiers.rb: falls back to hash objid
- Running create_indexes.rb before transform.rb: reads from dump, not transformed
- Running enrich_with_original_record.rb before transforms: nothing to enrich
- Clear error messages for missing prerequisite files
```

## 4. Post-Migration Validation

### 4.1 Referential Integrity

Location: `../2026-01-26/try/referential_integrity_try.rb`

```
Test Cases:
- All customers have corresponding organization (1:1)
- All custom domains have valid org_id (FK to organization)
- All receipts with non-anon custid have valid owner_id (FK to customer)
- All receipts with owner_id have matching org_id
- All receipts with share_domain have valid domain_id (FK to customdomain)
```

### 4.2 Index Count Validation

Location: `../2026-01-26/try/index_counts_try.rb`

```
Test Cases:
- customer:instances ZCARD == customer object count
- customer:email_index HLEN == customers with email
- organization:instances ZCARD == organization count
- custom_domain:display_domain_index HLEN == custom domain count
- receipt:instances ZCARD == receipt object count
- secret:instances ZCARD == secret object count
```

### 4.3 Counter Validation

Location: `../2026-01-26/try/counter_validation_try.rb`

```
Test Cases:
- customer:secrets_created == SUM of individual secrets_created
- customer:secrets_shared == SUM of individual secrets_shared
- customer:secrets_burned == SUM of individual secrets_burned
- customer:emails_sent == SUM of individual emails_sent
```

## 5. Test Fixtures

### 5.1 Sample Data Generation

Create minimal representative fixtures in `../2026-01-26/fixtures/`:

```
fixtures/
  customer_dump.jsonl        # 5 customers (various roles, with/without email)
  customdomain_dump.jsonl    # 3 domains (different custids)
  metadata_dump.jsonl        # 10 receipts (anon, named, with share_domain)
  secret_dump.jsonl          # 5 secrets (various states, one with binary)
  email_to_org_objid.json    # Lookup for 4 of 5 customers (1 missing)
  email_to_objid.json        # Customer email->objid mapping
```

### 5.2 Fixture Format

```json
// customer_dump.jsonl (one line per record)
{"key":"customer:user@example.com:object","type":"hash","ttl_ms":-1,"db":6,"dump":"<base64>","created":1706000000}
{"key":"customer:user@example.com:receipts","type":"zset","ttl_ms":-1,"db":6,"dump":"<base64>"}
```

## 6. Test Execution

### Running All Migration Tests

```bash
# Extract/Transform tests (2026-01-26)
bundle exec try --agent ../2026-01-26/try/

# Load tests (this directory)
bundle exec try --agent try/

# Verbose mode for debugging
bundle exec try --verbose --fails ../2026-01-26/try/

# Single test file with stack traces
bundle exec try --verbose --stack ../2026-01-26/try/identifier_enricher_try.rb
```

### Test Database Setup

Tests use DB 14 and 15 as scratch databases (matching existing pattern in the codebase).

```ruby
# Setup
@test_db = 14
@scratch_db = 15
@redis = Redis.new(url: "redis://127.0.0.1:6379/#{@test_db}")
@redis.flushdb

# Teardown
@redis.flushdb
@redis.close
```

## 7. Implementation Priority

1. **Phase 1 (Critical):** Unit tests for IdentifierEnricher and transformers
2. **Phase 2 (High):** Integration tests for pipeline order and lookup consistency
3. **Phase 3 (Medium):** Regression tests for known edge cases
4. **Phase 4 (Low):** Post-migration validation (can be manual initially)

## 8. Acceptance Criteria

Migration is considered tested when:

1. All unit tests pass in agent mode
2. Full pipeline runs against fixture data without errors
3. Index counts match record counts
4. Binary data round-trips correctly
5. Missing lookup handling does not cause pipeline abort
6. Audit trail fields present on all transformed :object records
