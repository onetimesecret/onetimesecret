Summary: Production Catalog Sync Pattern
┌───────────────────────┬────────────────────────────────┬──────────────────────┐
│       Scenario        │             Action             │      Frequency       │
├───────────────────────┼────────────────────────────────┼──────────────────────┤
│ Product/Price webhook │ Incremental upsert             │ Real-time            │
├───────────────────────┼────────────────────────────────┼──────────────────────┤
│ Server boot           │ Validate cache, async repair   │ On boot              │
├───────────────────────┼────────────────────────────────┼──────────────────────┤
│ Drift detection       │ Compare and reconcile          │ Hourly cron          │
├───────────────────────┼────────────────────────────────┼──────────────────────┤
│ Full resync           │ Rebuild alongside, atomic swap │ Manual/disaster only │
└───────────────────────┴────────────────────────────────┴──────────────────────┘

Key Principles:

1. Webhooks are primary - Real-time updates, not polling
2. Never clear-and-rebuild - Atomic upserts only
3. Fetch fresh on webhook - Don't trust webhook payload alone
4. Idempotency is mandatory - Track event IDs, handle duplicates
5. Prices are immutable - Archive, don't delete
6. Distributed locks - Handle multi-process concurrency
7. Drift detection - Periodic validation catches missed webhooks
8. Cache TTL as fallback - 12h expiry triggers refresh if webhooks fail


Production systems typically:
1. Trust the webhook-populated cache on boot
2. Run validation async after boot
3. Schedule periodic drift detection (hourly/daily)

Stripe's Recommended Architecture

┌─────────────────────────────────────────────────────────────┐
│                    Stripe (Source of Truth)                  │
└─────────────────────────────────────────────────────────────┘
                              │
                    Webhooks  │  API (validation only)
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Your Webhook Handler                       │
│  • Verify signature                                          │
│  • Check idempotency (StripeWebhookEvent)                   │
│  • Queue for processing                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Background Worker                          │
│  • Fetch full object from API (webhook has snapshot)        │
│  • Update Redis cache atomically                            │
│  • Mark event processed                                      │
└─────────────────────────────────────────────────────────────┘
                              │
                              ▼
┌─────────────────────────────────────────────────────────────┐
│                   Redis Cache (Familia)                      │
│  • Plan objects with 12h TTL                                │
│  • Stripe snapshot for recovery                             │
│  • Atomic updates (no clear-and-rebuild)                    │
└─────────────────────────────────────────────────────────────┘

  Stripe Best Practices Alignment
  ┌──────────────────────────────────────────────┬──────────────────────────────────────┐
  │            Stripe Recommendation             │          Our Implementation          │
  ├──────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Webhooks are primary sync mechanism          │ ✅ Incremental webhook updates       │
  ├──────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Never clear-and-rebuild                      │ ✅ Upsert pattern                    │
  ├──────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Fetch fresh on webhook (payload is snapshot) │ ✅ Stripe::Price.retrieve in handler │
  ├──────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Prices are immutable - archive, don't delete │ ✅ Soft-delete via active: false     │
  ├──────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Track event IDs for idempotency              │ ✅ Existing StripeWebhookEvent       │
  ├──────────────────────────────────────────────┼──────────────────────────────────────┤
  │ Distributed locks for concurrent access      │ ⚡ Add for full sync only            │
  └──────────────────────────────────────────────┴──────────────────────────────────────┘
