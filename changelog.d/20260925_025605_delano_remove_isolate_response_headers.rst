.. A new scriv changelog fragment.

Removed
-------

- Removed ``Onetime::Middleware::IsolateResponseHeaders``. Otto 2.11 copies
  router ``not_found`` / ``server_error`` responses per request, which closes
  the same session-cookie leak (#4401). The ``otto`` floor is now ``~> 2.11``.
  (#4547)
