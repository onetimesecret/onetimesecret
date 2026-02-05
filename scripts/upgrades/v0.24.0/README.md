# Onetime Secret Data Migration - v0.23 -> v0.24

> **Relocated**: These scripts were moved from `migrations/2026-01-26/` to
> `scripts/upgrades/v0.24.0/` for better organization. Git history is preserved.

```

Dependency Graph

Customer ──────────────────┬──────────────────┐
    │                      │                  │
    ▼                      ▼                  │
Organization          CustomDomain            │
    │                      │                  │
    └──────────┬───────────┘                  │
               ▼                              ▼
            Receipt ◄─────────────────────Secret
```
