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
  ``AUTH_REMEMBER_ME_ENABLED=false`` still turns it off, and also returns
  sessions already remembered to the default lifetime (their 14-day
  deadline still ends them). The deadline is checked when the session is
  read, so a request that straddles it cannot hand the session a new
  rolling lifetime.
- Every signed-in session now ends 30 days after sign-in, however active it
  is, in both authentication modes. Full mode already held its
  active-session rows to this bound; simple mode had no absolute bound at
  all, so a session used at least once a day never expired. Remembered
  sessions end at 14 days as above; the 30 days is the ceiling for every
  other session. The bound is ``site.session.absolute_timeout``
  (``SESSION_ABSOLUTE_TIMEOUT``), in seconds; ``0`` disables it.

Changed
-------

- Full authentication mode: the auth database gains a nullable
  ``remember_until`` column on ``account_active_session_keys`` (migration
  011). The web process applies it at boot, before it serves requests.
  Installs that apply auth migrations by hand must run it before starting
  this version: the per-request session check reads the column and
  refuses sessions while it is missing. Rodauth's separate remember-me cookie is no longer
  enabled; it was set but never read.
