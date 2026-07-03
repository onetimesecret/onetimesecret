.. A new scriv changelog fragment.

Fixed
-----

- Incoming secrets (``/incoming``) submitted on a custom domain are now bound
  to that domain: the notification email links to the secret on the custom
  domain and is delivered via that domain's sender config, matching the
  authenticated share flow.

Changed
-------

- Secret-link and incoming-secret emails render the secret's custom domain in
  the shared layout's header wordmark and footer link. Account and system
  emails, and install-level links inside email bodies, still use the
  canonical host.
