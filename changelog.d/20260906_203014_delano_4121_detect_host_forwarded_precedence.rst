.. A new scriv changelog fragment.

Security
--------

- RFC 7239 ``Forwarded: host=`` is no longer used to determine the application
  host. Deployments that depend on it must rewrite ``Host`` or provide
  ``X-Forwarded-Host``, ``Apx-Incoming-Host``, or ``X-Original-Host`` through a
  configured trusted proxy (#4121).
