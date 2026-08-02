.. A new scriv changelog fragment.

Fixed
-----

- The secret duration dropdown no longer offers a lifetime the server will
  quietly shorten. Secrets created without signing in are capped server-side at
  7 days, but the dropdown was built from the full configured list, so on a
  stock install a guest could pick "30 days", see no error, and get less. The
  applicable ceiling is now published in the bootstrap payload
  (``secret_options.ttl_max_anonymous`` for guests,
  ``organization.limits.secret_lifetime`` for signed-in users) and longer
  options are filtered out of the list. The guest ceiling is published on every
  deployment, self-hosted included, and reflects any ``TTL_MAX_ANONYMOUS``
  override, so raising or lowering it moves the dropdown with it. A remembered
  duration above the
  ceiling now falls back to the configured default instead of silently
  resolving to a shorter lifetime.
