---
labels: billing, research, airwallex, orb, clerk, workos, payer-decoupling
related: "billing-payer-decoupling.md; stripe-surface-audit.md; provider-seam-verification.md"
status: research note / leads (non-authoritative)
date: 2026-09-30
provenance:
  - Four delegated research passes on 2026-09-30, one per vendor, restricted to each vendor's official docs, pricing and changelog domains.
  - Every vendor domain (clerk.com, workos.com, airwallex.com, withorb.com and docs.withorb.com) is blocked by this session's egress proxy. No page was read directly. Every quotation below is the text of a search-engine excerpt attributed to the named URL. Treat each as a lead to confirm against the live page before citing it as a vendor claim.
  - Nothing here modifies the categorizations in stripe-surface-audit.md. Where an excerpt disagrees with a fact that audit lists as verified, the disagreement is recorded in section 5 and the audit's wording stands.
---

# Frontier billing services as reference points for payer decoupling

`billing-payer-decoupling.md` argues for three parties (user, organization,
billing account) and cites one shipped product, Kinde, as its reference
point. `stripe-surface-audit.md` selects Airwallex as the provider for new
billing relationships. This note adds four newer services to the reference
set and asks the same question of each: **where does the paying party live
relative to the tenant, and can it be someone outside the tenant?**

The four are not alike. Two are identity products that have grown a billing
surface (Clerk) or a billing pointer (WorkOS). One is a payment provider with
a billing layer (Airwallex). One is a billing engine that sits above payment
providers (Orb). Read together they mark out the design space the decoupling
spec sits in.

## 0. Summary against the three-party model

| Question | Clerk Billing | WorkOS | Airwallex Billing | Orb |
|---|---|---|---|---|
| Sells billing at all | Yes (beta) | No; Stripe add-ons only | Yes | Yes |
| Separate customer object distinct from user and org | Payer object, but 1:1 with a user or an org | None; a Stripe customer id is stored on the org | Customer: contact, tax id, default currency, payment sources | Customer: name, email, external id, payment provider link |
| Payer outside the tenant | Not documented; billing is gated by org membership permissions | Not documented | Customer has no notion of application users, so yes by construction | Customer has no notion of application users, so yes by construction |
| One payer, many tenants | Not documented | Not documented | Many subscriptions per customer implied, not stated | Parent/child customer hierarchy with consolidated or split invoicing |
| Re-point an agreement to a new payer | Not documented | n/a | Not possible: subscription customer is immutable | Not documented |
| Who moves the money | Stripe only | Stripe (yours) | Airwallex | Stripe or Adyen as gateway; or an external invoicing provider |
| What the vendor owns | Catalog, plans, features, checkout UI, `has()` checks | Entitlements claim and seat meter, both fed from your Stripe | Catalog, subscriptions, invoices, hosted checkout, tax calculation | Catalog, metering, subscriptions, invoices, credits, hierarchy |
| Entitlement signal to the app | `has({plan})`, `has({feature})` | `entitlements` claim in the access token | Webhooks on subscription state | Webhooks; License resource; credit balance API |
| Vendor's own price | 0.7% per transaction plus Stripe fees | Free to 1M MAU; per-connection for SSO/DSync | Not researched (payments pricing) | Custom, by billings and events; platform fee on upper tiers |

The two columns that answer the spec's question with a plain yes, Airwallex
and Orb, are the two whose customer object knows nothing about application
users. The two that cannot answer it, Clerk and WorkOS, are the two where the
billing relationship hangs off the identity object. That is the spec's
argument restated as a market observation, and it is the main reason to keep
the billing account app-owned rather than delegated to an identity provider.

## 1. Clerk Billing

Clerk is the closest thing to a shipped version of the collapsed model the
decoupling spec argues against: the payer is the user or the organization,
never a third party.

- **Payer is a wrapper over user or org.** The billing webhooks doc
  (https://clerk.com/docs/guides/development/webhooks/billing) describes a
  Subscription Item as "the relationship between the payer (user or
  Organization) and a Plan". The checkout payer object
  (https://clerk.com/docs/nextjs/reference/hooks/use-checkout) carries its
  own `id` plus `userId`, `organizationId`, `organizationName`. So billing
  ids are distinct from identity ids, but each payer maps to exactly one
  user or one org.
- **Billing authority is a membership permission.** Seat purchases require
  the `org:sys_billing:read` and `org:sys_billing:manage` system permissions
  (https://clerk.com/docs/guides/billing/seat-based-plans). The billing tab
  lives inside the organization profile. No path exists for a non-member to
  hold the card.
- **One main subscription per payer.** "There can only be one active
  Subscription Item per payer and Plan" (webhooks doc). Plans are typed per
  payer kind: `getPlanList()` filters by `payerType: 'org'`
  (https://clerk.com/docs/reference/backend/billing/get-plan-list).
- **Stripe only, Clerk owns the catalog.** "Clerk Billing only uses Stripe
  for payment processing." (https://clerk.com/docs/guides/billing/overview).
  Clerk owns plans, features, the checkout UI and the `has()` checks;
  Stripe holds the money.
- **Price.** "just 0.7% per transaction, plus transaction fees which are
  paid directly to Stripe" (overview and https://clerk.com/pricing).
- **Status.** Reference pages still carry the beta banner ("Billing is
  currently in Beta and its APIs are experimental and may undergo breaking
  changes."). No GA changelog entry was found as of 2026-09-30.

What to take from it: the `has({feature})` shape is the entitlement surface
the app's own `manage_billing` entitlement should resemble, and the
per-payer-kind plan typing is a clean way to keep personal and organization
catalogs from mixing. The payer model itself is the counterexample.

## 2. WorkOS

WorkOS does not sell billing. It is worth including because its answer to
"where is the payer" is the same one this codebase gives today: a Stripe
customer id stored on the organization.

- **No billing product.** AuthKit, SSO, Directory Sync, Organizations, RBAC,
  FGA, Audit Logs, Vault and Radar. Two Stripe add-ons stand in:
  - Stripe Entitlements (https://workos.com/docs/authkit/add-ons/stripe):
    "Entitlements are set at the organization level so the only code that's
    required is to set the Stripe customer id on the WorkOS organization".
    WorkOS listens to your Stripe webhooks through Stripe Connect and
    exposes an `entitlements` claim in the access token.
  - Stripe Seat Sync (https://workos.com/changelog/stripe-billing-seat-sync,
    2025-10-31): "automatically sends active organization member counts to
    Stripe as billing meter events" under the event name `workos_seat_count`.
- **Object model.** Organization, User, OrganizationMembership. No customer
  object. Organizations and users carry `external_id` (unique, 64 chars) and
  up to 10 metadata key-value pairs
  (https://workos.com/docs/user-management/metadata/introduction).
- **Payer outside the tenant.** Not documented either way. The docs say to
  set the Stripe customer id on each organization; nothing states whether
  one customer id may appear on several organizations.
- **Price.** Free for up to 1 million monthly active users; SSO and
  Directory Sync at $125 per connection per month with volume tiers; Audit
  Logs from $5 per organization per month (https://workos.com/pricing).
  Organizations themselves carry no charge.
- **Orb.** Appears only as a WorkOS subprocessor ("Usage-tracking and billing
  engine", https://workos.com/legal/subprocessors). No customer-facing
  integration.

What to take from it: WorkOS treats billing as a pointer on the tenant plus
a claim derived from someone else's subscription state. That is exactly the
shape `stripe_customer_id` on the organization has here, and exactly the
shape the decoupling spec wants to move past. Seat Sync's use of Stripe
meter events for member count is a pattern to remember if per-seat pricing
ever returns.

## 3. Airwallex Billing

Airwallex is the planned provider, so its answers matter most. Nothing below
overrides `airwallex_facts_verified` in the audit; section 5 lists the one
discrepancy.

- **Customer is a payment relationship only.** "The customer resource holds
  the necessary information to bill a customer correctly, including contact
  details, payment methods and billing history."
  (https://www.airwallex.com/docs/billing/how-airwallex-billing-works).
  Fields seen on create
  (https://www.airwallex.com/docs/api/billing/billing_customers/create):
  `type` BUSINESS or INDIVIDUAL, business name, first and last name, email,
  address, a single `tax_identification_number`, `default_billing_currency`,
  `default_legal_entity_id`. Payment methods are separate Payment Source
  objects referenced from the subscription. No concept of application users.
- **Subscription customer is immutable.** The subscriptions API guide
  (https://www.airwallex.com/docs/billing/subscriptions/subscriptions-via-api)
  states "you cannot update a subscription's customer, billing entity, or
  billing currency" and suggests duplicating the subscription instead.
- **No hierarchy, no cross-customer consolidation.** No parent/child
  customer or consolidated invoice across customers was found. The only
  consolidation is within one subscription: multi-item, multi-frequency
  items are "combined into one invoice"
  (https://www.airwallex.com/docs/billing/subscriptions/get-started-with-subscription-management).
- **Metadata.** Customer: "up to 50 keys with key names up to 50 characters
  long and values up to 500 characters long"
  (https://www.airwallex.com/docs/billing/billing-components/customers/customers-via-api).
  Subscription metadata is updatable in PENDING, IN_TRIAL and ACTIVE.
  Billing Checkout metadata exists "to link a cart, order or customer in
  your system to it"
  (https://www.airwallex.com/docs/billing/billing-components/checkout/hosted-billing-checkout);
  whether it is copied onto the created subscription is not documented,
  which matches the audit's open item V2.
- **Collection methods.** AUTO_CHARGE (saved payment method),
  CHARGE_ON_CHECKOUT ("collects payments via digital invoice, and when the
  customer pays the first time, the payment method will be saved"), and
  OUT_OF_BAND ("managing payments outside of Airwallex Billing (for example,
  through a direct bank arrangement)", invoice marked paid manually). Bank
  transfer can be offered at checkout or on the invoice
  (https://www.airwallex.com/docs/payments/payment-methods/global/bank-transfer).
- **Tax.** Calculation only. "Billing does not enforce or monitor filing
  obligations"; "You also need to file returns and remit what you
  collected."
  (https://www.airwallex.com/docs/billing/airwallex-tax/how-automatic-tax-calculation-works).
  Merchant of Record is a separate Payments product in beta for digital
  goods (https://www.airwallex.com/docs/payments/merchant-of-record). Same
  as the audit.
- **Plan change preview.** Not documented beyond the invoice preview the
  audit already describes. Same as the audit.
- **Currency.** Per subscription or invoice; the customer holds only a
  default (https://www.airwallex.com/docs/billing/configure-your-billing-settings).

What to take from it, as proposals for the decoupling design:

1. **The billing account must be app-owned, not an Airwallex customer.**
   Airwallex gives no parent/child customer and no way to move a
   subscription between customers. The "one billing account, five client
   organizations" case in the decoupling spec therefore maps to one
   Airwallex customer holding five subscriptions, with the app's agreement
   table recording which organization each one covers. Airwallex cannot
   express the organization side of the edge at all; only metadata can
   carry it.
2. **Payer handoff is cancel-and-recreate on the provider.** The spec
   describes handoff as "re-point the agreement to a new billing account"
   with the organization untouched. On Airwallex that is a new subscription
   under the new customer and a cancellation of the old one, so the app's
   agreement id must be stable across a change of provider subscription id.
   This is the same requirement the audit's M4 (subscription binding)
   raises for Stripe replacement detection, now with a concrete trigger.
3. **OUT_OF_BAND is the invoice-based sales channel.** The spec's
   "send-invoice collection" for procurement teams has a direct
   counterpart. CHARGE_ON_CHECKOUT is the first-invoice-then-card path.
   Both should be selectable per agreement, not per provider config.
4. **A single tax id field.** Stripe customers hold a list of tax ids;
   Airwallex shows one. A reseller paying for organizations in several
   jurisdictions may need more than one. Worth checking on the live API
   reference before the billing account schema is fixed (V-F3 below).

## 4. Orb

Orb is the only one of the four with a shipped answer to "one payer, many
tenants" and consolidated invoicing. It is not a payment provider and is
priced for sales-led accounts, so it is a reference for the data model, not
a provider candidate. That last sentence is an interpretation.

- **Customer is the billed party, nothing more.** "A Customer is the basis
  for all billing in Orb, and is the entity that has events, subscriptions,
  invoices, and payments associated with it." Orb "generally does not have
  personally identifying information about your customers, other than a
  name and email address." (https://docs.withorb.com/core-concepts).
- **External id is yours and permanent.** `external_customer_id` is "an
  alias to Orb's own generated customer_id", unique per account, and "cannot
  be changed after creation due to its impact on billing cycles"
  (https://docs.withorb.com/events-and-metrics/customer-aliases). The
  recommended value is "a stable ID in your system, such as your customer's
  primary key". That is the billing account id, not the organization id.
- **Customer hierarchy.** "Orb has support for creating hierarchical
  relationships between your customers to power flexible pricing, usage
  aggregation, and invoicing"; set by updating a customer's `hierarchy`
  field with a parent or children. Options: "bill a parent customer for all
  children subscriptions, bill all child subscriptions individually, or bill
  hybrid". Invoice line items carry `usage_customer_ids`; the parent's
  currency governs the invoice
  (https://docs.withorb.com/product-catalog/customer-hierarchy).
- **Money moves elsewhere.** "Orb integrates with payment gateways like
  Adyen and Stripe for payment processing"
  (https://docs.withorb.com/invoicing/payments). Alternatively an external
  invoicing provider (Bill.com, Stripe Invoicing, QuickBooks, NetSuite)
  issues the invoice and "payment will not be collected through Orb"
  (https://docs.withorb.com/integrations-and-exports/introduction).
- **Collection.** `auto_collection` per invoice, inherited from the
  customer; with Stripe, net terms of zero become `charge_automatically`
  and non-zero terms become `send_invoice`
  (https://docs.withorb.com/integrations-and-exports/stripe).
- **Entitlements.** No feature-flag API. A License resource "represents an
  entitlement provisioned on a subscription"
  (https://docs.withorb.com/data-exports/resource-types); otherwise
  webhooks and the credit balance API
  (https://docs.withorb.com/self-serve/product-access).
- **Webhooks.** `X-Orb-Signature` as `v1=<hmac>` over `v1:<timestamp>:<body>`
  with `X-Orb-Timestamp`
  (https://docs.withorb.com/integrations-and-exports/webhooks). A third
  signature scheme beside Stripe's and Airwallex's, which supports the
  audit's call for a provider-aware webhook envelope rather than a shared
  verifier.
- **Price.** "custom pricing based on two key metrics, billings and
  events"; Advanced and Enterprise "also include a platform fee"; no public
  rates (https://www.withorb.com/pricing).

What to take from it: Orb's hierarchy is the closest shipped prior art for
the decoupling spec's billing account with many agreements, and it confirms
two design choices. The external id that the billing engine keeps must be
the payer's id, never the tenant's. And "bill parent or bill children" is a
per-agreement setting, which argues for a collection mode on the agreement
rather than on the billing account.

## 5. Discrepancies and verification items

Items the delegated passes surfaced that conflict with, or extend, facts
already recorded elsewhere. None is resolved here.

| Id | Item | Where it matters | Status |
|---|---|---|---|
| V-F1 | The Airwallex pass reported proration mode names such as `PRORATE_CREDIT_AND_FEE` with per-item override. The audit's verified list has `default_proration_mode PRORATED \| ALL \| NONE`. | Audit stage 5, plan change (V4) | Unverified; the audit's wording stands until the live API reference is read |
| V-F2 | Whether one Airwallex customer may hold many subscriptions is implied by customer defaults being "pre-filled when creating invoices or subscriptions for this customer" but never stated. | Section 3 proposal 1 | Confirm on the subscriptions API reference |
| V-F3 | Airwallex customer shows one `tax_identification_number`; Stripe holds a list. | Billing account schema | Confirm on the customer API reference |
| V-F4 | Airwallex Billing Checkout metadata passthrough to the created subscription. | Audit V2 | Still open; nothing new found |
| V-F5 | Clerk Billing GA status. Reference pages still say beta on 2026-09-30. | Section 1 only | Re-check changelog before citing Clerk as shipped |
| V-F6 | Whether WorkOS permits the same Stripe customer id on several organizations. | Section 2 only | Not documented; low priority |
| V-F7 | Orb subscription transfer between customers. | Section 4, handoff comparison | Not found; treat as unsupported until shown otherwise |

## 6. Delegated findings ledger

Per AGENTS.md, every delegated finding used here has a stable id and a
disposition. Findings are grouped by pass; "used" means the finding appears
in sections 0 through 4 with its URL.

| Id | Pass | Finding | Disposition |
|---|---|---|---|
| C1 | Clerk | Payer is a wrapper over user or org with its own id | Used, §0 §1 |
| C2 | Clerk | Billing gated by org system permissions; no external payer | Used, §0 §1 |
| C3 | Clerk | Stripe only; Clerk owns catalog and checks | Used, §1 |
| C4 | Clerk | One active Subscription Item per payer and plan; plans typed by payer kind | Used, §1 |
| C5 | Clerk | 0.7% per transaction plus Stripe fees | Used, §0 §1 |
| C6 | Clerk | Beta banner still present | Used, §1; V-F5 |
| C7 | Clerk | Seat plans, custom prices, trials, credits exist | Not used; not relevant to payer model |
| W1 | WorkOS | No billing product; Stripe Entitlements and Seat Sync add-ons | Used, §0 §2 |
| W2 | WorkOS | Stripe customer id set on the organization; entitlements claim in token | Used, §2 |
| W3 | WorkOS | external_id and 10 metadata pairs on org and user | Used, §2 |
| W4 | WorkOS | Pricing: 1M MAU free, per-connection SSO/DSync, Audit Logs per org | Used, §0 §2 |
| W5 | WorkOS | Orb is a WorkOS subprocessor | Used, §2 |
| W6 | WorkOS | No Stripe Sandbox support for the add-on | Not used; operational detail |
| A1 | Airwallex | Customer fields and no user concept | Used, §0 §3 |
| A2 | Airwallex | Subscription customer, entity and currency immutable | Used, §0 §3 proposal 2 |
| A3 | Airwallex | No hierarchy or cross-customer consolidation | Used, §3 proposal 1 |
| A4 | Airwallex | Metadata limits on customer, subscription, checkout | Used, §3; V-F4 |
| A5 | Airwallex | Three collection methods; bank transfer on invoice | Used, §3 proposal 3 |
| A6 | Airwallex | Tax calculation only; MoR separate beta | Used, §3; agrees with audit |
| A7 | Airwallex | Proration mode names differ from audit | Not used in body; V-F1 |
| A8 | Airwallex | Webhook signature scheme | Not repeated; already in audit |
| A9 | Airwallex | Currency per subscription, default on customer | Used, §3 |
| O1 | Orb | Customer is billed party with name and email only | Used, §0 §4 |
| O2 | Orb | external_customer_id permanent, should be your primary key | Used, §4 |
| O3 | Orb | Customer hierarchy with three billing options | Used, §0 §4 |
| O4 | Orb | Payment via Stripe or Adyen gateway, or external invoicing provider | Used, §0 §4 |
| O5 | Orb | auto_collection and net terms mapping | Used, §4 |
| O6 | Orb | License resource; no entitlement API | Used, §0 §4 |
| O7 | Orb | Webhook signature scheme | Used, §4 |
| O8 | Orb | Custom pricing on billings and events | Used, §0 §4 |
| O9 | Orb | Event ingestion, idempotency, metric types | Not used; usage metering out of scope |
| O10 | Orb | Subscription transfer not documented | V-F7 |
