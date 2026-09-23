.. A new scriv changelog fragment.

Fixed
-----

- The "Remember me" checkbox on the sign-in form now works. It had no
  effect: every session ended after 24 hours without activity whether it
  was ticked or not. A session signed in with it ticked now lasts 14 days
  from sign-in, and activity does not extend it. Revoking the session from
  the sessions page, "sign out everywhere", password changes and logout
  end it exactly as they end any other session. The sessions page marks
  remembered sessions. Two-factor sign-ins are remembered once the second
  factor is completed. Works in both simple and full authentication modes;
  ``AUTH_REMEMBER_ME_ENABLED=false`` still turns it off.

Changed
-------

- Full authentication mode: the auth database gains a nullable
  ``remember_until`` column on ``account_active_session_keys`` (migration
  011, applied automatically at boot). Installs that set
  ``SKIP_AUTH_MIGRATIONS=true`` must run it before starting this version:
  the per-request session check reads the column and refuses sessions
  while it is missing. Rodauth's separate remember-me cookie is no longer
  enabled; it was set but never read.
