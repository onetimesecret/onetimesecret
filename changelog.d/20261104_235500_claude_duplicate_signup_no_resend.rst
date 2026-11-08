.. A new scriv changelog fragment.

Security
--------

- In full authentication mode, a sign-up for an address that already has an
  account now gets the same response as a new sign-up, instead of the 400
  "Unable to create account" error, so the response does not show whether the
  address is registered. The duplicate sign-up writes nothing and sends no
  email, whether or not the existing account is verified. The address owner
  can still request a new verification email with Resend.
- The same answer goes to a sign-up for an address that has a customer record
  but no open sign-in account, which 0.26.x refused with a 400. That sign-up
  creates nothing, so the person cannot register until an operator resolves
  the record. The server logs it as ``registration_duplicate_customer_record``
  at error level, with the record's ``external_id``. 0.26.x logged the case
  as ``registration_blocked_redis_conflict``, so update alerts and log
  searches that match the old name. With ``AUTHENTICATION_MODE=full``
  exported, ``bin/ots customers diagnose EXTERNAL_ID`` names the cause.
  ``missing_auth_account`` follows a move from simple to full mode, and
  ``bin/ots customers sync-auth-accounts --run`` creates the missing accounts.
  ``account_closed`` follows a closure from before 0.26.19 that stopped part
  way, and ``bin/ots customers prune-closed-accounts --confirm`` followed by
  ``bin/ots customers finish-closures --confirm`` removes the record.
