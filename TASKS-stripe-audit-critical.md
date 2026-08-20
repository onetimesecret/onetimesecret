# Stripe Checkout/Tax Audit — Critical & High Tasks

Source: Stripe Checkout/Tax audit 2026-08-07 (branch `fix/4025-currency-migration-tax-policy`).
Root cause for CM-1..CM-3: `apps/web/billing/lib/currency_migration_service.rb` still speaks the
pre-basil Stripe API while the deployment pins `stripe_api_version: "2025-12-15.clover"` with
stripe gem 18.4.2. The rest of billing was migrated (items-level `current_period_end`,
`subscription_details` in `preview_plan_change`, `total_taxes`); this service was not.
Specs (`spec/unit/billing/currency_migration_service_spec.rb`) stub the old field shapes, so
CI is green while the production path is broken.

## Task states

| Marker | Meaning |
|--------|---------|
| `[ ] TODO` | Not started |
| `[~] IN PROGRESS` | Actively being worked (note owner/branch) |
| `[!] BLOCKED` | Blocked — note blocker inline |
| `[x] DONE` | Fixed, tested, merged |

---

## CM-1 `[x] DONE` (fix/4025-currency-migration-clover-drift) — CRITICAL: `invoice.payment_intent` removed → immediate migration 500s AFTER canceling subscription

- **Where:** `apps/web/billing/lib/currency_migration_service.rb:532,536` (`issue_prorated_refund`)
- **Problem:** `Invoice#payment_intent` was removed in basil (2025-03-31). Gem 18.4.2 raises a
  bespoke "BREAKING CHANGE" `NoMethodError` for exactly this access
  (`stripe-18.4.2/lib/stripe/stripe_object.rb:449`). The local rescue only catches
  `Stripe::InvalidRequestError`; `migrate_currency`'s rescues (`billing.rb:1008-1027`) are
  Stripe-only → unhandled 500.
- **Blast radius:** Fires on every immediate migration with positive prorated credit (the normal
  mid-period case). Sequence at crash time: old subscription already canceled, no refund issued,
  no new checkout session created, migration intent not cleared. Customer stranded.
- **Fix:** Replace payment-intent lookup with `Stripe::CreditNote.create(invoice:, refund_amount:)`
  (also resolves CM-4). If a raw refund must stay, resolve the payment via `invoice.payments`.
- **Verify:** Spec that stubs a clover-shaped Invoice (no `payment_intent` reader; raises
  NoMethodError on access) and asserts the refund path completes; manual immediate migration in
  Stripe test mode mid-period.

## CM-2 `[x] DONE` (fix/4025-currency-migration-clover-drift) — CRITICAL: proration preview uses removed params → silent fallback to naive refund math

- **Where:** `apps/web/billing/lib/currency_migration_service.rb:470-478` (`calculate_prorated_credit`)
- **Problem:** `Invoice.create_preview` called with top-level `subscription_items` /
  `subscription_proration_behavior` / `subscription_proration_date` — all rejected under clover
  (basil moved them into `subscription_details`; correct shape already exists at
  `billing.rb:467-477`). The `rescue Stripe::StripeError` silently drops to
  `manual_prorated_credit`, which ignores discounts, taxes, and Stripe's proration logic.
- **Blast radius:** Preview path is permanently dead; every immediate-migration refund is computed
  by the naive fallback. A customer with a 50%-off coupon is computed a full-price refund
  (over-refund). Only a debug-level log marks the fallback.
- **Fix:** Rewrite the preview call to the `subscription_details` shape (mirror
  `preview_plan_change`). Raise the fallback log to warn so a dead preview path is visible.
- **Verify:** Spec asserting the exact param shape sent to `create_preview`; test-mode migration
  with an amount-off coupon confirming refund reflects the discounted price.

## CM-3 `[x] DONE` (fix/4025-currency-migration-clover-drift) — CRITICAL: unexpanded `subscription.discounts` → 500 on migration pre-check for couponed subscribers

- **Where:** `apps/web/billing/lib/currency_migration_service.rb:376-379` (`check_migration_warnings`)
- **Problem:** Under clover, `subscription.discounts` returns unexpanded discount ID strings
  (gem doc: "Use `expand[]=discounts`"). `discount&.coupon` on a String raises `NoMethodError`.
- **Blast radius:** `GET check_currency_migration` (`billing.rb:889`) calls `assess_migration`
  unwrapped → 500 for any subscriber with a coupon. In `create_checkout_session`'s 409 path the
  `rescue StandardError` swallows it and silently reports `has_incompatible_coupons: false`.
  Specs at `currency_migration_service_spec.rb:282,309` stub expanded coupon hashes, masking this.
- **Fix:** Retrieve the subscription with `expand: ['discounts']` in `check_migration_warnings`
  (and anywhere `.coupon` is read). Update specs to unexpanded-by-default shapes.
- **Verify:** Spec with `discounts: ['di_123']` (string IDs) asserting no raise; test-mode
  pre-check against a couponed subscription.

## CM-4 `[x] DONE` (fix/4025-currency-migration-clover-drift) — HIGH: refunds bypass Stripe Tax accounting (no credit note, pre-tax amount)

- **Where:** `apps/web/billing/lib/currency_migration_service.rb:523-547` (`issue_prorated_refund`)
- **Problem:** Raw `Stripe::Refund` against the latest paid invoice's payment intent. For
  `automatic_tax` deployments: (a) refund amount is a pre-tax manual proration while the customer
  paid tax on the full period; (b) no credit note is generated, so Stripe Tax reporting continues
  to count the full tax as collected — tax liability overstated.
- **Fix:** Use `Stripe::CreditNote` with `refund_amount` (tax-correct, and closes CM-1 in the
  same change). Target the invoice being partially refunded explicitly, not "latest paid".
- **Verify:** Test-mode migration with automatic tax on; confirm credit note appears and tax
  reporting adjusts.

## CM-5 `[x] DONE` (fix/4025-currency-migration-clover-drift) — HIGH: `refund_amount` reported to customer even when refund failed

- **Where:** `apps/web/billing/lib/currency_migration_service.rb:286-288,325-333`
  (`execute_immediate_migration`)
- **Problem:** `issue_prorated_refund` returns nil on failure (warn-level log only) — e.g. refund
  amount exceeds the latest invoice's charge, plausible when the most recent paid invoice is a
  small proration invoice. The result hash reports `refund_amount` / `refund_formatted` from the
  computed credit unconditionally: customer told they were refunded money that never moved.
- **Fix:** Thread the actual refund/credit-note result into the response; report 0 / omit with an
  explicit `refund_failed` flag when nil, and log at error level.
- **Verify:** Spec where the refund call fails, asserting the response does not claim a refund.

---

## Sequencing note

CM-1 + CM-4 are one change (credit-note refund). CM-2 and CM-3 are independent. CM-5 lands last
(depends on the refund call's final return shape). All five touch only
`currency_migration_service.rb` + specs; no schema or config changes.
