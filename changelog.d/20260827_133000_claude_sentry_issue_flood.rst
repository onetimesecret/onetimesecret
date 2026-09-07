Fixed
-----

- Frontend diagnostics now apply configured filtering and grouping to manually
  captured errors.

- Password confirmation flows no longer record a login or run login-session
  side effects.

- Invalid UTF-8 session-cookie values are rejected instead of causing a server
  error.

- Custom-domain lists accept proxy ``vhost.keep_host`` values provided as
  booleans.

- Diagnostic reports no longer carry secret or receipt identifiers in event
  grouping keys or in the request-context path.

Changed
-------

- v1 API form errors now group by endpoint and are reported at warning level.

- Errors from in-app browsers whose injected bridge did not load are ignored.
