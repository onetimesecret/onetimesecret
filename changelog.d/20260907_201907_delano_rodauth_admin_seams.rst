Added
-----

- Added optional ``RODAUTH_ADMIN_URL`` (config
  ``site.admin.rodauth_admin_url``). In ``full`` authentication mode, set it to
  link Colonel customer and session views to the matching standalone Rodauth
  Admin record.

Changed
-------

- In ``full`` authentication mode, Colonel session views now identify the
  standalone Rodauth Admin record as the session authority.

Removed
-------

- Removed the development-only ``GET /auth/admin/stats`` stub.
