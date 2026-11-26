Changed
-------

- The reveal notice and the expiration warning now share one rule for who
  may receive owner mail, ``Customer#notifiable?``: a non-anonymous account
  with an email address, verified by any means.
- The expiration warning now treats a blank owner email like a missing
  one: no email is queued and the secret stays on the warning timeline.

Deprecated
----------

- ``Customer#verified?`` is now ``Customer#account_verified?``, and
  ``Customer#email_verified?`` is now ``Customer#verified_by_email_link?``.
  The old names remain as aliases. A static spec refuses new calls to them
  in ``lib/`` and ``apps/``. A test stub on an old name does not affect code
  that calls the new one. The stored ``verified`` field and the
  ``verified`` key in API responses are unchanged.
