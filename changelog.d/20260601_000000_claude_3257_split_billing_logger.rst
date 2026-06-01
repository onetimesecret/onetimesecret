.. A new scriv changelog fragment.

Changed
-------

- Narrowed ``Billing`` logger scope to payment-only concerns (Stripe checkout, invoices, webhooks). Entitlement operations in ``ApplySubscriptionToOrg`` now log under the ``Ents`` category for cleaner ``DEBUG_ENTS=1`` filtering. (#3257)
