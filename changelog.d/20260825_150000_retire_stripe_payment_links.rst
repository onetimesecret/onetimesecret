.. A new scriv changelog fragment.

Removed
-------

- Stripe Payment Link provisioning has been retired. The ``/welcome`` endpoint
  that handled Payment Link redirects now logs the attempt and redirects to
  the homepage; the webhook handler skips Payment Link subscriptions (they
  never carried the ``customer_extid`` metadata the webhook requires). The
  ``bin/ots billing payment-links`` CLI command has been removed entirely.
  Existing Payment Link subscriptions continue to bill normally in Stripe;
  they simply no longer trigger automatic workspace creation. Customers who
  paid via a legacy Payment Link and were not provisioned should contact
  support. Use the Stripe Dashboard to audit or archive any remaining Payment
  Links.
