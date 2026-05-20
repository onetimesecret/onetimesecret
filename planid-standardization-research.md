# `organization.planid` and Stripe metadata `plan_id` — Standardization Research

Repo: `onetimesecret/onetimesecret` at `/Users/d/Projects/dev/onetimesecret/onetimesecret`
Scope: every reference, in production code, tests, fixtures, migration scripts, and docs, that reads or writes the Organization model's `planid` field or any Stripe metadata `plan_id` key (customer, subscription, product, price).

## TL;DR

There are **two different "plan_id" concepts** in this codebase and they have drifted out of agreement:

1. **Unsuffixed family form** (`identity_plus_v1`) — the universal plan identity carried in Stripe product metadata `plan_id`, in subscription metadata `plan_id` (intermittently), and what the `standardize_planid` housekeeping chore treats as canonical for `organization.planid`.
2. **Suffixed catalog form** (`identity_plus_v1_monthly`) — the `Billing::Plan` catalog identifier, computed as `"#{product.metadata.plan_id}_#{interval}ly"`, returned by `PlanValidator.resolve_plan_id(price_id)` and written into `organization.planid` by the owner-path webhook handler on every successful subscription event.

The owner-path webhook writes the **suffixed** form. The housekeeping chore then rewrites it to the **unsuffixed** form. Every paid org oscillates between the two depending on which ran most recently. `Billing::BillingService.plans_match?` (`apps/web/billing/lib/billing_service.rb:253-284`) exists specifically to paper over this drift in the diff-checker. There is no Stripe **customer** metadata `plan_id` field actually being read or written by current code — that is dead data if it exists in Stripe.

The cleanest fix is to make the **unsuffixed family form canonical for `organization.planid`** and decouple it from the interval-bearing catalog key. Rationale and migration touch points are detailed in section 7.

---

## 1. Architecture: where each "plan_id" lives

### 1.1 The Stripe-side input

Stripe products carry metadata. `apps/web/billing/metadata.rb:21` defines:

```ruby
FIELD_PLAN_ID = 'plan_id'
```

The value in `product.metadata['plan_id']` is the **unsuffixed family** — e.g. `identity_plus_v1`, `team_plus_v1`, `free_v1`. CLI tooling at `apps/web/billing/cli/products_create_command.rb:78`, `products_update_command.rb:72`, `catalog_push_command.rb:569`, and `helpers.rb:219` writes this value. `apps/web/billing/models/plan.rb:184` requires it on every OTS-managed product. The legacy field name was `planid` (no underscore) — `models/plan.rb:189` recognizes it but only emits a migration hint.

### 1.2 The Billing::Plan catalog (Redis cache)

`apps/web/billing/models/plan.rb:564` constructs the catalog identifier:

```ruby
base_plan_id = product.metadata[Metadata::FIELD_PLAN_ID]   # 'identity_plus_v1'
plan_id      = "#{base_plan_id}_#{interval}ly"             # 'identity_plus_v1_monthly'
```

So `Billing::Plan.plan_id` (the Redis key, the identifier returned by `find_by_stripe_price_id`, the value used by `Plan.load`) is always **suffixed**. This is the value `PlanValidator.resolve_plan_id(price_id)` returns (`apps/web/billing/lib/plan_validator.rb:101`).

### 1.3 The Organization model field

`lib/onetime/models/organization.rb:81`:

```ruby
@planid ||= 'free_v1'  # Default to canonical free plan
```

The field is declared in `lib/onetime/models/organization/features/with_organization_billing.rb` and exposed via `lib/onetime/models/organization/features/safe_dump_fields.rb:26`.

### 1.4 Stripe subscription metadata `plan_id`

Three production code paths write it:

| File:Line | Value written | Form |
|---|---|---|
| `apps/web/billing/controllers/billing.rb:128` (org-scoped checkout session create) | `plan.plan_id` | **suffixed** |
| `apps/web/billing/controllers/billing.rb:655` (subscription update / plan change) | `new_plan&.plan_id` | **suffixed** |
| `lib/onetime/cli/migrations/migrate_probono_accounts_command.rb:284` | `target_planid` (default `'identity_plus_v1'`) | **unsuffixed** |

Plus `apps/web/billing/controllers/plans.rb:152-162` writes `plan_id` only as a debug field inside `debug_info` JSON, not as top-level subscription metadata. So checkouts going through `/billing/plans/:product/:interval` produce subscriptions with **no top-level `metadata.plan_id`**, while checkouts going through `/billing/api/org/:extid/checkout` produce subscriptions with **suffixed** metadata. The probono migration is the only writer that produces **unsuffixed** subscription metadata.

Reads of subscription metadata `plan_id`:
- `apps/web/billing/lib/plan_validator.rb:181,203` — federation resolver.
- `apps/web/billing/lib/billing_service.rb:73` — fallback resolution.
- `lib/onetime/models/organization/features/with_organization_billing.rb:473` — drift detection.
- `apps/web/billing/logic/welcome.rb:271` — checkout completion log only.
- `apps/api/colonel/logic/colonel/investigate_organization.rb:136` — admin diagnostics.

### 1.5 Stripe customer metadata `plan_id`

**Nothing in current code writes or reads it.** Verified across all webhook handlers, all CLI commands, all controllers. The customer-metadata writes that exist only set `email_hash`, `region`, `org_extid`, `migrated_from`, `migrated_at`, and the federation breadcrumb keys (`last_federation_*`). If the user's framing assumed there is a customer-metadata `plan_id` keeping divergent state, that assumption is wrong — though stale values may exist in Stripe from older code iterations or manual dashboard edits.

### 1.6 Stripe price metadata `plan_id`

Optional. Only written when YAML catalog has a per-price `metadata:` block (`apps/web/billing/cli/catalog_push_command.rb:543`). Read as a federation fallback (`apps/web/billing/lib/plan_validator.rb:190`, `with_organization_billing.rb:468`).

---

## 2. Writers of `organization.planid`

| # | File:Line | Expression | Source | Suffixed? |
|---|---|---|---|---|
| W1 | `lib/onetime/models/organization.rb:81` | `@planid ||= 'free_v1'` | Default `init` | No |
| W2 | `apps/web/billing/operations/apply_subscription_to_org.rb:86` | `@org.planid = @planid_override` | `planid_override` kwarg. Only production caller is `migrate_probono_accounts_command.rb:298` with default `'identity_plus_v1'` (line 42). | **No** |
| W3 | `apps/web/billing/operations/apply_subscription_to_org.rb:102` (owner path) | `@org.planid = plan_id` | `PlanValidator.resolve_plan_id(price_id)` → catalog `Plan.plan_id` | **Yes** |
| W3' | same line (federated path) | same | `PlanValidator.resolve_plan_id_for_federation(subscription)` → reads `subscription.metadata['plan_id']` | Depends on what other region wrote (typically **No**) |
| W4 | `lib/onetime/models/organization/features/with_organization_billing.rb:399` | `self.planid = 'free_v1'` | Literal in `clear_billing_fields` (owner-side subscription delete) | No |
| W5 | `apps/web/billing/operations/webhook_handlers/subscription_deleted.rb:83` | `org.planid = 'free_v1'` | Literal in `clear_federated_org` | No |
| W6 | `apps/web/auth/operations/create_default_workspace.rb:158` | `org.planid = pending.planid if pending.planid` | `Billing::PendingFederatedSubscription.planid`, set at `pending_federated_subscription.rb:98` via `resolve_plan_id` | **Yes** when set |
| W7 | `lib/onetime/models/organization/chores/standardize_planid.rb:93` | `org.planid! corrected` | Result of `LEGACY_PLANID_MAP[family]` lookup | **No** (always unsuffixed canonical) |
| W8 | `scripts/upgrades/v0.24.5/02-organization/generate.rb:303` | `'planid' => planid` | `customer_fields['planid'] \|\| 'free'` (line 285) | Whatever was in v1 customer (mixed) |

Six distinct writer paths, three of which produce suffixed values and three of which produce unsuffixed. The chore (W7) is the only one that normalizes; everything else writes what its source supplied. The owner-path webhook (W3) fires on every subscription event so it dominates write traffic — meaning the day-to-day steady state for paid orgs is suffixed form between housekeeping runs.

### 2.1 Pending federation pipeline

`apps/web/billing/models/pending_federated_subscription.rb:98` stores `pending.planid = extract_plan_id(subscription)` where `extract_plan_id` calls `PlanValidator.resolve_plan_id(price_id)` — suffixed. That pending record is later consumed by `create_default_workspace.rb:158` (W6) when the federated user signs up.

But `subscription_federation.rb` for in-flight federation calls `ApplySubscriptionToOrg` with `owner: false`, which goes through the federated branch of W3' — and that branch reads `subscription.metadata['plan_id']` directly, which is typically unsuffixed.

**So two federation code paths (pending vs in-flight) write different forms onto receiving orgs.** Detailed in §4.

---

## 3. Readers of `organization.planid`

Roughly 34 distinct read sites across 14 production files, dominated by entitlement resolution.

### 3.1 Entitlement resolution (hot path)
- `lib/onetime/models/features/with_entitlements.rb:198,206,212,224,261,268,275,285` — `Billing::Plan.load(planid)` then `Plan.load_from_config(planid)` then raise `PlanCacheMissError`.
- `apps/web/billing/controllers/entitlements.rb:39,44,49,50,53,193,195` — same shape via PlanHelpers.
- `apps/web/billing/controllers/billing.rb:1288,1290` — plan data for response.

These reads expect the **suffixed** form because that is what `Billing::Plan` indexes under. When the chore rewrites a value to unsuffixed (`identity_plus_v1`), `Plan.load('identity_plus_v1')` falls through to `Plan.load_from_config('identity_plus_v1')` — which exists in `billing.yaml` keyed by the unsuffixed family. So entitlement resolution silently works in both directions only because the YAML config has the unsuffixed keys and the catalog has the suffixed keys.

### 3.2 Authorization / upgrade path
- `lib/middleware/entitlement_check.rb:67,73,81,111`
- `lib/onetime/logic/base.rb:176`
- `lib/onetime/incoming/recipient_resolver.rb:117`

### 3.3 Sync / classification
- `apps/web/billing/lib/billing_service.rb:125,160,197,205,208,284` — including `plans_match?` which strips `_(month|year)ly$` to compare across the two forms.
- `lib/onetime/models/organization/features/with_organization_billing.rb:178,183` — `paid?` against `FREE_PLAN_IDS = %w[free free_v1]`.

### 3.4 Display / serialization (exposed externally)
- `lib/onetime/models/organization/features/safe_dump_fields.rb:26`
- `apps/web/core/views/serializers/organization_serializer.rb:64`
- `apps/api/colonel/logic/colonel/list_organizations.rb:83`, `investigate_organization.rb:72`, `set_entitlement_test.rb:92,102`
- `apps/api/organizations/cli/list_command.rb:130,193`
- `apps/web/billing/controllers/billing.rb:396,415,691,699,846`
- `apps/web/billing/cli/diagnose_command.rb:272`
- `apps/web/billing/logic/welcome.rb:302`
- `apps/web/billing/operations/webhook_handlers/subscription_federation.rb:175`

External display means whichever form is stored at the moment leaks out to API responses and CLI output. Drift is observable from outside the system.

### 3.5 CLI / housekeeping branch checks
- `lib/onetime/cli/migrations/migrate_probono_accounts_command.rb:231,233` — read filter.
- `lib/onetime/models/organization/chores/standardize_planid.rb:72` — the chore itself.

---

## 4. Divergence map

### 4.1 The headline conflict

`apply_subscription_to_org.rb:96-102` (owner path) calls `Billing::PlanValidator.resolve_plan_id(price_id)` which returns the catalog's suffixed key. That value is assigned to `@org.planid`. Then `standardize_planid.rb:64-93` matches `INTERVAL_SUFFIX = /_(v1_)?(month|year)(ly)?\z/` on the same value, strips the suffix, and rewrites to the unsuffixed canonical form. Every paid org ping-pongs between the two on every webhook/housekeeping cycle.

`billing_service.rb:253-284` exists specifically to mask this from the diff-checker — `plans_match?` normalizes the interval suffix before comparison, so an admin running a sync-check sees no drift even when the data is changing every job tick.

### 4.2 Within `apply_subscription_to_org.rb` itself

The owner branch (`@owner == true`) writes the **suffixed** catalog form via `resolve_plan_id`. The federated branch (`@owner == false`) writes whatever the cross-region Stripe subscription has in its `metadata['plan_id']`, which is typically **unsuffixed** (because the federation contract assumes the universal family ID, not the interval-bearing catalog key). Two orgs receiving the same subscription event via owner vs federation routes end up with different planid forms.

### 4.3 Two federation paths disagree

- `PendingFederatedSubscription.extract_plan_id` → `resolve_plan_id` → suffixed catalog form → W6 writes suffixed.
- In-flight `SubscriptionFederation` → `ApplySubscriptionToOrg(owner: false)` → `resolve_plan_id_for_federation` → reads `metadata['plan_id']` → typically unsuffixed.

### 4.4 The v0.24.5 upgrade migration

`scripts/upgrades/v0.24.5/02-organization/generate.rb:285` copies `customer_fields['planid']` directly, falling back to the bare string `'free'` (not `'free_v1'`). The spec at `01-customer/spec.md:24` and `02-organization/spec.md:29` lists planid as "Direct Copy (no transform)". So every value that ever existed on a v1 customer landed on a v2 org untouched. The chore is the only normalization that runs on this data.

### 4.5 The probono migration deliberately diverges

`migrate_probono_accounts_command.rb:298` passes `planid_override: target_planid` where `target_planid` defaults to `'identity_plus_v1'` (unsuffixed). This was intentional, to align probono orgs with the chore's canonical form. It also clears `customer.planid` (line 302) so the next chore run keeps `org.planid = 'identity'` from being re-marked legacy.

### 4.6 Concrete values seen on orgs

Sorted roughly by likely frequency in production data:

| Value | Suffixed? | Producers |
|---|---|---|
| `identity_plus_v1_monthly`, `team_plus_v1_monthly`, plus yearly variants | Yes | W3 owner path, W6 pending federation → most paid orgs between chore runs |
| `identity_plus_v1`, `team_plus_v1` | No | W7 chore, W2 probono migration, W3' federated, post-housekeeping steady state |
| `free_v1` | No | W1 default, W4/W5 cancellation paths |
| `identity` | No | W7 preserves; v0.24.5 migration left as-is from v1 customer field |
| `free`, `basic`, `''`, `nil` | No | v0.24.5 migration output for any v1 customer with non-canonical planid; chore later normalizes |
| `identity_plus`, `identity_plus_monthly`, `identity_plus_yearly`, `team_plus_monthly`, `team_plus_yearly` | mixed | v0.24.5 migration output; chore handles |
| `identity_v1`, `multi_team_v1`, `pro_monthly`, `org_plus_v1`, `org_max_v1`, `ge_dedicated_v1`, `identity_plus_v2` | mixed | Test-only — present in VCR cassettes (generated from test fixtures), not in production data. No migration needed. |
| `premium`, `enterprise`, `enterprise_v2`, `pro`, `pro-plan` | No | Test-only — colonel integration spec uses these as sentinels; not in production. |
| `single_team_v1_monthly`, `org_max_v1_monthly`, `single_team_monthly_us_east` | Yes | Test data; some may exist on real orgs via region-specific catalogs |

The chore's `LEGACY_PLANID_MAP` covers: `''`, `free`, `basic`, `identity`, `identity_plus`, `team_plus`, with interval-stripping for `_month/_year/_monthly/_yearly` variants. This is considered complete for production data. The other values listed above (`identity_v1`, `multi_team_v1`, `pro_monthly`, etc.) appear only in tests and VCR cassettes, not production. Tooling docs that cite `identity_v1` are stale and should be corrected as part of this change.

### 4.7 Secondary inconsistencies

- `legacy_plan_v1` is in `CANONICAL_PLANIDS` with no writer — defensive whitelisting.
- `apps/web/core/controllers/welcome.rb:26-29` defines `LEGACY_TIER_MAP = { 'identity' => 'identity_plus_v1', 'dedicated' => 'identity_plus_v1' }` for URL routing — encodes the unsuffixed convention.
- Frontend `src/shared/composables/useEntitlements.ts:41-56` `FALLBACK_ENTITLEMENT_TO_PLAN` map uses `identity_v1` and `multi_team_v1` heavily — neither is canonical per the chore. Annotated `@deprecated` but present.
- Frontend `src/apps/workspace/billing/PlanSelector.vue:111-141, 385-471` branches on `planid === 'identity'` (hard-coded legacy id) and uses substring matching against `'multi_team'`, `'team_plus'`, `'single_team'`, `'identity_plus'`.

---

## 5. Migration scripts, CLI commands, and chores

### v0.24.5 upgrade
- `scripts/upgrades/v0.24.5/01-customer/analyze.sql` — read-only plan distribution queries.
- `scripts/upgrades/v0.24.5/01-customer/transform.rb:48` — declares `'planid' => :string` in `FIELD_TYPES`; direct copy.
- `scripts/upgrades/v0.24.5/01-customer/spec.md:24` — "Direct Copy (no transform)".
- `scripts/upgrades/v0.24.5/02-organization/generate.rb:54,285,303` — `customer.planid → org.planid` with bare-`'free'` fallback.
- `scripts/upgrades/v0.24.5/02-organization/spec.md:29,118` — same.

### `bin/ots migrations migrate-probono-accounts`
`lib/onetime/cli/migrations/migrate_probono_accounts_command.rb` — sets `org.planid='identity_plus_v1'` (default unsuffixed), creates a Stripe subscription with metadata `{plan_id: target_planid, legacy_planid: 'identity'}`, and clears `customer.planid`. Test: `spec/unit/onetime/cli/migrations/migrate_probono_accounts_command_spec.rb`.

### `bin/ots housekeeping run Onetime::Organization standardize_planid`
Dispatched through `lib/onetime/cli/housekeeping/run_command.rb:38` → `lib/onetime/jobs/scheduled/housekeeping_job.rb:106` → the chore. Test: `spec/unit/onetime/models/organization/chores/standardize_planid_spec.rb` (covers every canonical, every legacy map entry, every interval-suffix variant, whitespace, nil, and two "unknown" sentinels `enterprise_custom` and `pro_annual_2023`).

### `colonel/update_user_plan` (API)
`apps/api/colonel/logic/colonel/update_user_plan.rb:48` — mutates `customer.planid` (NOT organization). Validates via `BillingService.valid_plan_id?` which accepts catalog (suffixed) or static config (unsuffixed). Integration spec at `spec/integration/full/admin_interface_spec.rb` shows admin posts `planid: 'premium'` / `'enterprise'` with no canonical-form enforcement.

### `colonel/set_entitlement_test` (API)
`apps/api/colonel/logic/colonel/set_entitlement_test.rb:53` — session-scoped override only. Does not mutate persistent org state.

---

## 6. Test, fixture, and docs surface

The full enumeration is in section 8 below. Headline counts and the items most likely to need updates:

### Critical test infrastructure
- `apps/web/billing/spec/support/shared_contexts/with_test_plans.rb` — helper `test_plan_id(tier, interval, region)` synthesizes IDs in a format that doesn't match canonical billing.test.yaml keys; will need re-aligning.
- `apps/web/billing/spec/support/billing_spec_helper.rb` — `stub_test_plan_catalog!` mocks `Plan.load('identity_plus_v1')` returning a mock with `plan_id: 'test_plan_v1_monthly'`; assumes both forms coexist.
- `apps/web/billing/spec/billing.test.yaml` — defines `free_v1`, `identity_plus_v1`, `identity` (with `legacy: true`).
- `spec/support/shared_contexts/view_test_context.rb` — `planid: 'basic'`.

### Frontend fixtures with hard-coded planids
- `src/tests/schemas/shapes/fixtures/organization.fixtures.ts` — defaults to `'free'`.
- `src/tests/fixtures/billing.fixture.ts` — `mockPlans` keyed on `free_v1`, `identity` (legacy Early Supporter), `identity_plus_v1_monthly`, `identity_plus_v1_yearly`, `team_plus_v1_monthly`, `team_plus_v1_yearly`.

### VCR cassettes (most authoritative source for real Stripe data shapes)
`apps/web/billing/spec/fixtures/vcr_cassettes/` contains recorded Stripe API responses. The most diverse cassette `Billing_Controllers_BillingController/GET/returns_list_of_available_plans.yml` encodes plan_id metadata values: `vcr_test_plan_id_unique`, `new_plan`, `free_v1`, `identity_plus_v1`, `identity`, `identity_plus_v2`, `y`, `identity_v1`, `ge_dedicated_v1`, `org_max_v1`, `org_plus_v1`, `team_plus_v1`. These exact strings have been recorded from real Stripe API calls — meaning real production Stripe products have used these IDs.

### Documentation that asserts plan IDs
Docs that cite plan IDs the chore would reject as unknown:
- `docs/development/test-accounts.md:3` — cites `identity_v1`.
- `apps/web/billing/docs/cli-usage.md:9` — cites `identity_v1`, `identity_plus_v1_us`, `team_plus_v1_us`.
- `apps/web/billing/docs/stripe-configuration.md:4` — cites `identity_v1`.
- `apps/web/billing/docs/duplicate-product-handling.md:14` — cites `identity_v1_monthly`.
- `apps/web/billing/docs/BILLING-ENTITLEMENT-TEST-PATTERNS.md:18` — cites `identity_v1`, `premium`.
- `src/shared/composables/ENTITLEMENT_QUICK_REFERENCE.md:1` — cites `identity_v1` (as anti-pattern).
- `docs/test-plans/issues/2309-stripe-integration.yaml:2` — cites `org_plus_v1`.
- `docs/runbooks/duplicate-plans-on-plans-page.md` — mostly aligned, references `free_v1`/`free_v1_monthly` duplicate.

### Config schema
- `etc/schemas/billing.schema.json` enforces enums for `tier`, `tenancy`, `interval`, `currency`. **No regex or enum on plan_id keys.** Any string is accepted.
- `src/schemas/contracts/organization.ts` — `planid: z.string()` (nullable in bootstrap). No format constraint.

---

## 7. Recommendation

**Adopt the unsuffixed family form (`identity_plus_v1`) as the canonical value for `organization.planid`.** Drop interval from the org's planid field entirely; interval lives on the subscription record, not on the org's plan identity.

Why this direction rather than making suffixed canonical:

1. The federation path requires unsuffixed. Cross-region Stripe price IDs don't exist in the local catalog, so the only thing the federated webhook handler can store is the universal family ID from subscription metadata. If unsuffixed is canonical, the federation path is the simple path; if suffixed is canonical, federation needs special handling forever.

2. Interval is already separately tracked via `org.subscription_period_end` and via the Stripe subscription's own `items.price.recurring.interval`. Encoding it in `planid` is redundant.

3. The plan's *identity* doesn't change when a user toggles between monthly and yearly billing; the planid shouldn't either. With suffixed canonical, every billing-interval switch (a Stripe plan change to the same product, different price) mutates `org.planid` even though the entitlement set is identical.

4. Stripe product metadata already uses unsuffixed. Every CLI tool already writes unsuffixed. The chore already targets unsuffixed. The probono migration already writes unsuffixed. The only writer producing suffixed values is the auto-resolved catalog lookup in `apply_subscription_to_org.rb` owner path — that's one code path to change.

5. The `LEGACY_PLANID_MAP` is shorter and more stable. Adding `identity_v1`, `multi_team_v1`, etc. to it is a small set of additions. Adding all their suffixed permutations would be a combinatorial expansion.

6. Frontend code already does substring-matching that effectively normalizes (`PlanSelector.vue` checks `planid.includes('identity_plus')`). Making unsuffixed canonical aligns with where the frontend is already heading.

### What changes if we go this direction

**Production code:**

- `apps/web/billing/operations/apply_subscription_to_org.rb:84-103` — owner path: after `PlanValidator.resolve_plan_id(price_id)`, strip the `_(month|year)ly$` suffix before assigning to `@org.planid`. Or change the resolver itself.
- `apps/web/billing/lib/plan_validator.rb#resolve_plan_id` — consider returning the unsuffixed form for `org.planid` use, and keep a separate method for catalog-key resolution.
- `apps/web/billing/models/pending_federated_subscription.rb:121` (`extract_plan_id`) — same: store unsuffixed.
- `apps/web/billing/lib/billing_service.rb:253-284` (`plans_match?`) — the `_(month|year)ly$` stripping becomes unnecessary. Can be deleted once data is fully migrated.
- `apps/web/billing/controllers/billing.rb:128, 655` — `Stripe::Checkout::Session.create` / `Subscription.update` should write **unsuffixed** to `subscription.metadata['plan_id']` for consistency with federation.
- `lib/onetime/models/features/with_entitlements.rb` lookups — already work because of the existing fallthrough to `Plan.load_from_config` which uses unsuffixed keys, but we should add an explicit catalog-key resolver `planid_to_catalog_key(planid, interval)` and use it instead of relying on the fallthrough.

**The chore (`standardize_planid.rb`):**

- `LEGACY_PLANID_MAP` is complete as-is. No extensions needed.
- `CANONICAL_PLANIDS` stays the same: `free_v1`, `identity_plus_v1`, `team_plus_v1`, `legacy_plan_v1`, `identity`.

**Data migration:**

- A one-time normalization pass over `Onetime::Organization` instances: load each, run through the `standardize_planid` chore, write back. The chore is already idempotent and covers all production legacy values. Run it once to converge state, then keep it on the recurring schedule as a safety net.
- No Stripe customer metadata cleanup needed — current code doesn't write or read `customer.metadata['plan_id']`, and product metadata `plan_id` plus subscription's `items[].price.product` is sufficient to derive the plan for any customer.

**Test/fixture updates:**

- Replace suffixed fixtures with unsuffixed in:
  - `apps/web/billing/spec/controllers/billing_controller_spec.rb`, `plan_switching_spec.rb`, `entitlements_controller_spec.rb`
  - `apps/web/billing/spec/operations/apply_subscription_to_org_spec.rb`, `process_webhook_event/checkout_completed_spec.rb`, `process_webhook_event/federation/subscription_federation_spec.rb`
  - `try/unit/models/organization_billing_try.rb`, `try/unit/auth/billing_hooks_try.rb`, `try/unit/billing/plan_resolver_try.rb`
  - `src/tests/fixtures/billing.fixture.ts`, `src/tests/apps/workspace/billing/PlanSelector.spec.ts`, `BillingOverview.spec.ts`, `InvoiceList.spec.ts`
- Add explicit test cases in `standardize_planid_spec.rb` for the new legacy entries.
- VCR cassettes are recordings; they don't need code changes, but if Stripe products are renamed the cassettes will go stale and need re-recording.

**Documentation:**

- Add a section to `apps/web/billing/docs/plan-definitions.md` (or a new `apps/web/billing/docs/plan-id-conventions.md`) explaining the unsuffixed/family-vs-catalog-key distinction.
- Fix `docs/development/test-accounts.md`, `apps/web/billing/docs/cli-usage.md`, `apps/web/billing/docs/stripe-configuration.md`, `apps/web/billing/docs/duplicate-product-handling.md`, `apps/web/billing/docs/BILLING-ENTITLEMENT-TEST-PATTERNS.md`, `src/shared/composables/ENTITLEMENT_QUICK_REFERENCE.md`, `docs/test-plans/issues/2309-stripe-integration.yaml` to use only canonical values (or document the legacy mappings explicitly).
- Update `scripts/upgrades/v0.24.5/02-organization/spec.md` to note that the chore runs post-migration and normalizes; or change `generate.rb:285` to write `'free_v1'` instead of bare `'free'`.

**Schema enforcement:**

- Add a regex or enum to `etc/schemas/billing.schema.json` for plan_id keys (`^[a-z0-9_]+(_v\d+)?$` or an explicit enum), enforced at config-load time.
- Add a runtime validator in `Onetime::Organization` (a Familia v2 validation hook or a writer guard) so `org.planid =` rejects values outside the canonical set unless explicitly permitted.

---

## 8. Reference index

### Production files that read or write organization.planid

```
apps/api/colonel/logic/colonel/get_available_plans.rb
apps/api/colonel/logic/colonel/get_user_details.rb
apps/api/colonel/logic/colonel/investigate_organization.rb
apps/api/colonel/logic/colonel/list_organizations.rb
apps/api/colonel/logic/colonel/list_users.rb
apps/api/colonel/logic/colonel/set_entitlement_test.rb
apps/api/colonel/logic/colonel/update_user_plan.rb
apps/api/organizations/cli/list_command.rb
apps/api/v1/controllers/base.rb
apps/web/auth/operations/create_default_workspace.rb
apps/web/billing/cli/diagnose_command.rb
apps/web/billing/controllers/billing.rb
apps/web/billing/controllers/entitlements.rb
apps/web/billing/controllers/plans.rb
apps/web/billing/lib/billing_service.rb
apps/web/billing/lib/plan_resolver.rb
apps/web/billing/lib/plan_validator.rb
apps/web/billing/logic/welcome.rb
apps/web/billing/models/pending_federated_subscription.rb
apps/web/billing/models/plan.rb
apps/web/billing/operations/apply_subscription_to_org.rb
apps/web/billing/operations/webhook_handlers/catalog_updated.rb
apps/web/billing/operations/webhook_handlers/subscription_deleted.rb
apps/web/billing/operations/webhook_handlers/subscription_federation.rb
apps/web/billing/plan_helpers.rb
apps/web/core/controllers/welcome.rb
apps/web/core/views/serializers/organization_serializer.rb
lib/middleware/entitlement_check.rb
lib/middleware/entitlement_test_mode.rb
lib/onetime/cli/customers/show_command.rb
lib/onetime/cli/housekeeping_command.rb
lib/onetime/cli/housekeeping/run_command.rb
lib/onetime/cli/migrations/migrate_probono_accounts_command.rb
lib/onetime/incoming/recipient_resolver.rb
lib/onetime/jobs/scheduled/housekeeping_job.rb
lib/onetime/jobs/scheduled/plan_cache_refresh_job.rb
lib/onetime/logic/base.rb
lib/onetime/models/customer.rb
lib/onetime/models/features/with_entitlements.rb
lib/onetime/models/features/with_migration_fields.rb
lib/onetime/models/organization.rb
lib/onetime/models/organization/chores/standardize_planid.rb
lib/onetime/models/organization/features/migration_fields.rb
lib/onetime/models/organization/features/safe_dump_fields.rb
lib/onetime/models/organization/features/with_organization_billing.rb
```

### Production files that read or write Stripe metadata plan_id

```
apps/api/colonel/logic/colonel/investigate_organization.rb
apps/web/billing/cli/catalog_push_command.rb
apps/web/billing/cli/helpers.rb
apps/web/billing/cli/plans_validate_command.rb
apps/web/billing/cli/prices_generate_command.rb
apps/web/billing/cli/products_create_command.rb
apps/web/billing/cli/products_update_command.rb
apps/web/billing/cli/products_validate_command.rb
apps/web/billing/controllers/billing.rb              (subscription metadata writes; lines 128, 655)
apps/web/billing/lib/billing_service.rb
apps/web/billing/lib/currency_migration_service.rb   (does NOT write plan_id, listed for completeness)
apps/web/billing/lib/plan_validator.rb
apps/web/billing/logic/welcome.rb
apps/web/billing/metadata.rb                          (FIELD_PLAN_ID constant)
apps/web/billing/models/plan.rb                       (extract_plan_data → catalog key)
apps/web/billing/operations/webhook_handlers/checkout_completed.rb
apps/web/billing/operations/webhook_handlers/subscription_federation.rb
lib/onetime/cli/migrations/migrate_probono_accounts_command.rb  (subscription metadata write)
lib/onetime/cli/migrations/backfill_stripe_email_hash_command.rb  (does NOT touch plan_id)
lib/onetime/models/organization/features/with_organization_billing.rb
```

### Tests & tries with planid references

Unit specs (rspec): `spec/unit/billing/billing_service_spec.rb`, `spec/unit/billing/plan_validator_spec.rb`, `spec/unit/onetime/cli/migrations/migrate_probono_accounts_command_spec.rb`, `spec/unit/onetime/logic/require_entitlement_spec.rb`, `spec/unit/onetime/middleware/entitlement_test_mode_spec.rb`, `spec/unit/onetime/models/features/with_entitlements_can_spec.rb`, `spec/unit/onetime/models/features/with_entitlements_cache_miss_spec.rb`, `spec/unit/onetime/models/features/with_entitlements_test_mode_spec.rb`, `spec/unit/onetime/models/features/with_entitlements_ttl_env_spec.rb`, `spec/unit/onetime/models/organization/chores/standardize_planid_spec.rb`, `spec/unit/onetime/models/organization/with_organization_billing_spec.rb`.

Integration specs: `spec/integration/all/entitlement_test_spec.rb`, `spec/integration/api/v1/secret_ttl_entitlement_spec.rb`, `spec/integration/api/v2/entitlement_enforcement_spec.rb`, `spec/integration/api/v2/plan_cache_miss_handling_spec.rb`, `spec/integration/api/v2/secret_ttl_entitlement_spec.rb`, `spec/integration/api/v3/secret_ttl_entitlement_spec.rb`, `spec/integration/full/admin_interface_spec.rb`, `spec/integration/full/pending_federation_spec.rb`.

Billing app specs: `apps/web/billing/spec/cli/catalog_push_spec.rb`, `apps/web/billing/spec/cli/catalog_push_region_spec.rb`, `apps/web/billing/spec/cli/plans_spec.rb`, `apps/web/billing/spec/cli/products_spec.rb`, `apps/web/billing/spec/controllers/billing_controller_spec.rb`, `apps/web/billing/spec/controllers/entitlements_controller_spec.rb`, `apps/web/billing/spec/controllers/plan_switching_spec.rb`, `apps/web/billing/spec/controllers/plans_controller_spec.rb`, `apps/web/billing/spec/controllers/stripe_integration_blockers_spec.rb`, `apps/web/billing/spec/logic/welcome/process_checkout_session_spec.rb`, `apps/web/billing/spec/models/plan_spec.rb`, `apps/web/billing/spec/models/plan_upsert_spec.rb`, `apps/web/billing/spec/operations/apply_subscription_to_org_spec.rb`, `apps/web/billing/spec/operations/process_webhook_event/catalog_updates_spec.rb`, `apps/web/billing/spec/operations/process_webhook_event/checkout_completed_spec.rb`, `apps/web/billing/spec/operations/process_webhook_event/federation/subscription_federation_spec.rb`, `apps/web/billing/spec/operations/process_webhook_event/shared_examples.rb`.

V1-API specs: `apps/api/v1/spec/controllers/index_spec.rb`, `apps/api/v1/spec/logic/secrets/base_secret_action_spec.rb`, `apps/api/v1/spec/logic/secrets/v1_validation_boundaries_spec.rb`, `apps/api/v2/spec/logic/secrets/base_secret_action_spec.rb`.

Tryouts: `apps/web/billing/try/cli/helpers_try.rb`, `apps/web/billing/try/models/organization_billing_try.rb`, `apps/web/billing/try/models/plan_extract_try.rb`, `apps/web/billing/try/models/plan_load_all_from_config_try.rb`, `apps/web/billing/try/models/plan_try.rb`, `apps/web/billing/try/plan_helpers_try.rb`, `try/features/billing_isolation_verification_try.rb`, `try/integration/api/organizations/member_quota_try.rb`, `try/integration/api/organizations/organization_quota_try.rb`, `try/integration/billing/multi_region_federation_try.rb`, `try/migrations/field_types_completeness_try.rb`, `try/migrations/organization_generation_try.rb`, `try/migrations/transform_idempotency_try.rb`, `try/migrations/v2_json_serialization_try.rb`, `try/security/email_enumeration_prevention_try.rb`, `try/unit/auth/billing_hooks_try.rb`, `try/unit/billing/plan_resolver_try.rb`, `try/unit/cli/customers/doctor_command_try.rb`, `try/unit/cli/customers/show_try.rb`, `try/unit/logic/account/account_operations_try.rb`, `try/unit/logic/base_extended_try.rb`, `try/unit/models/customer_field_serialization_try.rb`, `try/unit/models/customer_pending_plan_intent_try.rb`, `try/unit/models/organization_billing_try.rb`, `try/unit/models/organization_entitlements_try.rb`, `try/unit/models/v2/customer_try.rb`.

Test helpers / shared contexts: `apps/web/billing/lib/test_support/billing_helpers.rb`, `apps/web/billing/spec/support/billing_spec_helper.rb`, `apps/web/billing/spec/support/shared_contexts/with_test_plans.rb`, `spec/support/shared_contexts/view_test_context.rb`.

### Frontend files

Contracts/schemas: `src/schemas/contracts/billing.ts`, `src/schemas/contracts/bootstrap.ts`, `src/schemas/contracts/config/billing.ts`, `src/schemas/contracts/config/index.ts`, `src/schemas/contracts/organization.ts`, `src/schemas/api/account/responses/colonel.ts`, `src/schemas/shapes/organizations/organization.ts`.

Stores/composables: `src/shared/composables/ENTITLEMENT_QUICK_REFERENCE.md`, `src/shared/composables/useAsyncHandler.ts`, `src/shared/composables/useAuth.ts`, `src/shared/composables/useEntitlements.ts`, `src/shared/composables/useTestPlanMode.ts`, `src/shared/stores/bootstrapStore.ts`, `src/shared/stores/entitlementsStore.ts`, `src/shared/stores/organizationStore.ts`.

Services: `src/services/billing.service.ts`, `src/services/diagnostics.service.ts`.

Vue components: `src/apps/colonel/views/ColonelOrganizations.vue`, `src/apps/colonel/views/ColonelUsers.vue`, `src/apps/secret/support/Pricing.vue`, `src/apps/workspace/account/settings/OrganizationsSettings.vue`, `src/apps/workspace/account/settings/OrganizationSettings.vue`, `src/apps/workspace/billing/BillingOverview.vue`, `src/apps/workspace/billing/PlanSelector.vue`, `src/apps/workspace/components/navigation/OrganizationScopeSwitcher.vue`, `src/shared/components/modals/PlanTestModal.vue`, `src/shared/components/ui/TestModeBanner.vue`, `src/plugins/core/globalErrorBoundary.ts`.

Frontend tests: `src/tests/apps/colonel/components/PlanTestModal.spec.ts`, `src/tests/apps/secret/support/Pricing.spec.ts`, `src/tests/apps/workspace/account/OrganizationSettings.spec.ts`, `src/tests/apps/workspace/billing/BillingOverview.spec.ts`, `src/tests/apps/workspace/billing/InvoiceList.spec.ts`, `src/tests/apps/workspace/billing/PlanSelector.currency.spec.ts`, `src/tests/apps/workspace/billing/PlanSelector.spec.ts`, `src/tests/apps/workspace/components/organizations/OrganizationCard.spec.ts`, `src/tests/apps/workspace/components/organizations/OrganizationContextBar.spec.ts`, `src/tests/apps/workspace/dashboard/UpgradeBanner.spec.ts`, `src/tests/components/identifier-navigation.spec.ts`, `src/tests/composables/useAuth.billing.spec.ts`, `src/tests/composables/useAsyncHandler.sentry.spec.ts`, `src/tests/composables/useEntitlements.spec.ts`, `src/tests/contracts/bootstrap-schema-contract.spec.ts`, `src/tests/contracts/bootstrap-serializer-fields.ts`, `src/tests/fixtures/billing.fixture.ts`, `src/tests/fixtures/bootstrap.fixture.ts`, `src/tests/plugins/core/globalErrorBoundary.errorHandler.spec.ts`, `src/tests/schemas/shapes/fixtures/organization.fixtures.ts`, `src/tests/schemas/shapes/helpers/serializers.ts`, `src/tests/services/diagnostics.service.spec.ts`, `src/tests/shared/components/navigation/UserMenu.spec.ts`, `src/tests/shared/composables/useTestPlanMode.spec.ts`, `src/tests/stores/bootstrapStore.spec.ts`, `src/tests/stores/organizationStore.spec.ts`, `src/tests/types/billing-legacy.spec.ts`, `e2e/full/mfa-bootstrap-reactivity.spec.ts`.

### Config & schema

`etc/examples/billing.example.yaml`, `etc/schemas/billing.schema.json`, `apps/web/billing/spec/billing.test.yaml`.

### Migration scripts

`scripts/upgrades/v0.24.5/01-customer/analyze.sql`, `scripts/upgrades/v0.24.5/01-customer/spec.md`, `scripts/upgrades/v0.24.5/01-customer/transform.rb`, `scripts/upgrades/v0.24.5/02-organization/generate.rb`, `scripts/upgrades/v0.24.5/02-organization/spec.md`.

### VCR cassettes that encode plan_id metadata

`apps/web/billing/spec/fixtures/vcr_cassettes/Billing_Controllers_BillingController/GET/returns_list_of_available_plans.yml`, plus all cassettes under `Onetime_CLI_BillingProductsCommand/_call/`, `Onetime_CLI_BillingProductsCreateCommand/_call/`, `Onetime_CLI_BillingProductsUpdateCommand/_call/`, `Onetime_CLI_BillingPricesCommand/_call/`.

### Documentation

`apps/web/billing/docs/BILLING-ENTITLEMENT-TEST-PATTERNS.md`, `apps/web/billing/docs/cli-usage.md`, `apps/web/billing/docs/duplicate-product-handling.md`, `apps/web/billing/docs/plan-definitions.md`, `apps/web/billing/docs/stripe-configuration.md`, `apps/web/billing/docs/validation-commands-spec.md`, `apps/web/billing/spec/BILLING-TEST-GUIDE.md`, `apps/web/billing/spec/controllers/README_INTEGRATION_TESTS.md`, `docs/authentication/per-domain-sso.md`, `docs/development/test-accounts.md`, `docs/runbooks/duplicate-plans-on-plans-page.md`, `docs/test-plans/features/billing/subscription-upgrade.yaml`, `docs/test-plans/issues/2309-stripe-integration.yaml`, `src/shared/composables/ENTITLEMENT_QUICK_REFERENCE.md`.

Total reference surface across all categories: roughly 200 files. The full grep set is 238 files with 2136 occurrences of the pattern `planid|plan_id|planID|PlanId` — the difference (~38 files) is incidental noise (e.g. unrelated `_plan_id` variables in other contexts, or matches inside `.bundle/` cached gems).

---

## 9. Operator decisions (resolved)

1. **VCR cassette values are test-generated, not production data.** `identity_v1`, `multi_team_v1`, `pro_monthly`, `org_plus_v1`, `org_max_v1`, `ge_dedicated_v1`, `identity_plus_v2`, `premium`, `enterprise`, `enterprise_v2`, `pro`, `pro-plan` do NOT exist on production org records. `LEGACY_PLANID_MAP` is considered complete. No extensions needed.
2. **All interval suffixes are removed from all plan_id values everywhere** — both `_month`/`_year` and `_monthly`/`_yearly` variants. Canonical = unsuffixed family form. This applies to `organization.planid`, `Billing::Plan` catalog keys, subscription metadata, product metadata, and all test fixtures.
3. **Stripe customer metadata `plan_id` is intentionally absent.** Product metadata `plan_id` + subscription's `items[].price.product` is sufficient to derive the plan for any customer. No cleanup or migration of customer-level metadata.
4. **Schema validation is required.** Add a regex/enum at the JSON schema level (`etc/schemas/billing.schema.json`) and at the Zod contract level (`src/schemas/`), wired into `bin/ots billing catalog validate`.
5. **`'identity'` is permanently canonical** as the legacy-plan marker. `legacy_plan_v1` stays in `CANONICAL_PLANIDS` as defensive whitelisting.

## 10. Implications of those decisions

### Scope shrinks

- No "unknown values" worklist. The chore's existing `LEGACY_PLANID_MAP` covers production. The data migration is just running the chore once over all orgs and confirming convergence.
- No Stripe customer metadata work.

### Scope expands (slightly)

Removing **all** interval suffixes — including the catalog `Plan.plan_id` — has implications beyond `organization.planid`:

- `Billing::Plan` currently identifies by `"#{base_plan_id}_#{interval}ly"` (`apps/web/billing/models/plan.rb:564`). If suffix removal is universal, the catalog needs a different identifier. Options:
  - Identifier = `"#{plan_id}_#{region}"` (composes plan with region instead of interval; works because each region has its own Stripe account).
  - Identifier = `plan_id` alone, with `interval` and `region` as separate fields, and the catalog Redis key composed differently (e.g. one Plan record per family with monthly and yearly prices as nested fields).
  - Identifier = `stripe_price_id` (already a field; price IDs are globally unique and immutable).
  - Identifier = `plan_id` + a Plan-per-interval-variant kept but the *identifier* is just `plan_id` with the interval-specific data on attached fields.

  Whichever model is picked, `Plan.load(plan_id)`, `Plan.find_by_stripe_price_id`, the `instances` sorted-set behaviour, and the upsert/prune logic in `refresh_from_stripe` all need to be reworked. This is the largest single piece of the change.

- Subscription metadata writes in `billing.rb:128, 655` already write `plan.plan_id` — they automatically pick up whatever the catalog identifier becomes. If we make `Plan.plan_id` unsuffixed, these writes become unsuffixed for free.

- `apply_subscription_to_org.rb:96-102` (owner path) and `pending_federated_subscription.rb#extract_plan_id` no longer need suffix-stripping logic — they get an unsuffixed value back from the resolver directly.

- `billing_service.rb#plans_match?` (the `_(month|year)ly$` normalization at lines 253-284) becomes pure dead weight. Remove after migration confirms.

- Tests that hard-code suffixed strings (most of `apps/web/billing/spec/controllers/`, `try/unit/auth/billing_hooks_try.rb`, frontend fixtures in `src/tests/fixtures/billing.fixture.ts`, etc.) need their plan_id literals rewritten. Mechanical find-and-replace, but high count.

### Schema validation work

The regex needs to match the canonical set: `^[a-z][a-z0-9_]*(_v\d+)?$`, optionally with an enum constraint matching `CANONICAL_PLANIDS`. Wiring:

- `etc/schemas/billing.schema.json` — add `propertyNames.pattern` (or `enum`) on the `plans` object.
- `src/schemas/contracts/organization.ts` — change `planid: z.string()` → `planid: z.string().regex(...)` or `z.enum(['free_v1', 'identity_plus_v1', 'team_plus_v1', 'legacy_plan_v1', 'identity'])`.
- `src/schemas/contracts/billing.ts` — similar for `target_plan_id`.
- `apps/web/billing/cli/catalog_validate_command.rb` — invoke the JSON schema validator against the loaded YAML.
- `apps/web/billing/cli/plans_validate_command.rb`, `products_validate_command.rb` — same pattern for Stripe-side validation.

### Revised scope summary

The data migration step is small (run the existing chore). The code change is medium: rework `Billing::Plan` identifier, simplify the resolvers, delete `plans_match?` normalization, update fixtures, add schema validation. Net code reduction once the change is complete.
