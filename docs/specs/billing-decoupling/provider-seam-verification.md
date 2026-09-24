---
labels: billing, stripe, airwallex, verification, scientist
related: "stripe-surface-audit.md; billing-payer-decoupling.md; docs/specs/entitlements-and-capabilities/scientist-verification-plan.md"
status: proposal / companion
code_snapshot: 2c532a271d4c57bedd39c76172f33140046e3703
---

# Proving the Provider Seam Before Airwallex Exists (Scientist companion)

> Companion to `stripe-surface-audit.md` in this directory (the "audit",
> merged 2026-09-24), which plans adding Airwallex for new billing relationships while
> the Stripe cohort stays on Stripe. The audit's stages 2 through 5 move
> Stripe behaviour behind a provider-neutral seam while every paying customer
> is still on Stripe. This document says how each of those stages proves the
> seam is behaviour-preserving, by running the new path beside the old one on
> production reads with the `scientist` gem. The harness, registry, triage
> protocol and agent rules are defined once in
> `docs/specs/entitlements-and-capabilities/scientist-verification-plan.md`
> §1 and are not repeated here.

## 0. Where the tool applies

Scientist compares two implementations of the same function on the same
input and needs a side-effect-free candidate. Against the audit's stage plan
that sorts cleanly:

| Audit stage | Fit | Why |
|---|---|---|
| 1 Catalog inventory (R1a) | Coverage counter | Not an experiment; see §1.1 |
| 2 Local catalog authority (R1b–R1e) | **Strong** | Price → plan resolution is a pure lookup with an existing control |
| 3 Binding, snapshot, envelope (M1, M4, M5, S2) | **Strong** | Deriving subscription facts from a Stripe object is pure once separated from the write, which the audit already requires |
| 4 Federation, provenance, purge (M6, M8) | Good | Eligibility and ownership predicates are pure reads |
| 5 Checkout intent, DTOs, config (M3, M7, M9) | Partial | Target resolution is pure; checkout creation is not |
| 6 Airwallex adapter | **None** | No control exists; different provider, different cohort |
| 7 Rollout and reconciliation | None | Covered by section 9 acceptance cases and reconcile tooling |

The absence in stage 6 matters as much as the presence in 2 through 4. An
experiment programme that is green through stage 5 says nothing about the
adapter. The adapter's proof is the shared example group (R9), sandbox runs
(V8) and the verification cases in audit §9.

Every candidate below reads objects the control already fetched or Redis
state already loaded. **No candidate calls Stripe.** A candidate that would
need a provider read is restructured until it does not, or it is not an
experiment.

## 1. Stage 2: catalog inversion (R1)

### 1.1 R1a is a coverage counter, not an experiment

R1a's deliverable is an inventory of every effective Stripe price-to-plan
binding, including retired prices still referenced by live subscriptions. The
audit warns not to assume YAML already holds every production value. A
counter in `Billing::Plan.find_by_stripe_price_id` and
`Billing::PlanValidator.resolve_plan_id` recording every distinct `price_id` resolved
in production, with its resolved `planid` and `catalog_synced_at` age,
produces that inventory from traffic. The set of observed price ids is the
population the stage 2 experiment must cover before R1d.

### 1.2 `billing.stage2.plan_resolution`

**Purpose.** Prove the local versioned catalog resolves every Stripe price the
Stripe projection resolves, to the same grants, without a live Stripe read.
This is also the continuous form of the R1a effective-data comparison, and
the acceptance test for H1 (a Stripe prune cannot deactivate a plan the local
catalog owns).

**Site.** The plan read inside `ApplySubscriptionToOrg` (where it reads
`.items.data.first.price.id` and resolves a `Billing::Plan`), and
`EntitlementMaterializeJob`
(`lib/onetime/jobs/scheduled/maintenance/entitlement_materialize_job.rb`)
where it resolves the org's plan.

```ruby
e = Onetime::Experiment.new('billing.stage2.plan_resolution')
e.context(price_id: price_id, org_extid: org.extid,
          projection_age_s: Familia.now.to_i - Billing::Plan.catalog_last_synced_at.to_i,   # existing accessor
          catalog_generation: Billing::Catalog.active_generation)                          # R1b deliverable
e.use { Billing::Plan.find_by_stripe_price_id(price_id) }               # control: Redis projection of Stripe
e.try { Billing::Catalog.resolve(provider: :stripe, ref: price_id) }    # candidate: local generation
e.compare { |a, b| grant_shape(a) == grant_shape(b) }                   # planid, entitlements, limits, interval, currency, active
e.clean { |plan| grant_shape(plan) }
```

`grant_shape` is the comparison surface: `planid`, sorted entitlements,
limits hash, interval, currency, `active`. Not object identity, not Stripe
product ids, not display text (display text differences are `both-acceptable`
by definition and go in `ignore` with a citation).

**Reading the output.**

| Pattern | Label | Meaning |
|---|---|---|
| Control resolves, candidate `nil` | `candidate-wrong` or R1a gap | A live price the local catalog does not bind; add the binding, it is exactly the retired-offer case the audit calls out |
| Both resolve, grants differ, `projection_age_s` large | `control-wrong` | Stale projection served silently (audit 0.3); the local catalog is right; fixture it |
| Both resolve, grants differ, projection fresh | stop | Real drift between YAML and Stripe metadata; resolve in R1a before R1d |
| Control `active: false`, candidate `active: true` | check H1 | The pruner deactivated a plan the local catalog owns; expected after R1e, a defect before |

**Exit criterion for R1d.** Zero unexplained mismatches across the full
observed price-id population from §1.1, and every price id in that population
has a local binding. Remove at R1e.

## 2. Stage 3: binding, snapshot and envelope (M1, M4, M5, S2)

The audit's M4 requirement, "translate provider responses into application
subscription facts before writing organization state", is the precondition
for every experiment in this section. Today `Organization#update_from_stripe_subscription`
reads Stripe object fields and writes in one method. Splitting derivation from
write is a refactor the experiments need and the audit already wants; do it
first, with the derivation as a pure function of the Stripe object.

### 2.1 `billing.stage3.subscription_snapshot`

**Purpose.** Prove `Providers::Stripe#fetch_subscription` (or its pure
translator over an already-fetched `Stripe::Subscription`) derives the same
application facts the current code derives.

**Site.** Every place a `Stripe::Subscription` object is turned into
organization state: `ApplySubscriptionToOrg`, `update_from_stripe_subscription`,
`checkout_completed.rb`, `org/reconcile.rb` (Stripe sync mode) and
`compute_sync_status` in `apps/web/billing/lib/billing_service.rb`.

```ruby
e.use { LegacyDerivation.facts_from(stripe_sub) }                 # control: current field reads, extracted into a pure method
e.try { Billing::Providers::Stripe::Translator.snapshot(stripe_sub) } # candidate: SubscriptionSnapshot
e.compare { |a, b| a.to_h == b.to_h }
```

Compared fields: internal status enum (S2), raw provider status, `period_end`
(epoch integer, units normalised), `plan_id`, `complimentary`, customer ref,
subscription ref, `cancel_at_period_end`. Money and timestamps are normalised
at the boundary per audit R2; the comparison is on the normalised form, so a
mismatch in units is a candidate defect, not an ignore.

**Reading the output.** The S2 mapping decision (`UNPAID` during dunning to
`past_due` or `unpaid`) is Airwallex-only and does not surface here. What does
surface: any Stripe status the current code handles by accident (an
`incomplete` subscription reaching `active_subscription?` through a string
comparison the enum rejects). Those are `control-wrong` and each becomes a
fixture in the shared example group (R9).

**Exit criterion.** Zero unexplained mismatches across every Stripe status
value observed in production, plus the full `VALID_SUBSCRIPTION_STATUSES` set
exercised through the billing VCR cassettes (226 under `apps/web/billing`) in tryouts with `raise_on_mismatches`.
Remove when the legacy derivation is deleted (stage 5).

### 2.2 `billing.stage3.status_predicates`

**Purpose.** The org predicates `active_subscription?`, `past_due?`,
`canceled?`, `billing_live?`, `paid?` and `subscription_owner?` are the
highest-traffic billing reads in the system. Prove the enum-derived versions
return the same answers.

**Site.** Inside each predicate, for the duration of stage 3.

```ruby
e.use { LIVE_SUBSCRIPTION_STATUSES.include?(subscription_status.to_s) }   # control: string set, as billing_live? today
e.try { Billing::Status.from_provider(:stripe, subscription_status).live? } # candidate: enum
```

This is the one experiment with meaningful volume. It is also the cheapest
candidate in this document (a hash lookup). Expect parity within a day; the
point is the tail, orgs carrying a status string the enum mapping did not
anticipate. Remove at stage 5.

### 2.3 `billing.stage3.event_translation`

**Purpose.** Prove the neutral inbound envelope (`verify_webhook` →
`InboundEvent`, `translate_event` → internal event name plus snapshot)
classifies every Stripe event the way `ProcessWebhookEvent`'s dispatch on
Stripe type strings does today.

**Site.** `ProcessWebhookEvent`, before dispatch. The control is the handler
class the current dispatch selects; the candidate is the internal event name
the translator yields, mapped through a fixed table to the handler it would
select. Comparison is on the handler selection and the derived snapshot, not
on what the handler then writes.

```ruby
e.context(event_type: event.type, event_id: event.id, account: 'stripe:live')
e.use { LegacyDispatch.handler_for(event) }
e.try { Billing::Providers::Stripe::Translator.translate(envelope).handler }
```

**Two run modes.** Live delivery is low volume (tens of events a day). The
`StripeWebhookEvent` records (`default_expiration 5.days`, `INDEX_MAX_ENTRIES = 10_000`) and the 226 billing VCR
cassettes give the same experiment a full replay population offline. Run the
offline replay in tryouts with `raise_on_mismatches` as part of the stage 3
PR; leave the live experiment on through stage 5 to catch event types the
replay window did not contain.

**Event identity (M5).** Not an experiment. The requirement that an Airwallex
event id and a Stripe event id cannot collide is a schema property of the
provider/account-qualified key; assert it in a tryout with two synthetic
events sharing a raw id.

## 3. Stage 4: federation, provenance and shared maintenance (M6, M8)

### 3.1 `billing.stage4.federation_eligibility`

**Purpose.** `find_federated_by_email_hash` selects orgs where
`stripe_customer_id` is empty. The provider-aware replacement selects orgs
with no billing binding of any provider and consults benefit provenance. With
only Stripe in production the two must select the same set; a difference is a
defect in the new predicate, not a coexistence case.

```ruby
e.use { Organization.find_federated_by_email_hash(hash).map(&:extid).sort }
e.try { Organization.federation_candidates(identity: hash).map(&:extid).sort }
```

Low volume (runs on federation events). Pair it with the offline replay
approach from §2.3 over the pending-federation records and the backfilled
email-hash index to get population coverage. H2 (a Stripe event cannot strip
an Airwallex benefit) has no control until Airwallex exists; it is asserted
in the shared example group with a synthetic Airwallex provenance record, not
measured here.

### 3.2 `billing.stage4.billing_state_predicates`

**Purpose.** M8 lists the shared maintenance paths that decide "does this org
have billing state": `purge_preflight.rb#billing_state?`, `org/delete.rb`
guard, `workspace_collision.rb` `BILLING_FIELDS`, `org doctor`
`UNIQUE_INDEXES`. Each currently checks Stripe-shaped fields. Wrap each with
the binding-aware replacement as candidate. These run on deletion, purge and
collision checks; volume is low but the cost of a wrong answer (a purge that
misses a billing relationship) is high, so the experiment stays on until
stage 7 and the offline replay runs over all organizations in the
`orgs_validate` CLI path.

## 4. Stage 5: checkout intent and management (M3, M7)

### 4.1 `billing.stage5.checkout_target`

**Purpose.** `CheckoutTargetResolver` resolves a checkout to an organization
via orgid, then `find_by_stripe_customer_id` requiring the `cus_` prefix, then
the owned default org, with a unique-index claim electing one creator. The
generalised resolver resolves via the local intent record (M3) and the
provider binding. The resolution is pure up to the claim; compare the
resolved org extid before the claim is attempted.

```ruby
e.use { LegacyResolver.resolve(session_metadata).extid }
e.try { Billing::CheckoutTarget.resolve(intent).extid }
```

Runs on checkout completion, so volume follows new-subscription rate. Replay
over the `checkout.session.completed` events in the webhook record window
covers the recent population.

### 4.2 Not experiments

- **Checkout creation** (`create_checkout`): creates a Stripe session. No
  candidate can run beside it. Verify the Stripe adapter's `create_checkout`
  by asserting the session params it *would* send (`build_session_params`
  already exists as a pure builder; test it directly with the shared example
  group).
- **Cancel, reactivate, change plan**: writes. Same treatment.
- **Invoice DTO normalisation** (R3): the `StripeInvoice` DTO is already
  application-shaped; `list_invoices` through the adapter can be compared to
  the current controller's mapping on the same `Stripe::Invoice` list once
  fetched, as a small experiment inside `list_invoices` if wanted. Low value;
  optional.

## 5. Stage 6 and 7: what to use instead

Nothing in this document covers the Airwallex adapter. The proof there is:

1. The shared example group (audit R9): one contract suite over
   `Billing::Providers::Base` that both adapters pass, with the fixtures
   harvested from every `control-wrong` mismatch above (those are the Stripe
   edge cases the Airwallex adapter must also get right).
2. Sandbox verification of V1 through V10 before adapter design, recorded as
   cassettes.
3. Audit §9 acceptance cases run against a staging deployment with both
   providers configured.
4. For rollout (stage 7), the experiments still running from stages 3 and 4
   become the regression guard for the Stripe cohort: a change to shared
   code that alters a Stripe answer shows up as a mismatch against the
   legacy derivation, which is kept, disabled by default, until stage 7
   completes.

## 6. Registry entries

```yaml
billing.stage2.plan_resolution:         { enabled: true,  introduced: r1b,     remove_at: r1e }
billing.stage3.subscription_snapshot:   { enabled: true,  introduced: stage3,  remove_at: stage5 }
billing.stage3.status_predicates:       { enabled: true,  introduced: stage3,  remove_at: stage5 }
billing.stage3.event_translation:       { enabled: true,  introduced: stage3,  remove_at: stage5 }
billing.stage4.federation_eligibility:  { enabled: true,  introduced: stage4,  remove_at: stage7 }
billing.stage4.billing_state_predicates:{ enabled: true,  introduced: stage4,  remove_at: stage7 }
billing.stage5.checkout_target:         { enabled: true,  introduced: stage5,  remove_at: stage7 }
```

Same removal rule as the entitlements companion §1.4: marking a stage
complete without deleting its experiments fails the build.

## 7. Interaction with the #3491 work

Stage 2 here (local catalog authority) and Stage C there (plan features only
in the org set, capabilities from the role table) touch the same object:
`Billing::Plan.entitlements` becomes the org's `plan_entitlements` source.
Sequence so that #3491 Stage C lands before R1b, or R1b's local catalog is
authored without `manage_*` from the start and the H6 cleanup is done in the
same PR. Running `ent.stage_b.capability_gate` before R1a answers whether
production YAML carries `manage_*`, which decides which order is cheaper.

## 8. Verification record

Checked against the working tree at `faeca4483` (2026-09-24). The audit's
`code_snapshot` `2c532a271d` is an ancestor in the same history.

| Claim | Evidence |
|---|---|
| Every file cited in §1 through §4 exists | `apps/web/billing/operations/webhook_handlers/checkout_completed.rb`, `lib/onetime/operations/org/reconcile.rb`, `apps/web/billing/lib/billing_service.rb` (`def compute_sync_status(org)`), `apps/web/auth/operations/customers/purge_preflight.rb` (`BILLING_IDENTIFIER_FIELDS`, `def billing_state?(org)`), `apps/web/auth/operations/workspace_collision.rb` (`BILLING_FIELDS`), `lib/onetime/cli/org/doctor_command.rb` (`UNIQUE_INDEXES`), `apps/web/billing/cli/orgs_validate_command.rb`, `apps/web/billing/lib/checkout_target_resolver.rb`, `apps/web/billing/operations/create_checkout_link.rb` (`def build_session_params(plan, resolution, price_id)`), `apps/web/billing/models/stripe_webhook_event.rb`, `apps/web/billing/operations/process_webhook_event.rb`, `apps/web/billing/operations/apply_subscription_to_org.rb`, `lib/onetime/operations/org/delete.rb`, `lib/onetime/jobs/scheduled/maintenance/entitlement_materialize_job.rb` |
| `LIVE_SUBSCRIPTION_STATUSES = %w[active trialing past_due unpaid]`; `billing_live?` compares `subscription_status.to_s` | `lib/onetime/models/organization/features/with_organization_billing.rb` L54, L216-217; `field :subscription_status` L67 |
| `find_federated_by_email_hash`, `subscription_owner?`, `update_from_stripe_subscription` exist | same file, L123, L304, L412 |
| `Billing::PlanValidator` is a module with `extend self`; `resolve_plan_id(price_id)` delegates to `Billing::Plan.find_by_stripe_price_id` and raises `CatalogMissError` | `apps/web/billing/lib/plan_validator.rb` L74-100 |
| `catalog_synced_at` is a `class_json_string` with `CATALOG_TTL`; plan records themselves do not expire; `catalog_last_synced_at` returns the epoch | `apps/web/billing/models/plan.rb` L95, L439-441 (matches audit reconciliation 0.3) |
| Webhook event retention is 5 days with a 10k index | `stripe_webhook_event.rb` L58, L92 |
| Billing cassette count | 226 `.yml` files under `apps/web/billing` cassette paths (audit says ~230) |
| The two docs' shared harness symbols are consistent | `Onetime::Experiment`, registry and triage protocol defined once in the entitlements companion §1 |

Not verified, because they do not exist yet: `Billing::Catalog`,
`Billing::Status`, `Billing::Providers::Stripe::Translator`,
`SubscriptionSnapshot`, `LegacyDerivation`, `LegacyDispatch`,
`LegacyResolver`, `Billing::CheckoutTarget`, `Organization.federation_candidates`.
These are the audit's R1b, S2, R2 and M3 deliverables, named here as
placeholders for the sake of readable samples.
