Changed
-------

- The reveal notice and the expiration warning now share one rule for who
  may receive owner mail, ``Customer#notifiable?``: a non-anonymous account
  with an email address, verified by any means. (!5009)

Fixed
-----

- The expiration warning no longer queues a warning to an empty address.
  A verified owner with a blank email is now treated like one with no
  email: nothing is queued and the secret stays registered for expiration
  warnings. A blank email on an unverified or anonymous account is dropped
  from the warnings, as before. (!5009)

Deprecated
----------

- ``Customer#verified?`` is now ``Customer#account_verified?``, and
  ``Customer#email_verified?`` is now ``Customer#verified_by_email_link?``.
  The old names remain as aliases. A static spec flags new calls to them
  on customer-named receivers in ``lib/`` and ``apps/``. A test stub on an
  old name does not affect code that calls the new one. The stored
  ``verified`` field and the ``verified`` key in API responses are
  unchanged. (!5009)
