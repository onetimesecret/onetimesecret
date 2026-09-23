.. A new scriv changelog fragment.

Changed
-------

- Auth database migrations add passkey scope and relying-party columns. Existing
  passkeys continue to work. PostgreSQL deployments whose runtime role cannot
  alter the schema must configure ``AUTH_DATABASE_URL_MIGRATIONS`` or apply the
  migrations before upgrading. #4414
