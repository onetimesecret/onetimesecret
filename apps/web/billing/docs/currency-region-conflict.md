# Currency/Region Conflict in Multi-Region Subscriptions

_Updated: 2026-02-18_

## How the Problem Arises

OTS operates multiple regional deployments (e.g., `onetimesecret.com` USD, `ca.onetimesecret.com` CAD).
Each region has its own Stripe product catalog — separate Price objects per region — so `identity_plus_v1`
in US maps to a USD price and `identity_plus_v1` in CA maps to a CAD price.

A user with an active subscription in one region can create an account (or log in) in another region
using the same email address. When this happens, the system recognizes the existing subscription and
copies `stripe_customer_id` and `stripe_subscription_id` to the new account. The user now has valid
credentials in both regions but their Stripe Customer object is locked to the currency of their original
subscription.

When that user visits the plans page in the new region and attempts to select a plan, the checkout
attempt fails:

```
Stripe::InvalidRequestError: You cannot combine currencies on a single customer.
This customer has an active subscription... with currency cad.
```

## Stripe's Constraint and Design Expectation

Stripe locks a Customer object to a currency the moment any active resource exists: subscriptions,
subscription schedules, discounts, open quotes, or pending invoice items. This is enforced at the
API level with no structured error code — only a generic `InvalidRequestError` with a human-readable
message. The absence of a machine-readable code is intentional: Stripe considers this a flow design
problem, not a recoverable runtime error.

Stripe's expected approaches:

1. **Multi-currency Prices** — a single Price with `currency_options` for each supported currency.
   No currency conflict is possible. Impractical here because regional plans have independent pricing,
   promotional history, and grandfathered rates.

2. **Cancel-and-recreate** — cancel the existing subscription, then create a new one in the target
   currency. This is the conventional migration path but requires managing the billing gap, proration,
   and customer communication. It is the right path for users who deliberately want to switch regions.

## Chosen Approach: Disable Cross-Region Plan Selection

Because every paid plan includes unlimited custom domains, there is no functional reason for a user
to switch from a USD plan to a CAD plan (or vice versa). The plans are structurally equivalent across
regions. Cross-region plan selection provides no user value and creates the currency conflict.

**Resolution:** when the region (or currency) of a displayed plan does not match the currency of the
user's active subscription, disable the plan selection UI rather than allowing the checkout attempt
to proceed. Each product carries a `region` metadata field; the user's subscription currency is
available from `subscriptionStatus.current_currency` (already fetched on page load).

This eliminates the error path entirely for the common case. The cancel-and-recreate migration path
remains available for users who genuinely need to move their subscription to a different region;
that is a deliberate account management action, not a routine plan upgrade.

## What Remains of the Currency Conflict Infrastructure

The `Billing::CurrencyMigrationService` and the 409 `currency_conflict` response path remain valid
for the explicit migration case (user intentionally switching regions). The `CurrencyMigrationModal`
is appropriate there. However, `create_checkout_session` should not be the discovery point for
routine cross-region accidental clicks — the UI should prevent those before a Stripe API call is made.

## Summary

| Scenario | Correct Handling |
|---|---|
| User on same-region plan page, upgrading/downgrading | Normal checkout, no currency issue |
| User on different-region plan page, clicking a plan | Disable selection; show "manage your subscription in your original region" |
| User explicitly requesting region migration | `CurrencyMigrationModal` + cancel-and-recreate flow |
