.. A new scriv changelog fragment.

Fixed
-----

- Fixed tenant SSO on custom domains behind proxies that rewrite ``Host``.

Security
--------

- The example Caddyfile now strips client-supplied ``X-Forwarded-Host`` before
  proxying requests.

Documentation
-------------

- Documented host handling for deployments with a Host-rewriting proxy in the
  example Caddyfile.

AI Assistance
-------------

- Claude assisted with tenant SSO host handling and coverage.
