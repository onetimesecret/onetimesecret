.. A new scriv changelog fragment.

Fixed
-----

- The global authentication kill switch (``AUTH_ENABLED`` / ``AUTH_SIGNIN`` / ``AUTH_SIGNUP``) is now authoritative over per-domain sign-in and sign-up configuration. The runtime gates ``Core::Controllers::Base#signin_enabled?`` and ``#signup_enabled?`` previously used replace semantics, so an enabled per-domain ``SigninConfig``/``SignupConfig`` could re-enable sign-in or sign-up on a custom domain even while the operator had disabled it globally. Both gates and the ``ConfigSerializer`` display gate now resolve through shared ``SigninConfig.resolve_signin_enabled`` / ``SignupConfig.resolve_signup_enabled`` helpers that AND the per-domain override with the global capability — a domain config may only narrow, never widen, the install-level setting. (#3453)
