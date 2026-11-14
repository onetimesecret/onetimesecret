.. A new scriv changelog fragment.

Security
--------

- Stripe webhooks are no longer verified with a placeholder signing secret.
  Copies of ``etc/billing.yaml`` made from the example file before this
  release fall back to ``nosigningsecret`` when ``STRIPE_WEBHOOK_SIGNING_SECRET``
  is unset, and a forged event signed with that public value was accepted.
  ``POST /billing/webhook`` now refuses to verify with a blank or placeholder
  secret (``nosigningsecret``, ``CHANGEME``) and answers 500, and a deployment
  with a real ``STRIPE_API_KEY`` and no signing secret refuses to boot with a
  message naming the variable. Operators who run billing: set
  ``STRIPE_WEBHOOK_SIGNING_SECRET`` to the endpoint's ``whsec_`` value before
  upgrading. The example file no longer carries the fallback.
