Fixed
-----

- The expiration warning no longer queues a warning to a blank email
  address (empty or whitespace only). A verified owner with a blank email
  is treated like one with no email: nothing is queued and the secret stays
  registered for expiration warnings. A blank email on an unverified or
  anonymous account is dropped from the warnings, as before. No code path
  that writes a blank email has been found; this is a guard. (!5009)

Deprecated
----------

- ``Customer#verified?`` is now ``Customer#account_verified?``, and
  ``Customer#email_verified?`` is now ``Customer#verified_by_email_link?``.
  The old names remain as aliases. A static spec flags new calls to them
  on customer-named receivers in ``lib/`` and ``apps/``. A test stub on an
  old name does not affect code that calls the new one. The stored
  ``verified`` field and the ``verified`` key in API responses are
  unchanged. (!5009)
