.. A new scriv changelog fragment.

Added
-----

- The v3 API can issue and accept short-lived PASETO v4.public bearer tokens
  (#2427). Set ``PASETO_ENABLED=true`` (``auth.yaml`` ``paseto.enabled``) to
  turn it on; it is off by default and a deployment that leaves it off is
  unchanged. ``POST /api/v3/token`` exchanges a browser session or a Basic
  auth API key for a token that lives ``PASETO_TOKEN_TTL`` seconds (default
  one hour, at most one day) and is presented as
  ``Authorization: Bearer v4.public...`` on the authenticated v3 secret routes
  and ``/api/v3/version``. Tokens cannot mint further tokens, and are refused
  once the account is suspended or its password changes. The signing key is
  derived from ``SECRET``; ``SECRET_PREVIOUS`` entries keep verifying tokens
  signed before a rotation. See ``docs/authentication/api-bearer-tokens.md``.
- Two credential refusal codes, ``api_token_invalid`` and
  ``api_token_expired``, with an RFC 6750 ``WWW-Authenticate: Bearer``
  challenge on the 401 that carries them.

Changed
-------

- ``otto`` floor raised to 2.12 and ``familia`` to 2.13 (the latest
  releases). ``Organization::Features::SecretActivity.configure!`` now applies
  its retention cap through Familia's ``configure_related_field`` and refuses
  a different cap once an organization has materialized.

AI Assistance
-------------

- The PASETO codec, keyring, strategy, token endpoint, tests and
  documentation were written with AI assistance; the codec is pinned to the
  official PASETO v4 test vectors.
