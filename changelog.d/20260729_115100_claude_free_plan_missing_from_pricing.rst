.. A new scriv changelog fragment.

Fixed
-----

- Restored the Free plan on the pricing page. ``GET /billing/api/plans``
  dropped every plan that had no prices, and the free tier is defined with
  ``prices: []`` — so it passed the ``show_on_plans_page`` gate and was then
  filtered out one line later, leaving the pricing page with only paid plans
  and no way to see what the free tier includes. This regressed when the
  endpoint was refactored to flat per-interval records (#3153) and contradicted
  the catalog loader, which persists price-less plans specifically so they can
  be displayed. The endpoint now emits a single record for a price-less visible
  plan (``amount: 0``, no Stripe price, ``month`` interval). Signed-in
  customers also see the Free tier in the workspace plan grid, where it acts as
  the downgrade path for an active subscription.

- Fixed the billing catalog losing the free tier whenever plans are loaded from
  ``billing.yaml`` rather than Stripe. The loader skipped price-less plans
  outright, so a deployment that started while Stripe was unreachable had no
  free tier in its catalog at all — affecting entitlement materialization as
  well as the pricing page. The same loader backs the billing test fixtures, so
  the entire billing test suite ran against a catalog with no free tier, which
  is why this went unnoticed. The loader now handles config-only plans through
  the same path the Stripe sync uses.
