.. A new scriv changelog fragment.

Security
--------

- **Anonymous secrets now expire within 7 days, on every deployment.** The
  ceiling for secrets created without an account is a fixed product limit
  (``ANONYMOUS_MAX_TTL``) rather than a value derived from the free-tier plan
  limit. ``PLAN_TTL_ANONYMOUS`` may only lower it — set to 10, 14 or 30 days it
  now yields 7; set to 5 days it yields 5 — closing a path where configuration
  could grant anonymous callers a longer TTL than an authenticated free-tier
  user, who is refused above the free-tier threshold with an upgrade prompt. A
  configured ``ttl_options`` maximum below 7 days still wins.

.. note::

   **Self-hosted operators:** the 7-day anonymous cap applies whether or not
   billing is enabled. Deployments with billing off previously allowed
   anonymous secrets up to the configured ``ttl_options`` maximum (30 days on
   stock config); anonymous secrets created there now last at most 7 days.
   Authenticated users are unaffected — their limits still come from their
   plan, and the 14-day free-tier gate is unchanged.
