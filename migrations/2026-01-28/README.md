# Kiba ETL Migration Pipeline

Redis data migration from Familia v1 to v2 using Kiba ETL framework.

## Architecture

```
┌─────────────┐     ┌───────────────┐     ┌───────────────┐
│ Redis DBs   │────▶│ dump_keys.rb  │────▶│ *_dump.jsonl  │
│ 6,7,8,11    │     └───────────────┘     └───────┬───────┘
└─────────────┘                                   │
                                                  ▼
┌─────────────────────────────────────────────────────────────────┐
│                        Kiba Pipeline                            │
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
└─────────────────────────────────────────────────────────────────┘
                                                  │
                                                  ▼
                                         *_transformed.jsonl
                                                  │
                                                  ▼
                                          load_keys.rb → Redis
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

### Dump and Load

```bash
# Export from source Redis
ruby dump_keys.rb --all

# Load to target Redis
ruby load_keys.rb --input-dir=exports --target-db=0
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
