Changed
-------

- The reveal notice and the expiration warning now share one rule for who
  may receive owner mail, ``Customer#notifiable?``: a non-anonymous account
  with an email address, verified by any means.

Fixed
-----

- The expiration warning now treats a blank owner email like a missing
  one: no email is queued and the secret stays registered for expiration
  warnings. Before, a verified owner with a blank email had a warning
  queued to an empty address.

Deprecated
----------

- ``Customer#verified?`` is now ``Customer#account_verified?``, and
  ``Customer#email_verified?`` is now ``Customer#verified_by_email_link?``.
  The old names remain as aliases. A static spec flags new calls to them
  on customer-named receivers in ``lib/`` and ``apps/``. A test stub on an
  old name does not affect code that calls the new one. The stored
  ``verified`` field and the ``verified`` key in API responses are
  unchanged.
