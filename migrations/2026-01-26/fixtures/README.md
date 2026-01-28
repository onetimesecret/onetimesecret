# Test Fixtures for Migration Testing

This directory contains sample data for testing the v0.23->v0.24 migration pipeline.

## Fixture Files

### Input (V1 Format)
- `customer_dump.jsonl` - 5 customer records with various configurations
- `customdomain_dump.jsonl` - 3 custom domain records
- `metadata_dump.jsonl` - 10 receipt records (various ownership scenarios)
- `secret_dump.jsonl` - 5 secret records (including one with binary data)

### Lookup Files
- `email_to_org_objid.json` - Organization lookup (4 of 5 customers mapped)
- `email_to_objid.json` - Customer email->objid mapping

## Test Scenarios Covered

### Customer Variations
1. Regular customer with all fields
2. Customer without email (edge case)
3. Colonel role customer
4. Anonymous role customer
5. Customer with high counter values

### Custom Domain Variations
1. Domain with valid org mapping
2. Domain with missing org mapping (tests followup file)
3. Domain with brand/logo hashes

### Receipt Variations
1. Anonymous receipt (custid=anon)
2. Anonymous receipt (custid=nil)
3. Named receipt with valid owner lookup
4. Named receipt with missing owner lookup
5. Receipt with share_domain set
6. Receipt with state='viewed' (tests transform)
7. Receipt with state='received' (tests transform)
8. Receipt with state='new' (no transform)
9. Receipt with viewed/received timestamps
10. Receipt with long lifespan

### Secret Variations
1. Normal text secret
2. Secret with passphrase
3. Burned secret
4. Secret with binary ciphertext (tests preservation)
5. Secret with TTL

## Usage

```bash
# Copy fixtures to exports directory for testing
cp -r fixtures/* /path/to/test/exports/

# Or run tests that use fixtures directly
bundle exec try try/migrations/
```

## Generating New Fixtures

To create fixtures from real (anonymized) data:

```ruby
# Dump a small sample
dumper = KeyDumper.new(
  redis_url: 'redis://localhost:6379',
  output_dir: 'fixtures',
  dry_run: false
)
# Manually select and copy records
```

Note: All email addresses and identifiers in fixtures are fake/anonymized.
