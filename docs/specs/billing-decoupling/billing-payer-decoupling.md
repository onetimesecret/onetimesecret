# Billing Concepts: Decoupling the Paying Party from the Organization

A reference for the design decision behind "one subscription per organization, payer decoupled." Standalone; no prior context required.

## Three parties, not one

Every SaaS billing arrangement involves three distinct parties that small systems tend to collapse into a single record:

1. **The user**: an identity that signs in and does things.
2. **The organization**: the tenant. The container of members, domains, branding, and data that the service is actually delivered to.
3. **The customer**: the party that pays. It holds a payment method, receives invoices, and has a name that matters to accountants, not to the application.

Collapsing these is fine for a product where an individual buys for herself. It breaks the moment money and usage separate, which in B2B is the normal case, not the exception. The design consequence: the customer should be its own object (call it a **billing account**), related to organizations through **agreements** (subscriptions), never merged with them.

```
Billing Account (the payer)
    ├── Agreement #1  ──►  Organization A
    ├── Agreement #2  ──►  Organization B
    └── Agreement #3  ──►  Organization C

Users ──memberships──► Organizations (roles, entitlements)
Billing Account ──agreements──► Organizations (money)
```

One billing account can hold many agreements. Each agreement covers exactly one organization. Users reach organizations through memberships; money reaches organizations through agreements. The two graphs never need to share an edge.

## Why the card holder need not be a member

It looks surprising at first: someone who cannot even sign in to the organization is paying for it. The reasons it must be allowed:

**Procurement is not usage.** In most companies above a certain size, the entity that pays is accounts payable, operating under purchase orders and vendor onboarding rules. The people who use the tool never see the invoice; the people who pay never use the tool. Requiring the payer to be a member forces the creation of a fake user whose only purpose is to hold a credit card. Every such fake user is a security liability and a seat-count distortion.

**Payment relationships outlive memberships.** People leave. If the subscription hangs off a member's identity, offboarding that person breaks billing for everyone else. A billing account persists independently of any individual's employment.

**Least privilege.** The person who updates the card should not need administrative access to the product, and in a secrets-management product specifically, finance staff should not receive access to secret links as a side effect of paying an invoice. Separating the billing account means billing authority and product authority are granted independently.

**Intermediaries are a channel, not an anomaly.** IT contractors pay for organizations belonging to their clients. Resellers exist because procurement teams often refuse card payment and will only pay invoices through their own accounts-payable process; the reseller is the adapter between a card-only vendor and an invoice-only buyer. Parent companies pay for subsidiaries. Sponsors pay for nonprofits. All of these are the same shape: payer outside the tenant.

**The payment processor already thinks this way.** A Stripe Customer is nothing but a payment relationship: name, email, payment methods, tax IDs, invoice history. It has no concept of application membership. Kinde makes the same separation explicit: its `customer_id` and `customer_agreement_id` are deliberately distinct from user and organization IDs ([billing concepts and terms](https://docs.kinde.com/billing/about-billing/billing-concepts-terms/)). Merging payer identity into the tenant means fighting the processor's model instead of mapping onto it.

## What the decoupling enables

**The contractor case.** One billing account, five client organizations, five agreements, one card, optionally one consolidated invoice. Each client's organization is cleanly separate (its own members, domains, SSO, data), while the money flows through one relationship.

**Payer handoff without service interruption.** A client outgrows its contractor and wants to pay directly: re-point the agreement to a new billing account. The organization, its members, and its data are untouched. Without the decoupling this becomes a migration project.

**Invoice-based sales.** A billing account with send-invoice collection serves the procurement teams directly, shrinking the need for intermediaries where you would rather not have them.

**Sane delinquency handling.** Dunning targets the agreement. The organization suspends or degrades according to its agreement's status, and one payer's card failure across five organizations is one problem with one owner, not five support tickets.

## What keeps it honest

The unit of purchase is the organization: one agreement covers one organization, and every organization that wants paid features carries its own agreement. Under that rule, owning many organizations cannot reduce anyone's bill, so multi-org ownership needs no policing. The only remaining abuse is stuffing several distinct companies into a single paid organization to buy once and serve many, and that is bounded by per-organization limits (members, domains, SSO connections) plus a plain prohibited-use clause. Pricing structure does the enforcement; the terms of service only mop up.

Two supporting roles complete the picture. Inside the organization, a `manage_billing` entitlement governs which members may change plans or view invoices. On the billing account, ownership governs the payment method itself. These are frequently the same human. Nothing anywhere requires it.

## Reference points

Kinde's model ([billing model](https://docs.kinde.com/billing/about-billing/kinde-billing-model/), [concepts](https://docs.kinde.com/billing/about-billing/billing-concepts-terms/)) demonstrates the separation in a shipped product: Kinde owns the catalog and agreements, Stripe processes payments, and billing identifiers never collide with tenant identifiers. Kinde's own pricing (MAU plus transaction fee, unlimited organizations) shows the complementary move: choose price metrics that make container count worthless to game.
