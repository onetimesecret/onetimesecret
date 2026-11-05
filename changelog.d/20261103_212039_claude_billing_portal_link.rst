.. A new scriv changelog fragment.

Added
-----

- Organization owners can open the Stripe Customer Portal from the
  organization billing overview to manage the subscription, payment methods
  and billing history. Which actions the portal offers is set in Stripe's
  portal configuration. The Billing Portal card appears for owners only, and
  only when the organization has a Stripe customer. Leaving the portal
  returns the owner to that organization's billing overview. The browser
  follows the portal URL only when it is served from ``billing.stripe.com``
  or the configured Stripe custom domain. (#4872)

- Operators with a Stripe custom domain must set ``STRIPE_CHECKOUT_HOST``
  (or ``checkout_host`` in ``billing.yaml``) to that host, or the portal URL
  is refused; Checkout has the same requirement. In Stripe live mode, save
  the Customer Portal settings in the Stripe Dashboard first, or opening the
  portal reports an error. The new error message for a failed portal open
  falls back to English in other locales until it is translated. (#4872)
