.. A new scriv changelog fragment.

Changed
-------

- The ``AUTH_ENABLED`` master switch now suppresses tenant SSO on custom
  domains. Previously an SSO-only custom domain (enabled SSO config, no
  sign-in config) kept advertising its Sign In link and completing the SSO
  flow even with ``AUTH_ENABLED=false`` — but with authentication disabled,
  session auth is never registered, so the resulting session was silently
  ignored everywhere. The masthead link, /signin page, domain settings API,
  and the SSO runtime route now all go dark together under a master kill.
  ``AUTH_SIGNIN=false`` intentionally still leaves tenant SSO available: it
  retires only password/email sign-in. (#3672)

- **Operators:** the auth log event ``omniauth_tenant_sso_not_enabled`` now
  carries a ``reason`` field naming the gate that rejected the SSO request —
  one of ``auth_disabled`` (``AUTH_ENABLED`` off), ``no_sso_config``,
  ``sso_config_disabled``, or ``sso_not_permitted`` (the domain's sign-in
  config withholds SSO). This replaces the ``sso_permitted`` field, which was
  briefly renamed to ``sso_available`` during this work; both are gone.
  Anything alerting or querying on ``sso_permitted`` / ``sso_available`` must
  be updated to ``reason``. (#3672)

Fixed
-----

- Saving a domain's homepage configuration no longer hides the branded
  masthead Sign In / Create Account links for the admin's own session until
  the next page reload. The save response echoes deprecated stored fields
  that carry no display authority, and these were overwriting the live
  resolver-computed values in the session bootstrap state. (#3672)
