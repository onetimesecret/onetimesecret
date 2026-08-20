.. A new scriv changelog fragment.

Fixed
-----

- Fixed tenant SSO on custom domains being blocked by Content-Security-Policy
  in Chromium.

Changed
-------

- ``SSO_FORM_ACTION_ORIGINS`` is now only needed for split-endpoint OIDC
  configurations; tenant IdP origins on custom domains are allowed
  automatically.

Documentation
-------------

- Corrected Entra sovereign-cloud SSO guidance. Use an ``oidc`` provider with
  the sovereign v2.0 issuer.

AI Assistance
-------------

- Claude assisted with tenant SSO CSP handling and coverage.
