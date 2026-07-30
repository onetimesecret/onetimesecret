.. A new scriv changelog fragment.

Security
--------

- **The anonymous secret TTL ceiling is now read on every deployment.**
  Previously it was derived from the free-tier plan limit, so it applied only
  where billing was enabled — leaving deployments with billing off with no
  anonymous ceiling at all, and an override (``PLAN_TTL_ANONYMOUS``) that was
  silently ignored on exactly those installs. The ceiling is now its own
  configuration value (``site.secret_options.ttl_max_anonymous``, env
  ``TTL_MAX_ANONYMOUS``), defaulting to 7 days, resolved through a single reader
  shared by TTL enforcement and the bootstrap payload that builds the duration
  dropdown. A configured ``ttl_options`` maximum below the ceiling still wins.
  With billing enabled, the free-tier ``secret_lifetime`` limit applies as an
  additional ceiling, which is what preserves the invariant that an anonymous
  caller never receives a longer TTL than an authenticated free-tier user.

Changed
-------

- ``TTL_MAX_ANONYMOUS`` replaces ``PLAN_TTL_ANONYMOUS`` throughout. The old name
  implied a coupling to plan and billing state that no longer exists. It is
  still read as an alias for the anonymous ceiling when the new name is unset,
  but it is no longer read anywhere else — including its second, older job of
  setting the free-tier ``secret_lifetime`` fallback used when plan state is
  unavailable. That fallback now reads ``TTL_MAX_ANONYMOUS`` as well, so on a
  billing-enabled deployment one variable moves both values.

  **Operators on a billing-enabled deployment should rename the variable.** Left
  as-is, ``PLAN_TTL_ANONYMOUS`` still sets the anonymous ceiling via the alias,
  but the free-tier ``secret_lifetime`` fallback reverts to its 14-day default
  (``free_v1`` in ``etc/billing.yaml``). That fallback only applies when plan
  state is unavailable — an empty or uncached ``planid`` — and the anonymous
  ceiling is unaffected either way.

.. note::

   **Self-hosted operators:** the anonymous ceiling defaults to 7 days whether
   or not billing is enabled. Deployments with billing off previously allowed
   anonymous secrets up to the configured ``ttl_options`` maximum (30 days on
   stock config), so this is a behaviour change on upgrade. It is a default,
   not a limit — set ``TTL_MAX_ANONYMOUS=2592000`` to restore 30 days, or any
   value up to 365 days. Authenticated users are unaffected; their limits still
   come from their plan, and the 14-day free-tier gate is unchanged.
