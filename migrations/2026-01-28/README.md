# migrations/2026-01-28/README.md
---

# Data Migration - Kiba

┌─────────────┐ ┌───────────────┐ ┌───────────────┐
│ Redis DBs │────▶│ dump_keys.rb │────▶│ _\_dump.jsonl │
│ 6,7,8,11 │ └───────────────┘ └───────┬───────┘
└─────────────┘ │
▼
┌─────────────────────────────────────────────────────────────────┐
│ Kiba Pipeline │
│ ┌──────────┐   ┌──────────┐ ┌──────────┐ ┌──────────┐ │
│ │ Customer │──▶│ Org │──▶│ Domain │──▶│ Receipt/ │ │
│ │ Transform│   │ Generate │ │ Transform│ │ Secret │ │
│ └────┬─────┘   └────┬─────┘ └────┬─────┘ └──────────┘ │
│ │ │ │ │
│ ▼ ▼ ▼ │
│ email→cust email→org fqdn→domain │
│ lookup lookup lookup │
│ │ │ │ │
│ └──────────────┴──────────────┘ │
│ │ │
│ ▼ │
│ LookupRegistry │
└─────────────────────────────────────────────────────────────────┘
│
▼
_\_transformed.jsonl
│
▼
load_keys.rb → Redis
