# Functional Spec — Plan Grants

Status: Draft · Updated: 2026-06-19 · Scope: `apps/web/billing`

## Purpose

Mint a **grant** of plan entitlement to an account, optionally billed to a
separate **billing party**, redeemed by the recipient via a single-use,
email-locked **claim link** — without routing the recipient through card
checkout.

Reseller orders are one use. The same mechanism covers pro-bono / non-profit
grants, enterprise sales-assisted deals, partner/gift grants, and internal
accounts. The differences are attributes of a grant — chiefly whether a billing
party is attached — not separate tools or commands.

The operator interface is a single `bin/ots billing grant create` (over
`Billing::Operations::Grant`) plus read/revoke commands. The recipient-facing
surface is one self-serve claim endpoint; it is the **only** way a grant is
redeemed. This feature does **not** add a catalog plan; it grants the existing
plans.

## Why this is mostly an assembly job

The hard part the original spec named — "granting entitlement that isn't tied to
checkout" — already exists:

- `Billing::Operations::GrantProbonoEntitlements`
  (`apps/web/billing/operations/grant_probono_entitlements.rb`) grants a plan to a
  customer's org with **zero Stripe round-trip**: three local writes —
  `org.planid`, materialize entitlements, `org.complimentary = 'true'`. This is
  the no-billing-party special case of the general grant.
- `Billing::Operations::ApplySubscriptionToOrg.materialize_entitlements_for_org`
  (`apps/web/billing/operations/apply_subscription_to_org.rb`) is the reusable
  entitlement-write both the webhook path and the pro-bono path call.
- Entitlements are read at request time by `require_entitlement!`
  (`lib/onetime/logic/base.rb`) → `auth_membership.can?(entitlement)` against
  materialized sets. That read path is Stripe-agnostic.

We add a Grant record, a self-serve claim, and (for priced catalog plans only)
the one Stripe write the codebase lacks: `Stripe::Subscription.create` for an
invoiced subscription.

## Architecture at a glance

```
bin/ots billing grant {create,list,show,revoke}   apps/web/billing/cli/grant_*_command.rb  (new)
        │
        ▼
Billing::Operations::Grant::*          apps/web/billing/operations/grant/*.rb    (new)
  ├─ Create   validate → persist Grant + claim_token → (if billing party) Stripe sub
  │           fail-fast before any Stripe call; best-effort rollback on partial failure
  ├─ Redeem   invoked ONLY by the claim endpoint: resolve/create recipient org, grant plan
  └─ Revoke   invalidate claim and/or demote grant

Onetime::Grant                         lib/onetime/models/grant.rb               (new Horreum)

GET/POST /billing/grant/claim/:token   recipient claim endpoint → Operations::Grant::Redeem  (new, core)

webhook invoice.paid + customer.subscription.*  →  metadata['grant_id'] → Grant  (new handler)
        apps/web/billing/operations/webhook_handlers/invoice_paid.rb            (auto-registers)
```

The recipient org is matched to its Stripe subscription by
**`subscription.metadata['grant_id']`**, never by email/federation (see
[Rejected: federation routing](#rejected-federation-routing)).

## Data model — `Onetime::Grant`

New Familia v2 Horreum model at `lib/onetime/models/grant.rb`. The single-use
claim follows the `OrganizationMembership` invite-token pattern
(`unique_index :claim_token, :claim_token_lookup`, consume-on-redeem,
restore-on-failure).

The grant stores **references**, not money. List/net amounts and currency are
owned by Stripe + the catalog and read back for display — never free-typed inputs.

| Field | Notes |
|---|---|
| `objid` / `extid` | dual id; `extid` format `gr%<id>s`, user-facing |
| `plan` | catalog planid, e.g. `identity_plus_v1` |
| `interval` | `month` / `year`; selects the catalog Stripe Price. Required only with a billing party |
| `coupon` | optional reusable Stripe coupon id (e.g. `reseller-20`); the only discount input |
| `billing_party_org_id` | objid of an **existing** Organization (the payer). Absent = comp grant |
| `admin_email` | recipient account-admin; the claim is **locked** to this address |
| `org_name` | recipient org name (signup/onboarding hint) |
| `payment_terms` | `Net N` → `days_until_due` on the invoice. Only meaningful when billed |
| `status` | claim lifecycle: `issued → redeemed` / `expired` |
| `billing_status` | Stripe-synced: `none` / `invoiced` / `paid` (none for comp grants) |
| `claim_token` | `SecureRandom.urlsafe_base64(32)`; single-use, email-locked, expiring |
| `stripe_sub_ref` | Stripe subscription id (Stripe-backed grants only) |
| `created_at` / `redeemed_at` / `expires_at` | claim expiry default 30 days (lazy-checked at redeem) |

The Grant is the source of truth for who (if anyone) pays, who the recipient is,
and where both the claim and the billing sit in their lifecycles.

### Single-use claim

`claim_token` is generated on create, indexed via `unique_index :claim_token,
:claim_token_lookup`, and consumed on redeem: remove from the lookup, null the
field, set `redeemed_at`, persist in one save; on failure, re-add the token so the
claim stays resolvable (mirrors `OrganizationMembership#accept!`). The Grant **is**
the durable, email-locked, single-use pending claim — there is no separate
pending-subscription record. `expires_at` is checked lazily when the link is used;
there is no background sweep.

## Interfaces

### Operator CLI — `bin/ots billing grant ...`

Auto-discovered from `apps/web/billing/cli/grant_*_command.rb`, registered with
`Onetime::CLI.register 'billing grant <verb>', ...` (Dry::CLI).

| Command | Operation |
|---|---|
| `grant create` | `Grant::Create` — mint grant + claim; if `--billing-party`, also create the Stripe subscription. Prints the claim URL |
| `grant list` / `grant show <extid>` | read; `show` surfaces live `billing_status` |
| `grant revoke <extid>` | `Grant::Revoke` — invalidate the claim and/or demote the grant |

There is **no** `redeem` command (redemption is self-serve only) and **no**
`provision` command (folded into `create`).

`create` is one logical operation, gated and ordered to fail clean:

1. **Validate everything before any external call** — plan in catalog; `interval`
   resolves to a catalog Price when a billing party is given; `--billing-party`
   resolves to an existing org (else **fatal**) that has a Stripe customer;
   `--coupon` exists; `admin_email` well-formed. A validation error fails here,
   before Stripe is touched.
2. **Stripe-backed path** (billing party + priced plan): create the subscription
   with an idempotency key, then persist the grant. Best-effort rollback — if the
   grant save fails, cancel the just-created subscription; if the subscription
   create fails, persist nothing. Not idempotent-retry: a failed run cleans up
   after itself so a re-run (after you fix the cause) starts from a clean slate.
3. **Comp path** (no billing party): persist the grant only. No Stripe.

Examples:

```bash
# Comp grant — pro-bono / non-profit / internal. No billing party ⇒ no Stripe.
bin/ots billing grant create \
  --plan identity_plus_v1 \
  --admin-email admin@charity.example --org-name "Helping Hands"

# Reseller order — payer ≠ recipient, invoiced via Stripe, reusable-coupon discount.
bin/ots billing grant create \
  --plan identity_plus_v1 --interval year \
  --admin-email admin@acme.example --org-name "Acme Inc" \
  --billing-party globex \      # existing org: extid | objid | billing_email. Fatal if absent.
  --coupon reseller-20 \        # reusable catalog coupon, not a per-order %
  --payment-terms "Net 45"
# → grant gr8x…; Stripe sub on globex's customer; claim link printed.
#   status: issued · billing_status: invoiced
```

`grant show gr8x…` later reports `billing_status: paid` once the invoice is paid.
Comp grants are permanent until `grant revoke`; Stripe-backed grants end via the
subscription lifecycle (`customer.subscription.deleted` → `apply_free_tier`).

### `Billing::Operations::Grant` module

New `apps/web/billing/operations/grant/`, one operation per file, `Data.define`
results (matching `Catalog::Push` / `GrantProbonoEntitlements`). `Grant::Redeem`
is the crux and is invoked **only** by the claim endpoint:

```ruby
# apps/web/billing/operations/grant/redeem.rb  (sketch)
def call
  return expired_result   if @grant.expired?
  return redeemed_result  if @grant.redeemed?

  cust = Onetime::Customer.find_by_email(@grant.admin_email) ||
         Onetime::Customer.create!(@grant.admin_email)        # sign in or sign up
  org  = default_or_named_org_for(cust, @grant.org_name)      # provision or upgrade
  org.planid = @grant.plan

  if @grant.stripe_sub_ref.to_s.empty?
    # Comp: idempotency ordering from GrantProbonoEntitlements — materialize
    # BEFORE marking complimentary so a mid-flight failure is retryable.
    ApplySubscriptionToOrg.materialize_entitlements_for_org(org, raise_on_miss: true)
    org.complimentary = 'true'
  else
    # Stripe-backed: owner: false sets status/plan/period on the recipient and
    # SKIPS apply_owner_fields (no stripe_customer_id on the recipient; the
    # billing party owns the Stripe customer). Not complimentary.
    sub = Stripe::Subscription.retrieve(@grant.stripe_sub_ref)
    ApplySubscriptionToOrg.call(org, sub, owner: false, planid_override: @grant.plan)
  end
  org.save
  @grant.redeem!   # consume claim_token, stamp redeemed_at, status → redeemed
end
```

### Recipient claim endpoint

`GET /billing/grant/claim/:token` (confirm) + `POST` (execute). Validates the
token (unused, unexpired, email match), authenticates/creates `admin_email`, calls
`Operations::Grant::Redeem`, then surfaces custom-domain config. This is the sole
redemption path and is therefore part of MVP. If the recipient cannot use the
link, that is a support matter, not a second code path.

## Stripe integration (direct, no agent toolkit)

> The Stripe Agent Toolkit (LLM tool-calling, MCP, token billing) is **not** used.
> A grant-and-invoice flow needs deterministic, idempotent writes, not an LLM in
> the money path. We call the Stripe Ruby SDK via `Billing::StripeClient`.

**Pricing references the catalog; it never mints Products or Prices per order.**
Products/Prices are the catalog (`bin/ots billing catalog push` → `Billing::Plan`).
A grant references an existing catalog Price; discounts reference reusable coupons.

- **Plan + interval → an existing catalog Price.** `--plan --interval` resolves to
  the Price already in Stripe. `list_price` and `currency` come from that Price —
  not CLI inputs. (`currency` is the Price's, already region/`JURISDICTION`-scoped.)
- **Discount → a reusable coupon.** `--coupon <id>` references a coupon, applied as
  `discounts: [{coupon}]` so the invoice shows a discount line. Bounded by the set
  of coupons, not by orders. Model coupons in `billing.yaml` and sync them in
  `catalog push` (see [coupons catalog](#coupons-as-catalog)).
- **Subscription.** `Stripe::Subscription.create(customer: <billing-party org's
  stripe_customer_id>, items: [{price: <catalog price>}], discounts: [{coupon}],
  collection_method: 'send_invoice', days_until_due: <Net N>, automatic_tax:
  {enabled: true}, metadata: {grant_id: grant.extid})`. New code — no
  `Stripe::Subscription.create` exists today.

### Auto-provision scope — priced catalog plans only

Auto-provisioning is bounded to catalog plans that **have a Stripe Price**:
`identity_plus_v1` and `team_plus_v1`. `free_v1` and the legacy `identity` plan
carry `prices: []` and are grant-only (comp).

**Dedicated and Global Elite are out of scope for Stripe automation.** They are not
in the catalog and their subscriptions are set up by hand in the Stripe Dashboard.
This tool does not create or sync their subscriptions. (If you want the tool to
*grant their entitlement* + issue a claim link, the plan must be cataloged with
`prices: []`; its billing stays manual — see [open decisions](#open-decisions).)

`grant create` rejects `--billing-party` for a plan that has no priced interval,
pointing the operator at the Dashboard.

### Status sync (webhooks)

New auto-registering handler
`apps/web/billing/operations/webhook_handlers/invoice_paid.rb` (`InvoicePaid <
BaseHandler`, `handles? 'invoice.paid'`); `BaseHandler.inherited` registers it with
zero boilerplate. It and the existing `customer.subscription.*` handlers resolve
the grant by `subscription.metadata['grant_id']`:

```
invoice.paid / customer.subscription.updated
   → metadata['grant_id'] → Grant.find(extid)
   → recipient org from Grant
   → ApplySubscriptionToOrg.call(recipient_org, subscription, owner: false, planid_override: grant.plan)
   → Grant.billing_status: invoiced → paid   (invoice.paid)
```

`customer.subscription.deleted` already routes through
`ApplySubscriptionToOrg.apply_free_tier(org)`, downgrading the recipient at
end-of-term automatically.

### Coupons as catalog

Add a `coupons:` block to `billing.yaml` and sync it in `catalog push`, so
discounts are version-controlled and referenced by id — this is what keeps
`--coupon` bounded rather than minting a coupon per order:

```yaml
coupons:
  reseller-20:
    percent_off: 20
    duration: forever
  nonprofit-100:
    percent_off: 100
    duration: forever
```

Genuinely bespoke negotiated amounts (no catalog-price-×-coupon fit) are the gated
exception, behind an explicit `--custom-amount` flag (one-off `amount_off` coupon
or a single created Price, tagged with `grant_id`) — never the default.

### Security / ops notes

- `create` should use a **restricted API key** (`rk_`) scoped to customers,
  subscriptions, coupons, and invoices write — not the full secret.
- Enable `automatic_tax` and ensure the billing-party org's Stripe customer carries
  a tax location + tax id (GST/HST relevance for CA deployments). The original
  spec's "tax id on the payer" lands here.
- API version is pinned at `2025-12-15.clover`; latest is `2026-05-27.dahlia`
  (separate upgrade decision, not a blocker).

### Rejected: federation routing

The `SubscriptionFederation` mixin routes a subscription's benefits to a non-owner
org matched by `email_hash`. Wrong here:

- `email_hash` is read from the Stripe **Customer** (one hash per customer). A
  billing party holds **many** grants for different recipients (bulk case), so a
  single payer customer cannot encode which recipient a subscription is for.
- It inverts federation's anti-email-swap model (which assumes customer == owner).

Route by `grant_id` instead — it scales 1-payer→N-recipients, reuses the Grant
lookup status-sync already needs, and lets us drop `PendingFederatedSubscription`
entirely (the Grant + `claim_token` is the pending claim).

## Status lifecycle

```
claim:    issued ──redeem──▶ redeemed
                 └─expiry──▶ expired        (lazy check at redeem; no sweep)

billing:  none                              (comp grants)
          invoiced ──invoice.paid──▶ paid   (Stripe-backed; synced via grant_id)
```

The claim track and the billing track are independent. A reseller grant is
`issued` + `invoiced` at creation; redemption flips the claim track; the webhook
flips the billing track.

## MVP (absolute minimum)

1. `Onetime::Grant` model + single-use `claim_token`.
2. `bin/ots billing grant create` — mints grant; comp path (no billing party) and
   Stripe-backed path (priced catalog plan + existing billing-party org) in one
   command, with fail-fast validation and best-effort rollback.
3. Recipient claim endpoint `/billing/grant/claim/:token` — the sole redemption
   path; provisions/upgrades the named account and grants the entitlement with no
   card charge.
4. `grant show` / `grant revoke`.
5. `invoice.paid` + `customer.subscription.*` sync keyed by `grant_id`.

Out of MVP, by decision: dedicated/elite automation (manual Dashboard), PDF,
renewal, bespoke `--custom-amount`, multi-seat tooling.

## Upgrades, in priority order

1. **Coupons-as-catalog** — `coupons:` in `billing.yaml`, synced by `catalog push`;
   until then `--coupon` references coupons created by hand in the Dashboard.
2. **Claim hardening** — explicit revoke (MVP), resend with token rotation.
3. **Order confirmation PDF** for a billing party's PO.
4. **Renewal** — reissued claim or repriced-term renewal with notice.
5. **Self-serve request URL (portal-lite)** — partner initiates, operator approves,
   claim issues. Only at volume.
6. **Multi-seat / bulk grants** — one billing party, N recipient orgs; each its own
   Grant and `grant_id` (this is why recipient routing is per-grant, not per-payer).
7. **Global Elite variant** — grant record triggers the onboarding questionnaire
   instead of a claim link (no self-serve tenant to provision); billing manual.

## File manifest

New:
- `lib/onetime/models/grant.rb`
- `apps/web/billing/operations/grant/{create,redeem,revoke}.rb`
- `apps/web/billing/cli/grant_{create,list,show,revoke}_command.rb`
- `apps/web/billing/operations/webhook_handlers/invoice_paid.rb`
- claim web route + view under `apps/web/billing/`

Reuse (no change expected):
- `apps/web/billing/operations/apply_subscription_to_org.rb` — `.materialize_entitlements_for_org`, `.call(owner: false)`, `.apply_free_tier`
- `apps/web/billing/operations/grant_probono_entitlements.rb` — pattern + idempotency ordering
- `apps/web/billing/lib/stripe_client.rb` — `StripeClient` (idempotency + retry)
- `lib/onetime/models/customer.rb` — `create!`, `find_by_email`, `normalize_email`
- `apps/web/billing/operations/webhook_handlers/base_handler.rb` — auto-registration

Possibly extended:
- `apps/web/billing/operations/catalog/*` + `etc/billing.yaml` — `coupons:` sync

## Open decisions

- **Dedicated / Global Elite.** Catalog them with `prices: []` so the tool can
  grant their entitlement + issue a claim link (billing manual in Dashboard), or
  leave them entirely outside this tool? Default lean: catalog with `prices: []`.
- **Recipient org selection on redeem.** New customers: create org from `org_name`.
  Existing customers with multiple orgs: reuse `GrantProbonoEntitlements
  .default_org_for`, or require the operator to name the org at `create`.
- **Billing-party customer bootstrap.** If the resolved billing-party org has no
  `stripe_customer_id`, does `create` create one (from its billing_email + tax id)
  or fail and require billing setup first? Default lean: fail fast, require setup.
- **Pro-bono consolidation.** Going forward, a new comp account is just `grant
  create` with no `--billing-party`; `GrantProbonoEntitlements` remains the legacy
  `planid='identity'` backfill and retires when none remain.
