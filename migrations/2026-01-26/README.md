# Onetime Secret Data Migration - v0.23 -> v0.24 (2026-01-26)

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
