# Billing / Plans / Entitlements / Capabilities — Canonical Reading List

The system has a clean layered design: `Stripe` → `Plan catalog` → `Org entitlements (materialized)` → `Membership entitlements (role-intersected)` → `enforcement`. A crucial subtlety a new engineer must internalize: there are three distinct "capability/feature" concepts that are easy to conflate (see note at the end).

## START HERE (single best file)

### `docs/architecture/decision-records/adr-012-membership-level-entitlements.md`
The design rationale for the whole entitlement model. Explains why authority moved from role-string checks to materialized entitlement sets, and the org ∩ role intersection. Read this first, then the two feature modules below.

---

## Ruby — the core model layer

### `lib/onetime/models/organization/features/with_plan_entitlements.rb` `← the load-bearing file`
Organization-only entitlement resolution with the full fail-open (self-hosted) vs fail-closed (SaaS) strategy. Key design choice: `STANDALONE_ENTITLEMENTS` (billing disabled → full access) vs `FREE_TIER_ENTITLEMENTS` fallback vs raise `PlanCacheMissError` for unknown plans. Overrides entitlements and supers into the portable base — the MRO trick is documented in the header.

### `lib/onetime/models/features/with_entitlements.rb`
Portable base feature: `can?(entitlement) = entitlements.include?`. Design choice: a slim, model-agnostic foundation any Horreum can include; plan-specific fallback deliberately lives one layer up. Also holds `DEFAULT_FREE_TTL` (must mirror `free_v1` in `billing.yaml` — noted drift bug #3111).

### `lib/onetime/models/organization_membership.rb` (lines ~55–106)
Declares `ROLE_ENTITLEMENTS` — the role capability templates (`MEMBER_`/`ADMIN_`/`OWNER_ENTITLEMENTS`, composed by set union). Key design choice: roles are entitlement templates, not authority themselves; `manage_org`/`manage_billing` are owner-tier here, `incoming_secrets`/`custom_domains` are admin-tier.

### `lib/onetime/models/organization_membership/features/with_materialized_entitlements.rb`
The intersection logic: `membership.entitlements = org.entitlements ∩ ROLE_ENTITLEMENTS[role]`, reconciled as plan + grants − revokes. Key design choice: a membership can never exceed its org's plan, and `can?` reads the materialized set (with an on-the-fly fallback for unmaterialized rows).

### `lib/onetime/models/organization/features/with_materialized_entitlements.rb`
Org-level materialization: entitlements/limits are copied from `Billing::Plan` at webhook time, not resolved at read time. Design choice: staleness detection via `timestamp:content_hash` snapshot covering both entitlements AND limits.

### `lib/onetime/logic/base.rb` (lines ~190–325)
The enforcement gate: `require_entitlement!` (checks `auth_membership.can?`) and `require_entitlement_in!` (target-org variant). Design choice: strictly fail-closed — missing `auth_org`/`auth_membership`/inactive membership all raise; builds Stripe upgrade-path hints on denial.

---

## Ruby — the billing/Stripe layer (`apps/web/billing/` is a self-contained sub-app)

### `apps/web/billing/models/plan.rb` `← Stripe integration + plan identity`
The `Billing::Plan` Horreum cache of Stripe Products/Prices. Key design choices: family-based `plan_id` (unsuffixed, e.g. `identity_plus_v1`) with interval variants nested under prices; set `:entitlements` vs set `:features` (security vs marketing) vs hashkey `:limits` (flattened `teams.max` keys); `load_with_fallback` / `load_from_config` implement the Stripe-cache → `billing.yaml` fallback.

### `lib/onetime/models/organization/features/with_organization_billing.rb`
Where Stripe identity lives on the Organization: `planid`, `stripe_customer_id`, `stripe_subscription_id`, `subscription_status`. Design choice: organizations own subscriptions (not customers or teams).

### `lib/onetime/billing_config.rb`
Singleton loader for `billing.yaml` (`ENV` overrides, region/currency isolation, `enabled?` gate). This is the switch that flips the entire fail-open/fail-closed behavior.

### `apps/web/billing/plan_helpers.rb`
`upgrade_path_for(entitlement, planid)` and `plan_name` — powers the "upgrade to X" messaging referenced by the enforcement gate and the entitlement middleware.

---

## Config YAML — the declarative catalog

### `etc/examples/billing.example.yaml` (canonical template; live file is a symlink to user config)
The source of truth for what entitlements exist and which plans grant them. Design choice: an `entitlements:` registry (each with category + description, e.g. `incoming_secrets`, `manage_org`) is declared separately from `plans:` that reference them; limits use per-role caps (`role_owners_per_org`, `total_members_per_org`) plus an aggregate. Mirrors the `ROLE_ENTITLEMENTS` categories in Ruby.

---

## Frontend — capabilities surface (TypeScript)

### `src/schemas/contracts/config/section/ui.ts` (`uiCapabilitiesSchema`, ~line 108)
Defines `ui.capabilities.* = { burn, show, receipt, recipient }`. Key design choice: these are UI surface-composition flags (which secret-page actions render), NOT security entitlements. Optional booleans, "unset = enabled."

### `src/schemas/contracts/config/section/capabilities.ts`
A separate top-level capabilities map: per-user-type `{ api, email, custom_domains }` flags (legacy `Plan.load_plans!` surface). Design choice: coarse per-user-type feature advertisement, distinct from both `ui.capabilities` and server entitlements.

### `src/shared/stores/bootstrapStore.ts` (~line 176, `uiCapabilities` getter)
How the frontend reads capability flags out of the bootstrap payload. Consumers: `SecretForm.vue`, `WorkspaceSecretForm.vue`, `ShowReceipt.vue`, and route guards `apps/secret/routes/{secret,receipt}.ts`.

---

## Critical distinction to flag for the new engineer

Three separate concepts share overlapping vocabulary:

1. **Security entitlements** — `incoming_secrets`, `manage_org`, `custom_domains`, etc. Declared in `billing.yaml` `entitlements:`, granted by plans, gated on roles via `ROLE_ENTITLEMENTS`, enforced server-side by `require_entitlement!` → `membership.can?`. This is the real authorization system.
2. **`ui.capabilities.*`** (`burn`/`show`/`receipt`/`recipient`) — frontend surface composition only (`ui.ts`). Not security; decides which UI controls render.
3. **Top-level config capabilities** (`api`/`email`/`custom_domains` per `user_type`, `capabilities.ts`) — legacy Plan-derived feature advertisement.

The **intersection rule** that ties the model together:
$$\text{effective membership authority} = \text{org.entitlements (from plan/materialization)} \cap \text{ROLE\_ENTITLEMENTS[role]} + \text{grants} - \text{revokes}$$

*Plan features gate what the org bought; role capabilities gate what this member may use.*
