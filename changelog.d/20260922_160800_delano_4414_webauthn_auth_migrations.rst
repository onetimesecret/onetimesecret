.. A new scriv changelog fragment.

Changed
-------

- Two auth database migrations, ``009_webauthn_surface_scope`` and
  ``010_webauthn_rp_id``, add nullable ``surface_scope`` and ``rp_id`` columns
  to ``account_webauthn_keys``. They are the first auth migrations since
  ``008`` shipped in v0.26.2. Full mode applies pending migrations at boot and
  a failed migration stops the boot, so a PostgreSQL install whose runtime role
  cannot ``ALTER TABLE`` will not start until it either sets
  ``AUTH_DATABASE_URL_MIGRATIONS`` to a role that owns the schema or applies
  the migrations before upgrading::

      bundle exec sequel -m apps/web/auth/migrations "$AUTH_DATABASE_URL_MIGRATIONS"

  Existing passkeys keep working. Rows without a value are treated as
  registered on the canonical host, which is what tenant re-authentication
  already assumed for them. (#4414)
