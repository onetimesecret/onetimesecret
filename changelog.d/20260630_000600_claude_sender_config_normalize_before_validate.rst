.. A new scriv changelog fragment.

Fixed
-----

- The PUT custom-sender endpoint now normalizes the from-address before
  validating it: a blank ``from_address`` is rewritten to ``noreply@<domain>``
  (for the non-flexible ``custom_mail_sender`` entitlement) instead of being
  rejected with "From address is required". This lets an operator enable the
  sender without hand-typing an address, matching the frontend default. The
  ``flexible_from_domain`` path is unchanged — it still requires an explicit
  address — and the PATCH endpoint already preserved the existing address.
