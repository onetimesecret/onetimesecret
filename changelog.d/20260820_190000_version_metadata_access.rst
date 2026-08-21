.. A new scriv changelog fragment.

Security
--------

- ``/api/v2/version`` and ``/api/v3/version`` now require session or Basic Auth.
  Update unauthenticated version probes; anonymous pages and API responses no
  longer expose application or Ruby version details. (#4195)
