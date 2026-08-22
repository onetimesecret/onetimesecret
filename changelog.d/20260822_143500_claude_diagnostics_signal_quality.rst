.. A new scriv changelog fragment.

Added
-----

- Authenticated browser sessions and selected backend error captures now
  carry a scoped pseudonymous actor reference, so operators can correlate
  an issue with affected accounts within its configured scope. The backend
  derives the 16-hex ``actor_ref`` from the account email, publishes it to
  the frontend in the ``diagnostics_ref`` bootstrap payload, and attaches
  it to supported backend captures. No direct identifiers, such as email
  addresses or customer IDs, are sent; however, the reference must still
  be handled as potentially personal data. Anonymous sessions and installs
  without a usable keying secret send no user context, and the frontend
  clears the reference on logout.

Fixed
-----

- Selected frontend Sentry issues use explicit grouping instead of
  minified bundle stack frames. Schema validation errors with a schema
  name group by that name. Axios-shaped request errors with ``config.url``
  group by method, the path normalized by the existing URL scrubbers, and
  an HTTP status or coarse ``aborted``/``network`` outcome; other errors
  retain Sentry's default grouping.
