Added
-----

- ``RODAUTH_ADMIN_URL`` (config ``site.admin.rodauth_admin_url``): the base URL
  of the standalone Rodauth Admin instance. Optional and credential-free. When
  set in ``full`` authentication mode, the colonel customer page links to the
  matching Rodauth account, and the sessions console and per-customer sessions
  panel link to it as the session authority. Nothing is ever requested from
  it; unset renders plain text.

Changed
-------

- In ``full`` authentication mode the colonel sessions console and the
  per-customer sessions panel now state that they are not the session
  authority (they read the Redis session store; Rodauth's session table is
  authoritative) instead of presenting a partial list as complete.

Removed
-------

- The development-only ``GET /auth/admin/stats`` stub. Its numbers are served
  by the standalone Rodauth Admin behind real authentication.
