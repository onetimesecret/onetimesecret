# Kiba ETL Migration Pipeline

Redis data migration from Familia v1 (multi-db) to v2 (single DB 0) using Kiba ETL framework.

## Architecture

```
┌─────────────┐     ┌───────────────┐     ┌───────────────┐
│ Redis DBs   │────▶│  00_dump.rb   │────▶│ *_dump.jsonl  │
│ 6,7,8,11    │     └───────────────┘     └───────┬───────┘
└─────────────┘                                   │
                                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                     Kiba Pipeline (Phases 1-5)                  │
│  ┌──────────┐   ┌──────────┐   ┌──────────┐   ┌──────────┐      │
│  │ Customer │──▶│   Org    │──▶│  Domain  │──▶│ Receipt/ │      │
│  │ Transform│   │ Generate │   │ Transform│   │  Secret  │      │
│  └────┬─────┘   └────┬─────┘   └────┬─────┘   └──────────┘      │
│       │              │              │                           │
│       ▼              ▼              ▼                           │
│   email→cust     email→org     fqdn→domain                      │
│    lookup         lookup         lookup                         │
│       │              │              │                           │
│       └──────────────┴──────────────┘                           │
│                      │                                          │
│                      ▼                                          │
│              LookupRegistry                                     │
│                      │                                          │
│       ┌──────────────┴──────────────┐                           │
│       ▼                             ▼                           │
│   IndexGenerator ──────────▶ RoutingDestination                 │
│   (yields multiple)          (routes by type)                   │
└─────────────────────────────────────────────────────────────────┘
              │                              │
              ▼                              ▼
     *_transformed.jsonl            *_indexes.jsonl
              │                              │
              └──────────┬───────────────────┘
                         ▼
                    06_load.rb → Redis/Valkey DB 0
                    (RESTORE + ZADD/HSET/SADD)
```

## Quick Start

```bash
cd migrations/2026-01-28

# Install dependencies
bundle install

# Run tests
bundle exec rspec

# Dry run (validate without writing)
bundle exec ruby jobs/pipeline.rb --dry-run

# Run full pipeline
bundle exec ruby jobs/pipeline.rb
```

## Commands

### Pipeline Orchestrator

```bash
# Run all phases
bundle exec ruby jobs/pipeline.rb

# Dry run (parse and count only)
bundle exec ruby jobs/pipeline.rb --dry-run

# Run specific phases
bundle exec ruby jobs/pipeline.rb --phases=1,2,3

# Continue from last successful phase
bundle exec ruby jobs/pipeline.rb --continue

# Strict mode (filter invalid records)
bundle exec ruby jobs/pipeline.rb --strict
```

### Individual Phase Jobs

```bash
# Phase 1: Customer transform
bundle exec ruby jobs/01_customer.rb --dry-run
bundle exec ruby jobs/01_customer.rb --input-file=../exports/customer/customer_dump.jsonl

# Phase 2: Organization generation
bundle exec ruby jobs/02_organization.rb --dry-run

# Phase 3: CustomDomain transform
bundle exec ruby jobs/03_customdomain.rb --dry-run

# Phase 4: Receipt transform
bundle exec ruby jobs/04_receipt.rb --dry-run

# Phase 5: Secret transform
bundle exec ruby jobs/05_secret.rb --dry-run
```

### Dump and Load (Kiba Jobs)

```bash
# Phase 0: Export from source Redis
bundle exec ruby jobs/00_dump.rb
bundle exec ruby jobs/00_dump.rb --dry-run
bundle exec ruby jobs/00_dump.rb --model=customer

# Phase 6: Load to target Redis/Valkey
bundle exec ruby jobs/06_load.rb --dry-run
bundle exec ruby jobs/06_load.rb --valkey-url=redis://localhost:6379
bundle exec ruby jobs/06_load.rb --model=customer
bundle exec ruby jobs/06_load.rb --skip-indexes   # Records only
bundle exec ruby jobs/06_load.rb --skip-records   # Indexes only
```

### Tests

```bash
# Run all tests
bundle exec rspec

# Run with documentation format
bundle exec rspec --format documentation

# Run specific spec file
bundle exec rspec spec/transforms/customer/field_transformer_spec.rb

# Run specific test by line
bundle exec rspec spec/transforms/secret/field_transformer_spec.rb:42
```

## Source of Truth

### Lookup Dependencies

See `lib/shared/lookup_registry.rb` for `KNOWN_LOOKUPS` which defines phase dependencies:

```ruby
# lib/shared/lookup_registry.rb
KNOWN_LOOKUPS = {
  email_to_customer: { phase: 1 },
  email_to_org: { phase: 2 },
  customer_to_org: { phase: 2 },
  fqdn_to_domain: { phase: 3 },
  # ...
}
```


### ExtID Prefixes

See `lib/migration.rb` for model prefixes:

```ruby
# lib/migration.rb
EXTID_PREFIXES = {
  'customer' => 'ur',
  'customdomain' => 'cd',
  'organization' => 'on',
  'receipt' => 'rc',
  'secret' => 'se',
}
```

## Output Files

Each phase generates two output files:

| Phase | Data File | Index File |
|-------|-----------|------------|
| 1 | `customer_transformed.jsonl` | `customer_indexes.jsonl` |
| 2 | `organization_transformed.jsonl` | `organization_indexes.jsonl` |
| 3 | `customdomain_transformed.jsonl` | `customdomain_indexes.jsonl` |
| 4 | `receipt_transformed.jsonl` | `receipt_indexes.jsonl` |
| 5 | `secret_transformed.jsonl` | `secret_indexes.jsonl` |

**Data files** contain records with Redis DUMP blobs for RESTORE commands.

**Index files** contain Redis commands (ZADD, HSET, SADD) as JSONL:
```json
{"command":"ZADD","key":"customer:instances","args":[1762193015,"019a4ae3-..."]}
{"command":"HSET","key":"customer:email_index","args":["user@example.com","\"019a4ae3-...\""]}
```

### Index Types by Model

| Model | Indexes Generated |
|-------|-------------------|
| Customer | `instances`, `email_index`, `extid_lookup`, `objid_lookup`, `role_index:{role}` |
| Organization | `instances`, `contact_email_index`, `extid/objid_lookup`, stripe indexes, `{org}:members`, `customer:{id}:participations` |
| CustomDomain | `instances`, `display_domain_index`, `display_domains`, `extid/objid_lookup`, `owners`, `organization:{id}:domains` |
| Receipt | `instances`, `expiration_timeline`, `objid_lookup`, `customer/organization/customdomain:{id}:receipts` |
| Secret | `instances`, `objid_lookup` |
