.. A new scriv changelog fragment.

Added
-----

- New ``ots sessions revoke-all <customer>`` break-glass command that revokes
  every session belonging to one customer (tracked, untracked and Rodauth
  ``account_active_session_keys`` rows) and records a single admin audit
  event. Accepts an email, external ID, Rodauth account ID or object ID;
  ``--reason`` records an operator-supplied reason in the audit trail and
  ``--force`` skips the confirmation prompt. (#4354)

Changed
-------

- Purging a customer (``DELETE /api/colonel/users/:user_id`` and
  ``ots customers purge-one``) now revokes all of that customer's sessions
  first, so a deleted account cannot keep acting through a still-live
  session. Both the revoke and the purge are recorded in the admin audit
  trail. (#4352)

Removed
-------

- The ``ots session clean`` command. Its only delete branch fired on a TTL
  of exactly zero, which Redis never reports, so it always claimed to have
  removed zero expired sessions and looked like it had worked. Use
  ``ots sessions revoke-all`` or ``ots session delete`` instead. (#4354)

- The colonel configuration editor's write path (the save/reset controls and
  the client-side state behind them). The endpoint it posted to never
  existed, so saving silently did nothing. Configuration visibility in the
  colonel console is read-only. (#4355)
