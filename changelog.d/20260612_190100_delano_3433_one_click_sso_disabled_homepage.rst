.. A new scriv changelog fragment.

Added
-----

- One-click SSO on the disabled-homepage variants (``minimal`` and ``v1``).
  When SSO is the sole login method and a single provider is configured, the
  homepage shows a direct SSO sign-in button instead of a ``/signin`` link,
  mirroring the activation logic of the auth-method selector (global
  ``restrict_to: sso`` or a custom domain with ``enforce_sso_only``). (#3433)

Changed
-------

- The disabled-homepage ``legacy`` variant is renamed to ``closed`` and is now
  the default. It remains a quiet, no-CTA placeholder; self-hosters who pinned
  ``minimal`` or relied on the ``legacy`` name should update their disabled
  homepage configuration. (#3433)
