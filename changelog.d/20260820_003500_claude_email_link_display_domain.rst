.. A new scriv changelog fragment.

Fixed
-----

- Magic-link, password-reset, account-verification and SSO link-confirmation
  emails now point at the domain the recipient signed in from, instead of the
  canonical host, on deployments behind a proxy that rewrites ``Host``.

- WebAuthn assertions on custom domains are now verified against the domain the
  browser is on.

AI Assistance
-------------

- Claude assisted with public-host resolution for Rodauth-generated URLs and
  regression coverage.
