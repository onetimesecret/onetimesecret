---
title: Stripe Surface Audit (merged)
subject: Onetime Secret billing integration, Stripe contact surface, categorized for adding Airwallex as the provider for new billing relationships while existing customers stay on Stripe
date: 2026-09-24
code_snapshot: 2c532a271d4c57bedd39c76172f33140046e3703
provenance:
  - audit_a: full read of apps/web/billing, lib/onetime, lib/tasks, apps/api/{colonel,organizations,account}, apps/web/auth/operations, apps/web/core, src/, etc/, e2e/full-billing, docs/specs, docs/architecture, docs/runbooks, docs/planning (this session)
  - audit_b: independent review of audit_a against the same snapshot, with vendor checks on preview and tax/MoR ("stripe-surface-audit-astra.md")
  - reconciliation: disputed claims re-verified against code and Airwallex documentation on 2026-09-24; results in section 0
scope_rules:
  - Existing Stripe customers remain on Stripe. The new provider applies only to new, unassigned billing relationships. No customer transfer, re-enrollment or automatic Stripe cancellation is in scope.
  - Airwallex product/plan entity mapping is deferred. Vendor checks are limited to claims that change a categorization.
  - Categories are proposals for this migration, not accepted project policy. Code citations establish observed implementation, not normative guarantees.
airwallex_facts_verified:
  - Webhooks: headers x-timestamp and x-signature; HMAC-SHA256 over (timestamp + raw body); must return 200; retried otherwise
  - Subscription statuses: PENDING, IN_TRIAL, ACTIVE, UNPAID, CANCELLED
  - Subscription create: billing_customer_id, items[{price_id}], collection_method AUTO_CHARGE | CHARGE_ON_CHECKOUT | OUT_OF_BAND, payment_source_id, trial_ends_at, billing_cycle_anchor_at, metadata, enable_automatic_tax, default_tax_percent
  - Subscription update: existing item price_id cannot be changed (add item + remove item); default_proration_mode PRORATED | ALL | NONE; cancel_at_period_end supported; no pause/resume endpoints
  - Invoice preview: POST /api/v1/billing/invoices/preview previews the upcoming invoice for an existing subscription (subscription_id) or the first invoice of a proposed new subscription (items, discounts, tax, trial, anchor). No proration parameters for a change on an existing subscription are documented.
  - Airwallex Tax: calculates and applies tax on invoices, subscriptions and Hosted Billing Checkout; produces transaction-level exports. Merchant remains responsible for nexus determination, registrations, and "preparing, filing, and paying your tax returns on time."
  - Merchant of Record: early access, limited merchants, digital products only, direct sales only; supported integration is Hosted Payment Page; "Native API, Checkout Elements, Payment plugins, Payment links, Billing Checkout" are not supported in the beta.
  - Dunning: failed payments retried up to 4 times over 15 days. Single sandbox environment.
category_definitions:
  MANDATORY: Behaviour that must be handled to operate the two-provider system, including indirect effects on shared code. Does not require reproducing every current screen or endpoint.
  RECOMMENDED: Valuable preparatory work or substantial simplification; schedule independently where possible; leaving it doubles maintenance or forfeits a verified advantage.
  SUGGESTED: Optional expansion or structural choice with benefits beyond the provider switch.
  NOT_NECESSARY: No Airwallex equivalent or broad rewrite is required. Some of it must remain operational for Stripe customers; this is not a deletion instruction.
disposition_definitions:
  port: same behaviour behind the provider interface (one adapter per provider)
  rebuild: replace with provider-neutral application code
  keep: unchanged; used only by the Stripe cohort
  delete: remove; no replacement needed (only after the stated precondition)
---

# Stripe Surface Audit (merged)

## 0. Reconciliation record

Each row is a claim where the two audits differed. "Resolution" is what this document now says, with the evidence that decided it.

| # | Audit A said | Audit B said | Resolution (evidence) |
|---|---|---|---|
| 0.1 | Airwallex has no proration preview; rebuild locally as prework (T7) | An invoice-preview API exists; do not build a local calculator as prework | Both partly right. `POST /billing/invoices/preview` exists but is documented only for the upcoming invoice of an existing subscription or the first invoice of a new one; no proration parameters for a change to an existing subscription. Plan-change preview equivalence is **unverified and leans absent**. Local estimate stays as the fallback design, demoted from prework to conditional on V4. |
| 0.2 | Under MoR, tax leaves the app; tax capability has a `merchant_of_record` mode | MoR is early access, HPP only, excludes Billing Checkout; Airwallex Tax does not remit | B is right. MoR docs list "Billing Checkout" as unsupported in the beta; Tax overview keeps filing and remittance with the merchant. **Airwallex Billing tax is calculation + exports, the same shape as Stripe Tax.** The `merchant_of_record` mode is retained in the capability design as future-only; nothing in this plan depends on it. |
| 0.3 | `Billing::Plan` cache has a 12h TTL | The 12h expiry is on `catalog_synced_at` only | B is right. `models/plan.rb` L95: `class_json_string :catalog_synced_at, default_expiration: CATALOG_TTL`. Plan records do not expire; the README's "Plan objects with 12h TTL" is wrong. Consequence: a stale cache is silently served, not emptied. |
| 0.4 | Checkout host allowlist must become an array (mandatory) | One configured HTTPS origin is already supported alongside the Stripe default; expand only if needed | B is right on mechanism (`redirect.ts` L175-245). An array is needed only if a Stripe custom checkout domain (`STRIPE_CHECKOUT_HOST`) and an Airwallex host must both be allowed. No custom host is set in tracked config; production env unknown. Downgraded to RECOMMENDED, conditional. |
| 0.5 | Compute the federation hash locally from billing email on every event | That changes identity when the billing contact changes; define stable identity and benefit provenance | B is right. The Stripe-side hash is written once and never updated (`checkout_completed.rb` L250-257: immutable once set); recomputing from a mutable email is not equivalent. Resolution: local, stable identity record plus per-benefit provenance (provider, agreement). |
| 0.6 | Delete inbound `customer.updated` email sync and the loop-breaker | Stripe portal edits still flow through it; decide authority first | B is right while the Stripe Customer Portal is offered to the Stripe cohort. Resolution: scope inbound sync to Stripe-cohort orgs; app is the authority for Airwallex-cohort orgs; delete inbound only when the portal is retired. |
| 0.7 | Core `welcome.rb` portal handler is dead code | `/account/billing_portal` is still routed | B is right: `apps/web/core/routes.txt` L104. Resolution: consolidate onto `/billing/portal` or redirect; not delete-on-sight. |
| 0.8 | Regional local-currency accounts eliminate currency migration for the new cohort | Settlement currency and subscription currency are different concerns | B is right that nothing verified says Airwallex customers are multi-currency. Resolution: currency-migration service stays Stripe-only and is never ported; whether Airwallex needs a currency-change workflow is V9. |
| 0.9 | Cohort migration "renew into Airwallex" described in the dual-provider section | Out of scope | Out of scope per the stated constraints. The replacement-detection note is kept as a future option only (section 9). |
| 0.10 | ~1,800 lines of adapter to re-implement; ~3,000 lines deletable | Estimates not established; dependencies extend outside the directory | Both estimates are retained as estimates with the arithmetic shown (section 2.3). B's point that entitlement/identity/lifecycle dependencies extend outside `apps/web/billing` is correct and is why the mandatory list includes lib and auth files. |
| 0.11 | `ConfigLoader.load_all_from_config` becomes the sole loader, then delete the pipeline | The loader clears first, still writes `stripe_price_id`, rebuilds a Stripe index; compare deployed data first | B is right on sequencing. `config_loader.rb` L104 clears before load; price rows write `stripe_price_id` L252. Resolution: catalog inversion is staged (R1a-R1e) with an effective-data comparison first. Still MANDATORY in substance (provider-independent plan resolution and writer isolation). |
| 0.12 | Separate billing service: no benefit at ~1,000 customers | Retain the option; benefits depend on operational goals | Position kept: do not build a separate service now; establish the domain boundary first; the option stays open (section 5, S6). |
| 0.13 | Stripe pruner, federation eligibility and event ordering not called out as hazards | Three concrete coexistence hazards | Confirmed in code (section 3.4, H1-H3). `plan_persister.rb#prune_stale_plans` L142 subtracts Stripe ids from all cached ids; `find_federated_by_email_hash` L131 selects orgs where `stripe_customer_id` is empty; `subscription_deleted.rb#clear_federated_org` applies free tier without checking benefit source. |

## 1. Bottom line

The useful migration boundary is between application billing policy and payment-provider operations. Stripe currently supplies both: payment operations, and part of the application's product catalog, organization identity, lifecycle vocabulary and federation machinery. Moving the application responsibilities behind a local boundary is worth more than reproducing the Stripe integration for Airwallex.

- The runtime path a new customer takes (checkout, webhook, subscription applied to organization, entitlements materialized) is roughly 4,500 lines. It is dominated by two things that are not about payments: Stripe product metadata acting as the plan catalog, and Stripe's one-currency-per-customer workaround.
- The provider-specific core to implement for Airwallex is estimated at ~1,850 lines of adapter code plus a webhook verifier and translator (arithmetic in 2.3).
- The rest of the 22,480-line billing app is operator tooling against Stripe objects (8,643 lines of CLI), catalog push/pull machinery, and the currency-migration service. None of it needs porting.

Findings that change the plan more than line counts:

1. **Entitlements are provider-neutral at read time and Stripe-coupled at write time.** `ApplySubscriptionToOrg` materializes from `Billing::Plan`, a Redis projection of Stripe Products; `EntitlementMaterializeJob` refuses to run without a verified Stripe pull. A locally authoritative catalog with separate provider price bindings is the strongest preparatory project.
2. **Coexistence is not a provider field.** Three shared paths would misbehave with two providers in the same cache and the same federation index: the Stripe catalog pruner deactivates plans it does not know; Stripe federation selects any org without a Stripe customer id, including an Airwallex-paid one, and the deleted handler strips its benefit; dedup by event id does not establish ordering or current ownership (H1-H3).
3. **Federation identity lives in Stripe Customer metadata** and is written once. The local fallback computes from a mutable email. Coexistence needs a stable local identity record and per-benefit provenance, not a recomputation.
4. **Two Airwallex API facts land on plan change.** No in-place `price_id` swap (add + remove item with a proration mode), and no documented preview of a change to an existing subscription. The ~300-line Stripe invoice-line parser cannot be ported; the replacement experience is a design decision (V4), not a given.
5. **Tax remittance is not on offer through Airwallex Billing today.** Airwallex Tax calculates and exports; MoR is early access and excludes Billing Checkout. The stated hope of settling and remitting tax through Airwallex is not available for the subscription flow as documented. Plan tax as a provider capability with the same shape as Stripe Tax; keep the MoR mode as future.

**Position on structure:** do not make billing a separate application now. The entitlement chain, organization billing fields and materialization writers live in `lib/onetime`; the app is config-gated. A separate service adds authenticated service communication, cross-region identity and delivery/reconciliation work with no benefit until the domain boundary exists. Rebuild `apps/web/billing` in place around a per-relationship provider adapter, following `Onetime::DomainValidation::Strategy` and `Onetime::Mail::ProviderRegistry`. A thin `billingv2` is a valid transitional home for new controllers provided shared catalog and entitlement operations have one owner and there are never two writers of organization billing state.

## 2. Shape of the surface

### 2.1 Reproducible counts (Ruby under apps/web/billing, excluding spec/, try/, docs/)

| Area | Files | Lines |
|---|---:|---:|
| CLI | 59 | 8,643 |
| Operations (incl. catalog/ and webhook_handlers/) | 27 | 5,568 |
| Libraries | 13 | 2,995 |
| Controllers | 6 | 2,750 |
| Models | 3 | 1,135 |
| Initializers, worker, logic, root files | 13 | 1,389 |
| Total | 121 | 22,480 |

Other figures: 19 Stripe API resources touched; 14 webhook event types handled (6 catalog sync); 15 billing fields on Organization (9 Stripe-shaped), 4 unique indexes + 1 multi-index; 9 files outside the billing app with direct SDK calls; 24 backend endpoints called by the SPA (11 customer, 13 colonel); 1 hardcoded Stripe domain in the SPA.

### 2.2 Structural facts

- Most runtime Stripe calls are bare `Stripe::X.y`. `Billing::StripeClient` is a retry/idempotency helper that accepts Stripe resource classes; it is not an application-level provider interface and should not be the seam for Airwallex. The circuit breaker wraps only catalog pull and the catalog webhook handler.
- Declared source of truth is Stripe (`application.rb` L29, `models/plan.rb` L20-25, `lib/plan_validator.rb` L37-46). YAML is authoring input and disaster fallback. The free tier is always loaded from YAML.
- The 12h `CATALOG_TTL` applies to `catalog_synced_at` (freshness signal) only. Plan records persist; staleness is served, not surfaced.
- Billing ownership today means a non-empty `stripe_customer_id` with Stripe-specific unique indexes (`with_organization_billing.rb` L63-106, `subscription_owner?` L304).
- `lib/onetime/application/registry.rb` L214-217 skips the billing app unless `billing_config.enabled?`; disabling billing selects standalone entitlements and infinite limits (`with_plan_entitlements.rb` L199, `with_materialized_limits.rb` L79). Billing must stay enabled for both cohorts.
- "Billing enabled" and "Stripe key configured" are separate gates; three scheduled jobs skip on a blank `stripe_key`.

### 2.3 Estimates (labelled)

Adapter re-implementation for Airwallex, provider-specific only: checkout session build/create/retrieve (~400: `plans.rb#checkout_redirect`, `billing.rb#create_checkout_session`, `create_checkout_link.rb`, `logic/welcome.rb`), completion handler (~400 of `checkout_completed.rb` + resolver prefix logic), subscription read/cancel/reactivate/guard (~400 from `billing.rb` and `subscription_guard.rb`), webhook verifier + translator (~300), invoice list (~50), federation handler provider calls (~200). Total ~1,750-1,900. Excludes provider-neutral rework that both providers need.

Deletable after catalog inversion (R1e), non-test lines: `catalog/pull.rb` 335, `stripe_reader.rb` 95, `data_extractor.rb` 150, Stripe half of `plan_persister.rb` ~150, `metadata_validator.rb` 63, `stripe_retry.rb` 52, `catalog_updated.rb` 308, `stripe_circuit_breaker.rb` 335, `catalog_retry_job.rb` 196, `plan_cache_refresh_job.rb` ~100, Stripe path of `billing_catalog.rb` ~60, Stripe-projection fields and price cache in `plan.rb` ~150, circuit-retry fields in `stripe_webhook_event.rb` ~80. Total ~2,000; ~3,000 with their specs. `catalog/push.rb` (470) is kept as the Stripe provisioning tool.

### 2.4 Current flows

```
etc/billing.yaml --(catalog push)--> Stripe Products+Prices (metadata = plan definition)
  --(catalog pull | boot initializer | product.* price.* webhooks)--> Redis Billing::Plan
etc/billing.yaml -.(fallback, free plans).-> Redis Billing::Plan
Stripe checkout return | subscription event --> ApplySubscriptionToOrg <-- Redis Billing::Plan
  --> Organization (planid, status, period_end, stripe ids, entitlements_plan, limits_plan)
  --> Membership materialize_for_role!
Stripe Products+Prices --> Stripe-specific support and CLI tools
```

## 3. MANDATORY (coexistence behaviour)

Each item lists the code it touches; audit B's coexistence framing is folded into the item that owns the code.

### M1. Billing ownership, provider binding and cohort routing
- disposition: rebuild
- files: `lib/onetime/models/organization/features/with_organization_billing.rb` (fields L63-99, indexes L102-106, `LIVE_SUBSCRIPTION_STATUSES` L54, predicates `active_subscription?` L181, `past_due?` L188, `canceled?` L195, `billing_live?` L216, `paid?` L247, `subscription_owner?` L304, `stripe_claim_fields` L145); `apps/web/billing/metadata.rb` (`VALID_SUBSCRIPTION_STATUSES`, `FREE_PLAN_IDS`); `lib/billing_service.rb` (`compute_sync_status` L128-148)
- required: persist which provider, and which provider account/environment (live vs test, regional account), owns each billing relationship; route existing relationships by that binding; apply the enrollment default only to unassigned relationships; a cohort rule for an existing payer buying for a new organization or returning after cancellation (decision, not code)
- status: internal enum with per-provider mapping (S2); preserve the raw provider status alongside the interpretation; do not infer a delinquency policy from a status name
- shape: additive bindings (`billing_provider`, `billing_account_ref`, `billing_customer_ref`, `billing_subscription_ref`) can coexist with the historical `stripe_*` fields; renaming every historical field is unnecessary. Decide additive-binding vs BillingAccount/Agreement (S1) before writing code; doing the rename now and the split later migrates the same fields twice
- `stripe_claim_fields` (create-time unique-index CAS keyed on the `cus_` prefix) must become provider-aware

### M2. Catalog and offer coexistence
- disposition: rebuild (R1 is the recommended implementation); delete Stripe writers only after R1e
- files: `models/plan.rb` (Stripe projection fields; `find_by_stripe_price_id` L314-337; `ensure_stripe_configured!`); `operations/catalog/plan_persister.rb` (`prune_stale_plans` L142); `operations/catalog/{pull,stripe_reader,data_extractor,metadata_validator,stripe_retry}.rb`; `webhook_handlers/catalog_updated.rb`; `initializers/billing_catalog.rb`; `metadata.rb`; `lib/plan_validator.rb` (`resolve_plan_id` fail-closed on Stripe price id); `lib/onetime/jobs/scheduled/{plan_cache_refresh_job,catalog_retry_job}.rb`; `lib/stripe_circuit_breaker.rb`; `entitlement_materialize_job.rb` (`catalog_verified` gate L97-123)
- required: resolve each provider's external price to an application plan/offer without requiring an Airwallex plan to exist in Stripe; keep historical Stripe price bindings resolvable for existing subscriptions (including retired prices still referenced); prevent Stripe catalog writers from overwriting or pruning other providers' entries (H1)
- YAML as the authority is the recommended implementation (already the authoring source; `ConfigLoader` exists), not an intrinsic requirement

### M3. Checkout creation, completion and target organization
- disposition: port (adapter) + rebuild (intent correlation)
- files: `controllers/plans.rb#checkout_redirect` L41-250 (direct SDK; region hardcoded `'EU'` L446); `controllers/billing.rb#create_checkout_session` L76-281; `operations/create_checkout_link.rb#build_session_params` L122-157 (metadata `orgid, plan_id, tier, region, customer_extid` is load-bearing); `logic/welcome.rb` (`Checkout::Session.retrieve`, `cs_`/`cus_` prefix checks L39, L77); `lib/checkout_target_resolver.rb` (orgid -> `find_by_stripe_customer_id` requiring `cus_` -> owned default org; unique-index claim elects one creator L174-199); `webhook_handlers/checkout_completed.rb` (skips without `customer_extid` L79-86; replacement detection L179-190 logs and continues); `apps/web/auth/operations/ensure_default_workspace.rb` (`stripe_customer_id:` L109, claim L283)
- required: every checkout entry point (public redirect, authenticated API, colonel, CLI) goes through the same cohort decision; correlate the provider checkout with a local intent (plan, interval, organization, provider, created_at) so browser return and webhook can arrive in either order and a later change of the enrollment default does not reroute an in-flight intent; generalize prefix checks and the workspace-claim CAS
- Airwallex: Hosted Billing Checkout, subscription mode; metadata passthrough to the created subscription is V2; fallback is the local intent table keyed by session ref

### M4. Subscription state and entitlement application
- disposition: rebuild the input; keep the materialization engine
- files: `operations/apply_subscription_to_org.rb` (486; reads `.status`, `.items.data.first.price.id`, `.items.data.first.current_period_end`, `.metadata['plan_id'|'complimentary']`, `.customer`; L361-470); `Organization#update_from_stripe_subscription` L412-457 (`is_a?(Stripe::Subscription)`); `apply_free_tier` L102-116 (clears `stripe_subscription_id`, keeps `stripe_customer_id`)
- required: translate provider responses into application subscription facts before writing organization state; preserve the distinctions between payment state, access eligibility, "subscription may continue billing" and scheduled cancellation; write provider refs through the binding (M1)
- keep: `materialize_entitlements_for_org`, `materialize_entitlements_from_plan/_from_config`, `rematerialize_all_memberships!`

### M5. Webhook intake, jobs and reconciliation
- disposition: rebuild the envelope; port the verifier
- files: `controllers/webhooks.rb`; `lib/webhook_validator.rb` (`Stripe::Webhook.construct_event`, 24h tolerance); `models/stripe_webhook_event.rb` (dedup by `stripe_event_id`; state machine; `Stripe::Event.construct_from`); `workers/billing_worker.rb` (queue `billing.event.process`); `lib/onetime/jobs/publisher.rb` (`enqueue_billing_event`; sync fallback requires billing op); `operations/process_webhook_event.rb` (dispatch on Stripe type strings); `lib/onetime/middleware/registry.rb` L112-114 (CSRF exemption by path); rate-limit key `stripe_webhook`
- required: provider-specific verification and translation; provider/account-qualified event identity (an Airwallex event id and a Stripe event id must not collide, nor two Stripe accounts'); keep `/billing/webhook` usable for Stripe unchanged; add `POST /billing/webhooks/:provider`; define handling of repeated, delayed, out-of-order and previously-bound subscription events (H3). A shared provider-aware envelope is recommended; a separate Airwallex queue is acceptable initially
- Airwallex: `x-timestamp` + `x-signature`, HMAC-SHA256 over timestamp+body; event names V1

### M6. Federation identity, benefit provenance and deferred signup claims
- disposition: rebuild
- files: `with_organization_billing.rb#find_federated_by_email_hash` L123-133 (eligibility = `stripe_customer_id.to_s.empty?`); `webhook_handlers/subscription_federation.rb` (`Customer.retrieve` L272; `email_hash = metadata['email_hash'] || EmailHash.compute(customer.email)` L219-221; `Customer.update` `last_federation_*` L172-201); `webhook_handlers/subscription_deleted.rb#clear_federated_org` (applies free tier to every selected federated org); `checkout_completed.rb#set_stripe_customer_email_hash` L222-257 (immutable once set); `models/pending_federated_subscription.rb` (one record per `email_hash`, 90-day TTL); `ensure_default_workspace.rb#apply_pending_federation!` L389-515 (deferred until verified for password signups); `lib/onetime/cli/migrations/backfill_stripe_email_hash_command.rb`; `lib/onetime/utils/email_hash.rb`
- required: recognize ownership by either provider; record which provider and agreement supplied each federated benefit and remove only that benefit on that agreement's end; a stable local identity record that preserves the established hash rather than recomputing from the current billing email; pending claims that distinguish competing sources instead of one email-hash slot; preserve verified-signup gating
- keep: HMAC email-hash design, pending record, deferred claim
- retire: Stripe Customer metadata as the identity carrier and audit note (via adapter `write_customer_metadata` if a provider-side note is still wanted)

### M7. Customer billing lifecycle and management per cohort
- disposition: port (status, cancel, reactivate, guard, invoices); rebuild (change plan); decide (portal, preview)
- files: `controllers/billing.rb` `subscription_status` L378-458, `change_plan` L591-738, `cancel_subscription` L783-826 (no local write; relies on webhook), `reactivate_subscription` L837-891, `list_invoices` L290-337, `preview_plan_change` L470-579 + helpers; `lib/subscription_guard.rb`; `controllers/plans.rb#customer_portal_redirect` L298-375; `apps/web/core/controllers/welcome.rb#customer_portal_redirect` L182-215 (routed at `core/routes.txt` L104; reads deprecated `Customer#stripe_customer_id`); `lib/onetime/operations/org/reconcile.rb` (mode select L289-305, `Subscription.retrieve` L337)
- required: an intentional route for cancellation, payment-method maintenance and billing documents for each cohort. Stripe cohort keeps portal + current endpoints. For the Airwallex cohort decide per action: in-app (cancel, reactivate, invoices are already app-owned), provider-hosted (payment method via hosted checkout setup mode), or support workflow. Same-screen plan switching with detailed proration and reactivation are conditional on V4 and the chosen experience; a simpler effective-at-renewal change is a legitimate option
- `SubscriptionGuard` must consult the org's current provider

### M8. Indirect organization and account behaviour
- disposition: rebuild (small edits after M1)
- files: `lib/onetime/operations/org/delete.rb` (guard L316, refusal L398); `apps/web/auth/operations/customers/purge_preflight.rb` (`BILLING_IDENTIFIER_FIELDS` L14-21, `BILLING_STATUS_FIELDS` L23-32, `billing_state?` L569-576); `lib/onetime/cli/customers/purge_command.rb` (`stripe_billing?` L687; raw HMGET L615-627); `apps/web/auth/operations/workspace_collision.rb` (`BILLING_FIELDS` L26-41); `lib/onetime/cli/org/doctor_command.rb` (`UNIQUE_INDEXES` L97-103); `safe_dump_fields.rb` (`active_subscription` L46); colonel `list_organizations.rb` filters; `apps/api/organizations/cli/list_command.rb` (`--customer cus_`, `--subscription sub_`)
- required: liveness predicates, deletion checks, purge discovery, collision checks and billing claims understand both providers; otherwise the new integration is invisible to shared maintenance paths

### M9. Configuration, routing and external redirects
- disposition: rebuild
- files: `lib/onetime/billing_config.rb` (Stripe accessors L61-291; neutral `enabled?` L50, `plans`, `entitlements`, `currency`, `region`); `initializers/stripe_setup.rb`; duplicate SDK configuration in `billing_worker.rb` L26-35, `stripe_client.rb` L210-219, `plan.rb#ensure_stripe_configured!`, `cli/helpers.rb#stripe_configured?`; `etc/examples/billing.example.yaml`; `print_log_banner.rb` L266-306; `lib/onetime/middleware/impersonation_context.rb` (`BLOCKED_PREFIXES`/`BLOCKED_SUBTREES` L114-132; ADR-041 "deny list is method-independent"); `src/utils/redirect.ts` L147-245; `config_serializer.rb` L81-82 (`checkout_host`)
- required: configure both providers independently (`providers: {stripe:, airwallex:}`) plus a separate new-enrollment default; new webhook paths in route declarations and CSRF exemption; equivalent impersonation denial for any new route that mints a session; checkout destinations work for both cohorts (one extra configured origin already exists; array only if a Stripe custom checkout domain and an Airwallex host are both needed); billing stays enabled
- direct SDK calls outside the app that must go through the adapter: `apps/api/organizations/logic/organizations/update_organization.rb` L169-172 (billing email push), `org/reconcile.rb` L337, `with_organization_billing.rb` L160/172/505/538

### M10. Operationally usable launch and verification
- disposition: rebuild (diagnostics), port (live reads)
- files: `lib/onetime/operations/org/reconcile.rb`; `apps/web/billing/cli/diagnose_command.rb`, `orgs_validate_command.rb`, `sync_org_command.rb`; colonel `investigate_organization.rb` (`Subscription.retrieve(expand:)` L153), `get_user_details.rb` (`Subscription.retrieve` L365, `Invoice.list` L379, Stripe dashboard link L394-397), `reconcile_organization.rb`; webhook event browser (`list_stripe_webhook_events`, `get_stripe_webhook_event`); `src/tests/services/billing.service.spec.ts`; `e2e/full-billing/*`
- required: enough diagnostics and repair tooling to identify provider/account, checkout intent, subscription binding and failed events for either cohort; a normalized reconcile path for Airwallex (current reconcile selects Stripe sync solely from `stripe_subscription_id`); verification of changed paths across both providers, late Stripe events, and billing-disabled installs. Full colonel parity is optional; a usable inspection/repair path is not

### 3.4 Coexistence hazards confirmed in code (acceptance cases)

| ID | Hazard | Evidence | Acceptance case |
|---|---|---|---|
| H1 | Stripe catalog pruning deactivates an Airwallex-only plan | `plan_persister.rb#prune_stale_plans` L142-147: `stale_ids = Billing::Plan.instances.to_a - current_plan_ids` then `active = 'false'`; `current_plan_ids` comes from Stripe products | A Stripe pull or `product.*` webhook cannot change `active` on a plan whose offers are bound to another provider; historical Stripe prices remain resolvable |
| H2 | Stripe federation selects an independently Airwallex-paid org and the deleted handler strips it | `find_federated_by_email_hash` L131 filters on `stripe_customer_id.to_s.empty?`; `subscription_deleted.rb#clear_federated_org` applies `apply_free_tier(owner: false)` to each selected org without checking benefit source | A Stripe subscription event for the same identity cannot replace or remove a benefit whose recorded provenance is an Airwallex agreement |
| H3 | Dedup does not establish ordering or current ownership | federation owner lookup by customer id (`subscription_federation.rb` L225) vs subscription id (`subscription_handler.rb` L76); replayed events for an earlier subscription; `checkout_completed.rb` L124-190 logs an unexpected active replacement and continues | Events for a previously bound subscription are handled by an explicit policy (ignore if superseded, or reconcile), and the policy is the same for replay, circuit retry and live delivery |

## 4. RECOMMENDED (discrete improvements, schedulable before Airwallex work)

### R1. Make the application catalog authoritative (highest value)
- disposition: rebuild in stages; delete Stripe writers only at R1e
- the application owns plan identity, grants, limits, display text and offers; provider bindings say how an offer is sold, not what it grants
- existing `ConfigLoader` (`config_loader.rb` L104 `load_all_from_config`, L252 price rows write `stripe_price_id`, L283 `stripe_product_id = nil`, L313-330 keeps Stripe-written prices) is a starting point, not a ready replacement: it clears the cache first, writes Stripe-named fields, rebuilds a Stripe-specific index, and fills some price attributes with defaults

| Step | Deliverable | Completion evidence |
|---|---|---|
| R1a | Inventory and export the currently effective catalog and every Stripe price-to-plan binding, including retired offers still referenced by live subscriptions | Reviewed difference report against `etc/billing.yaml`; no assumption that YAML already contains every production value |
| R1b | Versioned local catalog with separately scoped provider bindings; plan identity distinct from interval/currency offer identity (`provider_refs: {stripe:, airwallex:}` per price row) | Free, paid, hidden, retired, regional and complimentary cases resolve without a live provider read |
| R1c | Publish validated catalog generations into the Redis read model atomically | Completeness checked before the active generation is replaced; per-process price lookup caches observe an intentional version; invalid publication never becomes an empty or free-only catalog |
| R1d | Switch boot (`billing_catalog.rb`), maintenance (`entitlement_materialize_job.rb`) and entitlement readers to the local generation | Materialization runs without Stripe credentials; `catalog_verified` gate removed |
| R1e | Stop competing Stripe catalog writers (`CatalogUpdated`, `Catalog::Pull`, `PlanCacheRefreshJob`, pruner), then retire their machinery (circuit breaker, `CatalogRetryJob`, circuit-retry fields) | `product.*`/`price.*` events cannot overwrite local entitlements; pruning cannot deactivate unrelated plans; old Stripe subscriptions still resolve their offers; H1 passes |

- keep after R1e: `Catalog::Push` and `catalog validate` as one-way Stripe provisioning and drift tools; `CatalogDrift` as a report
- do not delete generic retry behaviour (`StripeClient#with_retry`) because one use case disappears

### R2. Application-level provider boundary (registry + per-relationship adapter)
- disposition: rebuild
- precedents: `lib/onetime/domain_validation/strategy.rb` (factory `for_config`, strict/fallback), `base_strategy.rb` (capability matrix: active/passive/no-op tiers), `lib/onetime/mail/provider_registry.rb` (descriptors, lazy `const_get`, enumerated derived call sites, `frontend_provider_parity_spec.rb`)
- one difference from both precedents: billing selects an adapter per persisted billing relationship, not once per installation

```
Onetime::Billing::ProviderRegistry
  name 'stripe' | 'airwallex'; label; adapter_class; verifier_class (names, const_get lazily)
  accounts: [{id, live?, region, config_keys required/optional/masked}]
  checkout_hosts; capabilities (below); status_map provider -> internal enum

Billing::Providers::Base
  # core
  create_checkout(intent)          -> {url, session_ref, expires_at}
  fetch_checkout(session_ref)      -> CheckoutResult (SubscriptionSnapshot + customer ref)
  fetch_subscription(ref)          -> SubscriptionSnapshot (status enum, raw_status, period_end, plan_id, refs, complimentary, metadata)
  cancel_at_period_end(ref, bool)  -> SubscriptionSnapshot
  verify_webhook(request)          -> InboundEvent (provider, account, event_id, occurred_at, object_ref, raw)
  translate_event(envelope)        -> internal event name + snapshot
  # optional (NotSupported; UI hides)
  change_plan(ref, offer_ref, proration:); preview_change(ref, offer_ref)
  list_invoices(customer_ref); payment_method_update_url(customer_ref); portal_url(customer_ref)
  update_customer_email(customer_ref, email); write_customer_metadata(customer_ref, hash)
  tax_mode -> :none | :calculate | :merchant_of_record (future)
```

- outside adapters: authorization, organization selection, catalog ownership, benefit policy, membership materialization
- at the boundary: normalize money units, currency and timestamps explicitly; preserve raw provider status alongside the interpretation
- parity spec from day one: fails when `redirect.ts` hosts, the Zod `provider` enum, `billing.yaml` provider keys and the registry disagree

Capability matrix (initial):

| Capability | Stripe | Airwallex | Domain fallback |
|---|---|---|---|
| Hosted checkout, subscription mode | Checkout Session | Hosted Billing Checkout | none (required) |
| Metadata passthrough to subscription | `subscription_data.metadata` | subscription metadata; from hosted checkout unverified (V2) | local intent table keyed by session ref |
| Cancel at period end / reactivate | yes | yes | none |
| Change plan in place | item price swap + prorations | add item + remove item, `default_proration_mode` | cancel + new checkout, or effective-at-renewal |
| Change preview | `Invoice.create_preview` | invoice preview for upcoming/new only; change preview unverified (V4) | labelled local estimate |
| Invoices | `Invoice.list` | Billing invoices API | empty list; tab hidden |
| Payment method update | Customer Portal | hosted checkout, setup mode | none |
| Customer portal | yes | not documented | app's billing pages |
| Pause / resume | `pause_collection` | none | unsupported |
| Trials | `trial_period_days`, `trial_will_end` | `trial_ends_at`, IN_TRIAL; ending event unverified (V3) | app reminder from period dates |
| Tax | automatic_tax + tax_id_collection | `enable_automatic_tax` (calculation + exports); MoR future | none |
| Out-of-band collection | not built | `OUT_OF_BAND` | manual |
| Coupons at checkout | `allow_promotion_codes` | coupons exist; hosted-checkout entry unverified (V6) | hide field |
| Customer email sync | `Customer.update` inbound+outbound | outbound only | app is authority |
| Federation identity carrier | Customer metadata (current) | none | local identity record |

### R3. Normalize contracts without unnecessary UI replacement

| Surface | Actual coupling | Recommendation |
|---|---|---|
| New checkout | `billing.service.ts` L304 sends local `product` + `interval` | keep; provider selected server-side |
| Plan switching | `PlanSelector.vue` L108-111 matches `stripe_price_id === current_price_id`; `PlanChangeModal.vue` L150/L170 sends `stripe_price_id` as `new_price_id` | introduce a local offer identifier or a server-issued provider-bound reference; make preview/change capabilities explicit so the UI can hide or simplify. Renaming to `price_id` alone leaves the UI on external identity |
| Invoice list | `StripeInvoice` (`billing.service.ts` L104-115) is already an application DTO; `InvoiceList.vue` displays it and opens `invoice_pdf`/`hosted_invoice_url` | normalize provider responses to the DTO; rename optional; rewrite unnecessary |
| Checkout destinations | `redirect.ts` L147 default Stripe origin + one configured host | array only if actual host requirements exceed that (0.4) |
| Currency changes | `planSelectorLogic.ts` L50-56 cross-currency blocking; migration components carry Stripe-shaped state | scope to Stripe cohort; let V9 decide the Airwallex experience |
| Overview, cancel, org settings | application responses (`OrganizationSettings.vue` L305-314 `active_subscription`) | preserve |
| Status enums | `subscriptionStatusSchema`, `invoiceStatusSchema`, `SUBSCRIPTION_OPTIONS` | move to the internal enum (S2) |
| Colonel schemas | `source: 'stripe'|'local_config'`, `stripe_configured`, `mode: 'stripe_sync'`, `colonelStripeOrganizationSchema`, org rows with `stripe_*` ids | extend incrementally with a `provider` column; keep truthful Stripe labels on Stripe-only tooling |

### R4. Contact synchronization and repair, provider-aware
- files: `update_organization.rb` L117-192; `webhook_handlers/customer_updated.rb`; `lib/webhook_sync_flag.rb`; `cli/sync_billing_email_command.rb`; `org/reconcile.rb`; `org doctor`; colonel `investigate`, `get_user_details`, billing roster
- choose an authority and conflict policy before simplifying: app is the authority for Airwallex-cohort orgs (outbound push only); Stripe-cohort orgs keep inbound sync while the Stripe portal can edit details; delete inbound sync and the loop-breaker only when the portal is retired
- keep reconcile, doctor and support inspection useful for Stripe; add a normalized repair path for Airwallex; preserve dry-run behaviour
- `/account/billing_portal` (core) is still routed: consolidate onto `/billing/portal` or redirect; drop the deprecated `Customer#stripe_customer_id` read

### R5. Currency migration service: keep for Stripe, never port
- files: `lib/currency_migration_service.rb` (648); endpoints `check-currency-migration`, `migrate-currency`; 409 branch `billing.rb` L212-273; org fields `pending_currency_migration`, `migration_target_price_id`, `migration_effective_after`; SPA `CurrencyMigrationModal.vue`, `PendingMigrationBanner.vue`
- gate on `billing_provider == 'stripe'`; exclude from the provider interface; whether Airwallex needs any currency-change workflow is V9

### R6. Tax as a provider capability with the same shape as Stripe Tax
- files: `create_checkout_link.rb#apply_tax_policy!` L167-178; `STRIPE_AUTOMATIC_TAX`; `billing.rb#extract_tax_amount` L1312-1332
- keep tax input collection, returned totals and provider documents behind the checkout/invoice boundary; do not remove tax or invoice UI on an assumed MoR arrangement; revisit if MoR reaches Billing Checkout (V7)

### R7. Dead and vestigial Stripe imports
- disposition: delete
- `lib/onetime/refinements/stripe_refinements.rb` (+ `logic/base.rb` L9 require; `get_account.rb` L5/L19 unassigned attrs; `get_colonel_info.rb` L5)
- `bootstrap.ts` L18 Stripe type import, L1078-1081 `stripe_customer`/`stripe_subscriptions` (no serializer emits); `bootstrapStore.ts` L60-63/117-120; `account.ts` L13-14; `stripe-types.ts`; `package.json` `stripe` npm dep
- `core/welcome.rb#welcome` L125-159 retired Payment Link landing (route L103 still declared: remove route + handler together); `BillingConfig#payment_links`; `caboose.payment_link`

### R8. Lifecycle emails and triggers
- `trial_will_end.rb` -> `:trial_expiring`; `subscription_updated.rb` L94-118 -> `:subscription_changed`; templates gated on `billing_config.enabled?`; map triggers per provider (V3); templates unchanged

### R9. Test scenarios and operational documentation
- retain Stripe fixtures, VCR cassettes (~230), stripe-mock, webhook tooling, e2e paths
- add shared application-contract scenarios (checkout intent, subscription snapshot, cancellation, entitlement application, benefit provenance) plus provider-specific verification tests; one shared example group both adapters must pass
- update `apps/web/billing/README.md` (Stripe alignment table), `docs/stripe-configuration.md` (names `STRIPE_WEBHOOK_SECRET`; code reads `STRIPE_WEBHOOK_SIGNING_SECRET`), runbooks `duplicate-plans-on-plans-page.md` and `entitlement-rematerialization.md`, ADR-041 path list

## 5. SUGGESTED

| ID | Opportunity | Scope judgment |
|---|---|---|
| S1 | Separate payer from organization (BillingAccount / Agreement per `docs/specs/billing-decoupling`) | Make the model decision early because it changes keys, authorization and routing. Not needed merely to retain Stripe and add Airwallex; needed for procurement, contractors and payer handoff. The current unique Stripe-customer index expresses one-customer/one-organization; a minimal binding must not bake that into every provider. Adding a payer object alone does not implement separate billing authority (checkout, portal, invoice access, membership permissions) |
| S2 | Internal status enum with per-provider mapping | pending, trialing, active, past_due, unpaid, canceled, paused. Stripe: incomplete -> pending, incomplete_expired -> canceled. Airwallex: PENDING -> pending, IN_TRIAL -> trialing, ACTIVE -> active, UNPAID -> past_due or unpaid by dunning stage (decision), CANCELLED -> canceled. Keep raw status |
| S3 | Thin `billingv2` app | Valid transition for new controllers and provider-neutral orchestration while legacy Stripe routes stay, provided shared catalog/entitlement operations have one owner and organization billing state has one writer. Auth already requires billing code for pending claims (`ensure_default_workspace.rb` L428); moving controllers does not remove that |
| S4 | CLI namespace split | Keep 8,643 lines of Stripe-object commands under `bin/ots billing stripe ...`; add a small neutral set via the interface (`customers show`, `subscriptions list|cancel`, `invoices`, `sync-org`, `diagnose`) |
| S5 | Provider-aware diagnostics and longer local event history | Current webhook record is 5-day processing state (10k index), not an accounting ledger; define retention and redaction; supports support investigations and any later revenue-recognition tooling |
| S6 | Separate billing service | Valid strategic option; adds authenticated service communication, cross-region identity, delivery/reconciliation and support work. Establish the domain boundary first; choose it later for those operational benefits |
| S7 | Invoice-based procurement (`OUT_OF_BAND`) and broader payment choices | Explore after confirming the Airwallex collection experience; do not add a generalized ledger or usage billing because a provider offers them |
| S8 | Incidental cleanup | `verified_by == 'stripe_payment'` value; `stripe_webhook` rate-limit key; `class_methods.rb` L323 log regex; hardcoded `'EU'` in `plans.rb#detect_region`; `pmc_` config and `PmcResourceMissing` stay inside the Stripe adapter; ~60 locale keys under `web.admin.billing.*`/`web.billing.*` naming Stripe (keep truthful labels on Stripe-only tooling; no global replace) |

## 6. NOT_NECESSARY

| ID | Surface | Disposition during coexistence |
|---|---|---|
| N1 | YAML -> Stripe product metadata -> Redis entitlement round trip | replace its authority role with the local catalog (R1); no Airwallex metadata round trip |
| N2 | Catalog push and Stripe product/price/metadata administration (`push.rb`, `products *`, `prices *`, `plans validate`, `products validate`, `prices generate|validate`, `update-stripe-metadata`; TS `StripeMetadataSchemaDefinition`, `getStripePlans`, `shouldCreateStripeProduct`; YAML `stripe_metadata_schema`, `app_identifier`, `match_fields`) | keep as optional Stripe provisioning/support tools; off the startup path after R1d; never port |
| N3 | Circuit breaker, catalog retry job, circuit-retry fields, `CircuitOpenError` mapping | delete at R1e |
| N4 | Stripe object CLI (`coupons`, `coupon validate`, `refunds *`, `payment-methods *`, `sigma *`, `events`, `products events`, `customers create|delete`, `subscriptions pause|resume|update`, `config`, `test *`) | keep for the Stripe cohort |
| N5 | Stripe SDK/API version pin and credentials (`Gemfile` L190-193) | keep while Stripe customers remain |
| N6 | Stripe developer tools and tests (`bin/stripe-dev-webhook`, `stripe:version`, `trigger-webhook`, `STRIPE_TEST_PRICE_ID*`, stripe-mock, cassettes, `vcr:billing:*`) | keep |
| N7 | Historical backfills and deprecated fields (`backfill-stripe-email-hash`, `backfill-subscription-status`, `grant-probono-entitlements`, `Customer` deprecated `stripe_*`, v1 migration fields) | keep; audit live consumers before removing anything (core portal and purge still read the deprecated Customer fields) |
| N8 | Provider-neutral entitlement/limit/membership engine (`with_plan_entitlements.rb`, `with_materialized_limits.rb`, `with_materialized_entitlements.rb`, `with_entitlements.rb`, membership materialization, `Org::SetPlan`, `EntitlementOverride`, `SecretLifetimePolicy`, chores, `entitlements` controller, `grant_probono_entitlements.rb`, `materialize_plans.rb`) | retain; change catalog/subscription inputs only |
| N9 | Free plans, complimentary grants, operator overrides | keep locally expressible; no zero-value Airwallex subscriptions required |
| N10 | Every current billing screen and Stripe response field | preserve application DTOs where they work; unsupported optional features may have a smaller experience |
| N11 | Existing customer/payment-method/subscription transfer | excluded; no automatic Stripe cancellation or re-enrollment when the enrollment default changes |
| N12 | Bank-account management, FX or treasury inside the app | no direct integration is justified by regional accounts; keep billing currency, provider account, legal seller and settlement destination conceptually distinct |
| N13 | Documentation archive, security assessments, `.claude/worktrees` copies, comment-only references (`config.defaults.yaml` L475, L1195; `features.ts` L560) | ignore; fix wording when touched |

## 7. Airwallex capabilities: verified limits, not assumed parity

- **Tax calculation and tax remittance are separate decisions.** Airwallex Tax calculates and exports; the merchant remains responsible for nexus, registration, filing and payment. This is the same scope as Stripe Tax. The Taxually layer is not in the codebase and its replacement is a commercial question, not a code one.
- **Merchant of Record** is early access, limited merchants, digital-only, direct-sales-only, Hosted Payment Page only, and explicitly excludes Billing Checkout. Nothing in this plan depends on it.
- **Invoice preview** exists for upcoming and first invoices. Preview of a change to an existing subscription is not documented. Plan-change experience is V4.
- **No in-place price swap; no pause/resume.** Adapter `change_plan` is add + remove with a proration mode, or cancel + create. Paused/resumed handlers are Stripe-only.
- **Collection methods** include `OUT_OF_BAND`, which maps to the decoupling spec's send-invoice sales (S7).
- **Dunning** is provider-side (4 retries over 15 days). The app has no dunning logic; the `UNPAID` mapping during the retry window is a decision (S2).
- **Multi-currency:** regional settlement accounts are a treasury concern. Whether an Airwallex customer or subscription can change currency without cancel + recheckout is V9.
- None of the above is exclusive to Airwallex or inherently unavailable in Stripe; the opportunity is to simplify application responsibilities using the capabilities and commercial terms actually selected.

## 8. Sequence of independently reviewable work

| Stage | Task | Depends on | Result | Maps to |
|---|---|---|---|---|
| 1 | Catalog inventory, effective-data comparison, historical offer mapping | current deployments/catalog exports; no Airwallex research | what can move local without silently changing existing offers | R1a |
| 2 | Local catalog authority and publication; retire competing catalog writers | 1 | entitlement maintenance no longer depends on Stripe metadata or availability; H1 passes | R1b-R1e, N1, N3 |
| 3 | Provider binding/cohort rules; normalized subscription snapshot; neutral event envelope | decide additive binding vs payer/agreement (S1) | Stripe behaviour runs through the new seam before Airwallex exists | M1, M4, M5, S2 |
| 4 | Coexistence safeguards: federation identity + provenance, pending claims, deletion/purge, event binding policy | 3 | shared code recognizes both providers and the source of each benefit; H2, H3 pass | M6, M8 |
| 5 | Common checkout intent, management capabilities, application DTOs, config split, dead-import removal | 3 (2 for catalog design) | public, customer and operator surfaces use one routing decision | M3, M7, M9, R3, R4, R7 |
| 6 | Airwallex adapter and required lifecycle operations | deferred provider mapping/capability research (V1-V9) | new cohort can enrol and be managed; Stripe cohort unchanged | R2, M7 |
| 7 | Controlled enrollment rollout and operational reconciliation | 2-6 and verification | default enrollment changes without moving subscriptions; in-flight intents keep their provider | M10 |
| 8 | Optional `billingv2`/service extraction, payer expansion, deeper UI simplification | established boundary | further benefits without entangling the launch | S1, S3, S6 |

Stages 2-5 can be delivered and reviewed while all paying customers still use Stripe.

## 9. Verification cases (proposed acceptance, not results)

- Existing Stripe renewals, invoices, portal sessions, plan changes and cancellation continue to route to Stripe.
- A new Airwallex checkout from every enabled entry point (public redirect, authenticated API, colonel link, CLI link) resolves to the intended organization exactly once; browser return and webhook may arrive in either order.
- Changing the enrollment default does not reroute an already-created checkout intent.
- A Stripe event for the same federation identity cannot replace or remove an independently owned Airwallex benefit (H2).
- Events for a previously bound subscription are handled by an explicit reconciliation policy, identically for live delivery, replay and retry (H3).
- Local catalog publication and Stripe catalog events cannot invalidate other providers' offers; historical Stripe prices remain resolvable (H1).
- Organization deletion, account purge, workspace collision and support inspection recognize either provider's billing relationship.
- Billing-disabled installations retain standalone behaviour.
- New checkout/portal routes receive equivalent authorization, redirect-allowlist and impersonation-denial treatment.
- Future option only (out of scope now): if a Stripe-cohort org is ever moved, completion of an Airwallex checkout sets the binding to Airwallex and the Stripe subscription is cancelled at period end through the Stripe adapter; replacement detection must be provider-crossing.

## 10. Verify with Airwallex before adapter design

| ID | Question | Decides |
|---|---|---|
| V1 | Billing webhook event names and payloads: subscription created/updated/cancelled, invoice paid/failed, checkout completed, customer updated | M5 translator |
| V2 | Does Hosted Billing Checkout carry metadata onto the created subscription | M3 intent correlation; fallback is the local intent table |
| V3 | Trial-ending event, or app-scheduled reminder from `trial_ends_at` | R8 |
| V4 | Can `POST /billing/invoices/preview` (or another call) preview a change to an existing subscription with prorations; proration behaviour of add + remove in one update; credit issued vs applied | M7 plan-change experience; whether a labelled local estimate is needed |
| V5 | Invoice document URLs (hosted page, PDF) | M7 invoice DTO |
| V6 | Coupon/promo entry on hosted checkout | R2 capability |
| V7 | MoR roadmap for Billing Checkout; eligibility in CA, EU, NZ, US | R6 future mode |
| V8 | Sandbox: single environment; webhook replay and event simulation | R9 |
| V9 | Currency per customer/subscription: can an Airwallex subscription change currency without cancel + recheckout | R5 scope, R3 currency UI |
| V10 | Multiple accounts (per-region local-currency accounts): one API key per account or one key with account routing; effect on event identity and registry `accounts` | M1, M5 |

## 11. File inventory (with corrections from reconciliation)

Category codes: M = MANDATORY, R = RECOMMENDED, S = SUGGESTED, N = NOT_NECESSARY.

### 11.1 apps/web/billing

| File | Stripe contact | Cat. | Disposition |
|---|---|---|---|
| `application.rb`, `config.rb`, `plan_helpers.rb`, `region_normalizer.rb` | no SDK | N | keep |
| `errors.rb` | `CatalogValidationError`, `CircuitOpenError`, `InvalidPlanMetadataError`, `PlanCacheMissError` | S | keep; drop catalog/circuit errors at R1e |
| `metadata.rb` | product metadata vocabulary; `VALID_SUBSCRIPTION_STATUSES`; `FREE_PLAN_IDS` | M | rebuild: keep limit/entitlement keys; statuses -> enum; retire SYNCABLE_FIELDS at R1e |
| `initializers/stripe_setup.rb` | global SDK config; pmc + checkout-host validation | M | port into Stripe adapter |
| `initializers/billing_catalog.rb` | `Catalog::Pull` at boot | M | rebuild at R1d |
| `controllers/base.rb` | `stripe_api_key_missing?` | R | rebuild: provider configured? |
| `controllers/webhooks.rb` | Stripe signature header; enqueue | M | rebuild: per-provider route |
| `controllers/plans.rb` | `Checkout::Session.create` (direct); `BillingPortal::Session.create`; region `'EU'` | M | port; portal Stripe-only |
| `controllers/billing.rb` (1,417) | checkout (StripeClient); `Invoice.list`; `Subscription.retrieve/update` x6; `Invoice.create_preview`; `Price.retrieve`; currency 409 | M | port status/cancel/reactivate/invoices; change_plan + preview per V4; currency endpoints Stripe-only |
| `controllers/entitlements.rb`, `controllers/page.rb` | none | N | keep |
| `logic/welcome.rb` | `Checkout::Session.retrieve`; prefix checks | M | port |
| `lib/stripe_client.rb` | retry/idempotency helper | R | keep inside Stripe adapter; not the seam |
| `lib/stripe_circuit_breaker.rb` | catalog breaker | N | delete at R1e |
| `lib/billing_service.rb` | plan resolution from subscription; sync status; compare states | R | rebuild on snapshot + enum |
| `lib/checkout_target_resolver.rb` | `cus_` prefix; Stripe-id lookup; claim CAS | M | rebuild: provider-aware refs; election logic stays |
| `lib/currency_migration_service.rb` (648) | 13 Stripe calls | R | keep Stripe-only; never port |
| `lib/plan_resolver.rb` | interval vocabulary | N | keep |
| `lib/plan_validator.rb` | `find_by_stripe_price_id` fail-closed | R | rebuild: (provider, ref) lookup at R1b |
| `lib/pmc_resource_missing.rb` | pmc error parse | N | keep inside Stripe adapter |
| `lib/subscription_guard.rb` | `Subscription.retrieve` | M | port; provider-aware |
| `lib/webhook_validator.rb` | `Webhook.construct_event`; record init | M | Stripe verifier |
| `lib/webhook_sync_flag.rb` | email-sync loop breaker | R | keep for Stripe cohort until portal retired (R4) |
| `lib/materialize_progress_renderer.rb`, `lib/test_support/*` | none | N | keep |
| `models/plan.rb` (516) | Stripe projection; price-id cache; `ensure_stripe_configured!`; `catalog_synced_at` TTL | M | rebuild at R1b-c |
| `models/stripe_webhook_event.rb` (380) | Stripe-shaped fields; `Event.construct_from`; circuit-retry fields | M | rebuild: provider/account-qualified event record |
| `models/pending_federated_subscription.rb` | Stripe subscription shape; one slot per hash | M | rebuild: snapshot input; source-distinguishing records |
| `operations/apply_subscription_to_org.rb` (486) | Stripe subscription shape | M | rebuild input; keep materialization |
| `operations/create_checkout_link.rb` | session params; `apply_tax_policy!`; StripeClient | M | port; tax per R6 |
| `operations/grant_probono_entitlements.rb`, `materialize_plans.rb` | none | N | keep |
| `operations/process_webhook_event.rb`, `webhook_handlers/base_handler.rb` | dispatch on Stripe types | M | rebuild keys |
| `operations/catalog/{pull,stripe_reader,data_extractor,metadata_validator,stripe_retry}.rb` | Stripe catalog read | M | delete at R1e |
| `operations/catalog/plan_persister.rb` | `upsert_from_stripe_data`; `prune_stale_plans` (H1) | M | rebuild: local publication; delete Stripe half at R1e |
| `operations/catalog/config_loader.rb`, `validate.rb` | YAML -> Redis (clears first; writes `stripe_price_id`) | R | rebuild into the R1c publisher |
| `operations/catalog/push.rb` (470) | `Product.create/update`, `Price.create` | N | keep as Stripe provisioning tool |
| `webhook_handlers/catalog_updated.rb` (308) | 6 catalog events | N | delete at R1e |
| `webhook_handlers/checkout_completed.rb` (386) | `Subscription.retrieve` x2; Customer email_hash stamp; replacement detection (H3) | M | rebuild on envelope + snapshot; binding policy |
| `webhook_handlers/subscription_federation.rb`, `federation_support.rb` | `Customer.retrieve/update`; eligibility (H2) | M | rebuild: local identity + provenance |
| `webhook_handlers/subscription_{created,updated,deleted,resumed}.rb`, `subscription_handler.rb`, `trial_will_end.rb` | Stripe event semantics; deleted strips federated benefit (H2) | M | rebuild on internal events; provenance-checked removal |
| `webhook_handlers/subscription_paused.rb` | `paused` status | N | Stripe-only |
| `webhook_handlers/customer_updated.rb` | inbound email sync | R | Stripe cohort only (R4) |
| `workers/billing_worker.rb` (227) | SDK config; `Event.construct_from` | M | rebuild: envelope deserialization |
| `cli/*` (59 files, 8,643) | see N2, N4, S4; helpers infer live/test from `sk_test_` | N | keep under `stripe` namespace; registry `live?` replaces prefix inference |

### 11.2 lib/onetime and lib/tasks

| File | Stripe contact | Cat. | Disposition |
|---|---|---|---|
| `billing_config.rb` (342) | Stripe accessors/validators | M | rebuild: providers block + enrollment default |
| `models/organization/features/with_organization_billing.rb` (560) | fields, indexes, 4 direct SDK calls, `update_from_stripe_subscription`, federation eligibility, status constants | M | rebuild (M1, M4, M6) |
| `models/organization.rb` | `planid` default; features; `caboose` | N | keep |
| `with_plan_entitlements.rb`, `with_materialized_limits.rb`, `with_materialized_entitlements.rb`, `models/features/with_entitlements.rb`, membership materialization | guarded `Billing::Plan` reads | N | keep |
| `safe_dump_fields.rb` | `active_subscription -> billing_live?` | M (via M8) | small edit after enum |
| `organization/features/migration_fields.rb` | v1 Stripe ids; unguarded `BillingService.free_plan?`; `caboose.payment_link` | N | keep; payment_link part with R7 |
| `models/customer.rb`, `customer/features/{deprecated_fields,migration_fields}.rb` | legacy `planid`; `pending_plan_intent`; deprecated `stripe_*` | N | keep; audit consumers before removal |
| `customer/features/status.rb` | `verified_by == 'stripe_payment'` | S | rename value when touched |
| `jobs/publisher.rb` | `enqueue_billing_event`; sync fallback | M | rebuild (M5) |
| `jobs/scheduled/plan_cache_refresh_job.rb`, `catalog_retry_job.rb` | Stripe pull; circuit retry | N | delete at R1e |
| `jobs/scheduled/maintenance/entitlement_materialize_job.rb` | `catalog_verified` gate; key check | R | rebuild at R1d |
| `operations/billing/stripe_organizations.rb`, `catalog_drift.rb`, `webhook_visibility.rb` | Stripe index; `source` enums; unguarded requires | R | extend with provider; keep drift as report |
| `operations/org/reconcile.rb` (538) | `require 'stripe'`; `Subscription.retrieve`; mode select by `stripe_subscription_id` | M | port; provider-aware mode select (M10) |
| `operations/org/{set_plan,delete,entitlement_override,transfer_ownership,create}.rb`, `operations/memberships/entitlement_override.rb` | Stripe-derived fields only | N (delete guard: M8) | keep; guard edit |
| `refinements/stripe_refinements.rb`; `logic/base.rb` L9 | gem load for all Logic | R | delete (R7) |
| `logic/base.rb` entitlement checks; `incoming/recipient_resolver.rb` | guarded `PlanHelpers` | N | keep |
| `middleware/impersonation_context.rb` | Stripe-minting path deny list | M (via M9) | add new-provider routes |
| `middleware/registry.rb` L112-114 | CSRF exemption path | M | add per-provider path |
| `application/otto_hooks.rb` | 503 mappings | R | drop `CircuitOpenError` at R1e |
| `application/registry.rb` L214-217 | app gate | N | keep; billing stays enabled |
| `initializers/print_log_banner.rb` | masked Stripe config | R | per-provider |
| `class_methods.rb` L323 | log regex | S | harmless |
| `secret_lifetime_policy.rb`, `mail/*`, chores | `billing_enabled?` gates | N | keep |
| `utils/email_hash.rb`, `utils/diagnostics_ref.rb` | comments | N | keep |
| `cli/billing/{orgs_stripe,catalog_drift}_command.rb` | index pager; drift | R | extend with provider |
| `cli/migrations/*` | backfills | N | keep; historical |
| `cli/customers/purge_command.rb`, `cli/customers/plan_set_command.rb` | Stripe protection; unguarded `BillingService` | N (purge: M8) | provider-aware protection |
| `cli/org/{doctor,delete,reconcile}_command.rb`, entitlement CLIs, `cli/worker_command.rb`, `cli.rb` | field lists; flags; worker load | N (doctor indexes: M8) | small edits |
| `lib/tasks/spec.rake`, `spec_selection.rake` | VCR tasks; exclusions | N | keep |

### 11.3 apps/api, apps/web/auth, apps/web/core

| File | Stripe contact | Cat. | Disposition |
|---|---|---|---|
| `api/organizations/logic/organizations/update_organization.rb` | `Customer.update` email; `WebhookSyncFlag` | M | port via adapter; authority per R4 |
| `api/organizations/logic/organizations/delete_organization.rb` | guard mapping | N | keep |
| `api/organizations/cli/list_command.rb` | `cus_`/`sub_` lookups | M (via M8) | provider refs |
| `api/colonel/logic/colonel/get_user_details.rb` | `Subscription.retrieve`; `Invoice.list`; dashboard URL | R | port; provider-aware link |
| `api/colonel/logic/colonel/investigate_organization.rb` | `Subscription.retrieve(expand:)`; `Stripe::Product` check | R | port |
| `api/colonel/logic/colonel/reconcile_organization.rb` | `:stripe_error` mapping | M (via M10) | provider-aware |
| other colonel billing logic (`list_stripe_organizations`, `list_stripe_webhook_events`, `get_stripe_webhook_event`, `list_pending_federated_subscriptions`, `get_billing_catalog`, `get_available_plans`, `set_entitlement_preview`, `get_organization_detail`, `list_organizations`, `list_users`, `update_organization_plan`, `update_user_plan`, `create_checkout_link`, `create_organization_checkout_link`, `delete_organization`, `get_system_settings`, `get_colonel_info`) | `Billing::*`; Stripe-named wire fields; no direct SDK | R | extend with provider; checkout-link ops route through cohort decision (M3) |
| `api/account/logic/account/get_account.rb` | dead refinements | R | delete import |
| `api/account/logic/account/get_entitlements.rb` | `source: 'stripe'` | R | rename enum |
| `web/auth/operations/ensure_default_workspace.rb` (518) | `stripe_customer_id:`; claim; pending federation | M | rebuild (M3, M6) |
| `web/auth/operations/workspace_collision.rb`, `customers/purge_preflight.rb` | Stripe field lists | M (via M8) | provider-aware lists |
| `web/auth/operations/customers/{change_email,doctor,set_plan}.rb` | comments; `stripe_payment` provenance; `customer.planid` | S | rename value when touched |
| `web/core/controllers/welcome.rb` (230) | portal on deprecated Customer field (routed L104); retired Payment Link landing (routed L103); legacy tier redirect (L101-102) | R | consolidate/redirect portal; remove landing route + handler; keep redirect |
| `web/core/views/serializers/authentication_serializer.rb` | `Plan.load_with_fallback` | N | keep |
| `web/core/views/serializers/config_serializer.rb` L81-82 | `billing_enabled`, `checkout_host` | R | `checkout_hosts[]` if needed (0.4) |

### 11.4 src (SPA), etc, tooling, e2e

| File | Stripe contact | Cat. | Disposition |
|---|---|---|---|
| `src/utils/redirect.ts`, `src/plugins/core/appInitializer.ts` | Stripe default origin + one configured host | R | array only if required (0.4) |
| `src/services/billing.service.ts`, `src/schemas/contracts/billing.ts`, `shapes/account/billing.ts`, `src/types/billing.ts` | `stripe_price_id`; `StripeInvoice` DTO; Stripe enums; proration response; currency-conflict | M (plan-change identity) / R (rest) | offer identity for plan change; normalize to existing DTOs; enums -> S2 |
| `src/apps/workspace/billing/{PlanSelector,PlanChangeModal}.vue`, `planSelectorLogic.ts` | price ids; currency blocking | M | offer identity; capability-driven UI |
| `src/apps/workspace/billing/InvoiceList.vue` | DTO fields; document URLs | N | keep; normalize server-side |
| `src/apps/workspace/billing/{CurrencyMigrationModal,PendingMigrationBanner}.vue` | migration flow | R | Stripe cohort only |
| `BillingOverview.vue`, `CancelSubscriptionModal.vue`, `FederationNotification.vue`, `routes/billing.ts`, `PlanCard.vue`, `Pricing.vue`, `public.routes.ts`, `usePostAuthRedirect.ts`, entitlement composables/stores, upgrade prompts, `OrganizationSettings.vue` | application responses; `billing_enabled` gates | N | keep |
| `src/schemas/contracts/bootstrap.ts`, `bootstrapStore.ts`, `api/account/{stripe-types,responses/account}.ts`, `package.json` `stripe` | vestigial types | R | delete (R7) |
| `src/schemas/api/internal/responses/{colonel-billing,colonel,colonel-organizations,registry}.ts`; `src/apps/admin/**` billing views/stores; `PlanPreviewModal.vue` | Stripe-named schemas; `source` enums | R | extend with provider column; truthful labels on Stripe-only sections |
| `src/schemas/contracts/config/billing.ts`, `shapes/config/billing.ts`, `config/config.ts`, `config/index.ts` | catalog contract with Stripe metadata schema, `prod_` regex, `getStripePlans` | N | keep for Stripe provisioning; add provider_refs at R1b |
| `config/section/limits.ts` L62-63 | `stripe_webhook` key | S | rename |
| `config/section/jobs.ts`, `logging.ts` | job flags; logger | R | remove two job flags at R1e |
| `etc/examples/billing.example.yaml` | Stripe keys, tax, pmc, checkout_host, metadata schema, price rows with `price_id` | M | providers block; provider_refs; enrollment default |
| `etc/defaults/config.defaults.yaml` | job flags; comments | R | remove two job flags at R1e |
| `Gemfile` L190-193 | pin rationale | N | keep |
| `bin/stripe-dev-webhook`, `package.json` scripts, `scripts/env-reference-ignore.txt` | Stripe CLI/test env | N | keep |
| `e2e/full-billing/*.spec.ts` | Stripe redirect and test-mode expectations | R | per-provider expectations (R9) |
| tests, cassettes, locale content, archives | Stripe-shaped fixtures; copy | N | keep; S8 for copy |

### 11.5 Stripe API resources by disposition

| Resource | Where | Disposition |
|---|---|---|
| Checkout::Session create/retrieve | `plans.rb` L219, `billing.rb` L191, `create_checkout_link.rb` L311, `currency_migration_service.rb` L335; `logic/welcome.rb` L48 | port |
| Checkout::Session list/expire | `currency_migration_service.rb` L420-428 | Stripe-only |
| BillingPortal::Session | `plans.rb` L354; `core/welcome.rb` L193 | Stripe-only |
| Subscription retrieve / update(cancel_at_period_end) | `billing.rb`, `subscription_guard.rb`, `checkout_completed.rb`, `with_organization_billing.rb`, `reconcile.rb`, colonel, backfill, CLI | port |
| Subscription update(items) / cancel / list | `billing.rb` L661; `currency_migration_service.rb`; `with_organization_billing.rb` L538; CLI | change_plan rebuilt per provider; rest Stripe-only |
| Invoice list | `billing.rb` L302; `get_user_details.rb` L379; CLI | port |
| Invoice create_preview / void | `billing.rb` L502; `currency_migration_service.rb` L497/L475 | per V4; void Stripe-only |
| InvoiceItem, CreditNote, Charge, Refund | currency migration; CLI | Stripe-only |
| Customer retrieve/update | federation, checkout_completed, update_organization, backfills, CLI | email update via adapter; metadata carrier retired |
| Customer create/list/delete | CLI; `with_organization_billing.rb` L505 | Stripe-only |
| Product, Price | catalog pipeline (delete at R1e); `push.rb` and CLI (keep) | split |
| Coupon, PromotionCode, PaymentMethod, Sigma, Account, Event.list | CLI | keep under stripe namespace |
| Webhook.construct_event; Event.construct_from | verifier; worker; record | Stripe verifier |
| WebhookEndpoint | never touched | n/a |

### 11.6 Webhook event types handled

| Event | Handler | Disposition |
|---|---|---|
| checkout.session.completed | `CheckoutCompleted` | internal `checkout.completed`; intent correlation; binding policy (H3) |
| customer.subscription.created | `SubscriptionCreated` | federation only; provenance-aware |
| customer.subscription.updated | `SubscriptionUpdated` | internal `subscription.updated` |
| customer.subscription.deleted | `SubscriptionDeleted` | internal `subscription.ended`; remove only the benefit this agreement supplied (H2) |
| customer.subscription.paused / resumed | `SubscriptionPaused` / `SubscriptionResumed` | Stripe-only |
| customer.subscription.trial_will_end | `TrialWillEnd` | port trigger (V3) |
| customer.updated | `CustomerUpdated` | Stripe cohort only (R4) |
| product.*, price.*, plan.* | `CatalogUpdated` | delete at R1e |

### 11.7 Organization billing fields

| Field | Semantics | Writers | Readers | Stripe-shaped |
|---|---|---|---|---|
| `stripe_customer_id` (unique) | owning `cus_`; presence = owner and federation ineligibility | `ApplySubscriptionToOrg`, `checkout_completed`, `subscription_federation`, `EnsureDefaultWorkspace`, v1 migration | `stripe_customer`, `find_federated_by_email_hash`, `subscription_owner?`, resolver, purge, doctor, backfills | yes |
| `stripe_subscription_id` (unique) | active `sub_` | `ApplySubscriptionToOrg`, `checkout_completed`, migration | `stripe_subscription`, `Org::Reconcile` mode, rosters, doctor, backfill | yes |
| `planid` | plan tier id; default `free_v1` | `ApplySubscriptionToOrg`, probono grant, pending federation, `Org::SetPlan`, chore, `EnsureDefaultWorkspace` | entitlements chain, `limit_for`, `paid?`, `Logic::Base`, safe_dump, `Org::Delete`, rosters | no |
| `billing_email` (unique) | billing contact; synced from Stripe inbound | `customer_updated`, `sync_billing_email`, `UpdateOrganization` | `compute_email_hash!`, safe_dump, rosters | direction-dependent |
| `subscription_status` | Stripe status string | `ApplySubscriptionToOrg`, `subscription_paused`, backfill, `EnsureDefaultWorkspace` | all predicates, safe_dump, `Org::Delete`, rosters | yes |
| `subscription_period_end` | epoch | `ApplySubscriptionToOrg`, backfill, `EnsureDefaultWorkspace` | reconcile snapshot, rosters | yes (item-level) |
| `stripe_checkout_email` (unique) | checkout email | v1 migration only | `get_stripe_customer_by_email`, doctor | yes; migration-only |
| `email_hash` (multi), `email_hash_synced_at` | federation join key | `compute_email_hash!` | federation lookup, backfills | mirrored into Stripe metadata |
| `subscription_federated_at`, `federation_notification_dismissed_at` | benefit marker; UX | federation handlers, `EnsureDefaultWorkspace`, controller | predicates | no (lacks provenance: M6) |
| `complimentary` | mirror of subscription metadata | `ApplySubscriptionToOrg`, probono grant | `complimentary?` | metadata-derived |
| `pending_currency_migration`, `migration_target_price_id`, `migration_effective_after` | Stripe currency migration | `CurrencyMigrationService` | `billing.rb` | yes |
| `entitlements_plan`, `limits_plan`, `entitlements_grants`, `entitlements_revokes`, `materialized_entitlements`, `materialized_entitlements_at` | materialized storage | materialization writers, overrides | `entitlements`, `limit_for`, `can?` | no |
| Customer: `planid`, `pending_plan_intent`, `verified_by`, deprecated `stripe_*` | legacy plan; signup intent; provenance; v1 copies | auth ops, checkout, migration | probono grant, `subscription_status` endpoint, `payment_verified?`, core portal, purge | mixed |

## 12. Sources

- Working tree of `onetimesecret` at `2c532a271d4c57bedd39c76172f33140046e3703`
- Audit A (this session) and Audit B (`stripe-surface-audit-astra.md`, 2026-09-24)
- `docs/specs/billing-decoupling/billing-payer-decoupling.md`; `docs/specs/formlize-control-plane/formalize-control-plane.md`; `docs/architecture/decoupled-billing.md` ("Status: Proposed design reference"); `docs/adr/adr-041-colonel-impersonation-session-overlay.md`
- Attached brief "Airwallex as a Stripe replacement"
- Airwallex documentation: Billing subscriptions create/update; Billing invoices (preview); Airwallex Tax overview; Merchant of Record overview; Developer tools: listen for webhook events
