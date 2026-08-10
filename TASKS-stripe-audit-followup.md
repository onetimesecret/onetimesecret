# Stripe Checkout/Tax Audit — Follow-up Tasks (Medium/Low)

Source: Stripe Checkout/Tax audit 2026-08-07 (branch `fix/4025-currency-migration-tax-policy`).
Critical/high items live in `TASKS-stripe-audit-critical.md`. Nothing here blocks a release;
FU-1 changes runtime behavior, the rest are hygiene/consistency.

## Task states

| Marker            | Meaning                                   |
| ----------------- | ----------------------------------------- |
| `[ ] TODO`        | Not started                               |
| `[~] IN PROGRESS` | Actively being worked (note owner/branch) |
| `[!] BLOCKED`     | Blocked — note blocker inline             |
| `[x] DONE`        | Fixed, tested, merged                     |

---

## FU-1 `[ ] TODO` — MEDIUM: dead idempotent-replay fallback in `ProcessCheckoutSession`

- **Where:** `apps/web/billing/logic/welcome.rb:350-351` (`find_target_organization`)
- **Problem:** The session is retrieved with `expand: %w[subscription customer]`, so
  `checkout_session.customer` is a `Stripe::Customer` object; the
  `is_a?(String) && start_with?('cus_')` guard never matches and the
  `find_by_stripe_customer_id` fallback (priority 2) is dead code. Resolution falls through to
  the customer's default org.
- **Impact:** Matters for `Plans#checkout_redirect` sessions, which carry no `orgid` metadata
  (#4017): replays resolve by default-org instead of by bound Stripe customer.
- **Fix:** Read `customer.id` when expanded (accept both String and object), or drop `customer`
  from the expand list. Coordinate with #4017 (metadata unification may make the fallback moot).

## FU-2 `[ ] TODO` — MEDIUM: `detect_region` divergence between checkout surfaces

- **Where:** `apps/web/billing/controllers/plans.rb:354-358` (hardcodes `'EU'`) vs
  `apps/web/billing/operations/create_checkout_link.rb:189-191` (reads
  `features.regions.current_jurisdiction`, default `'LL'`)
- **Problem:** Webhook-visible subscription metadata (`checkout_region` / `region`) differs by
  which surface created the session.
- **Fix:** Point `Plans#detect_region` at the shared implementation. Fold into the #4017
  `build_session_params` migration rather than fixing standalone.

## FU-3 `[ ] TODO` — LOW: raw Stripe error messages returned to API clients

- **Where:** `apps/web/billing/controllers/billing.rb:1020` (`migrate_currency`),
  `:536` (`preview_plan_change`), `:695` (`change_plan`) — all `json_error(ex.message, ...)`
- **Problem:** Stripe `InvalidRequestError` messages can embed object IDs and parameter names;
  other billing paths deliberately return generic messages.
- **Fix:** Replace with generic client messages; keep full detail in the existing log lines.

## FU-4 `[x] DONE` (fix/4025-currency-migration-clover-drift) — LOW: hardcoded `'cad'` currency fallback in migration result

- **Where:** `apps/web/billing/lib/currency_migration_service.rb:331`
  (`subscription&.currency || 'cad'`)
- **Problem:** Ignores `Onetime.billing_config.currency` (which itself defaults to `'cad'`);
  wrong display currency for non-CAD deployments when the org had no subscription.
- **Fix:** `subscription&.currency || Onetime.billing_config.currency`.

## FU-5 `[x] DONE` (fix/4025-currency-migration-clover-drift) — LOW: doc drift in `issue_prorated_refund`

- **Where:** `apps/web/billing/lib/currency_migration_service.rb:519-521`
- **Problem:** YARD documents `@param currency` but the method signature is
  `(customer_id, amount)`.
- **Fix:** Remove the stale param (or reintroduce currency if the CM-4 credit-note rewrite
  needs it). Fold into the CM-1/CM-4 change.

## FU-6 `[ ] TODO` — LOW: spec fidelity — stub clover-shaped Stripe objects

- **Where:** `spec/unit/billing/currency_migration_service_spec.rb` (e.g. `:282,309` expanded
  discount hashes), billing spec support doubles generally
- **Problem:** Doubles model pre-basil field shapes (`payment_intent` on Invoice, expanded
  `discounts`), which is exactly why CM-1..CM-3 shipped green.
- **Fix:** Align shared Stripe doubles/factories (`apps/web/billing/spec/support/`) with the
  pinned `2025-12-15.clover` shapes: no `Invoice#payment_intent`, unexpanded `discounts`,
  items-level `current_period_end`. Consider `verify_partial_doubles`-style guards or a factory
  comment pinning the API version.

---

## Sequencing note

FU-1 and FU-2 belong with the #4017 checkout-metadata unification. FU-4/FU-5 ride along with the
CM-1/CM-4 refund rewrite. FU-6 should land with (or immediately after) the critical fixes so the
new specs enforce clover shapes.
