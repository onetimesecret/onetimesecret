.. A new scriv changelog fragment.

Fixed
-----

- Restored SSO login on Chromium-family browsers (Chrome, Edge, and others),
  which broke in v0.26.0-rc1. The emitted Content-Security-Policy contained
  ``form-action 'self'``, and because Chromium enforces ``form-action`` across
  the entire redirect chain, the SSO form-POST that hands off to the identity
  provider was blocked — clicking a provider button did nothing. Firefox was
  unaffected because it only checks the initial, same-origin form target. The
  app now adds each active SSO provider's IdP origin to the ``form-action``
  directive at boot, so the redirect is allowed. For sovereign clouds, an OIDC
  issuer whose authorization endpoint lives on a different origin, or org-level
  SSO with placeholder providers, additional origins can be supplied via
  ``SSO_FORM_ACTION_ORIGINS`` (space-separated). Operators who cannot yet
  upgrade can set ``CSP_ENABLED=false`` as an interim workaround to drop the CSP
  header entirely. (#3848)
