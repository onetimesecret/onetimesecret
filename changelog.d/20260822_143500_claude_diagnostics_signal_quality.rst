.. A new scriv changelog fragment.

Added
-----

- Sentry error reports now carry a pseudonymous user reference on both
  services, so self-hosted operators can see how many users an issue
  affects without any personal data leaving the application. The backend
  derives a 16-hex ``user_ref`` from the account email via a keyed,
  region-scoped derivation (``DIAGNOSTICS_REF_REGION``), publishes it to
  the frontend in the bootstrap payload as ``diagnostics_ref``, and
  attaches the same reference to backend error captures. Anonymous
  sessions and installs without a keying secret send no user context at
  all, and the reference is cleared on logout.

Fixed
-----

- Frontend Sentry issues no longer fragment across deploys. Schema
  validation errors are grouped by schema name, and API 404/aborted/
  network errors are grouped by method, parameterized route, and status,
  instead of by minified bundle stack frames whose hashes change with
  every release.
