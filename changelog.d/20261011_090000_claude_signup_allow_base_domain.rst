.. A new scriv changelog fragment.

Added
-----

- Custom-domain sign-up validation can admit the domain's own organization
  automatically. Under the domain-allowlist strategy, the new
  ``allow_base_domain`` setting allows sign-ups from the custom domain's
  registrable domain (``secrets.acme.com`` admits ``@acme.com``) without the
  operator listing it, and follows the domain if it is renamed. Listed
  domains still apply alongside it, and the list may be left empty while the
  setting is on. Available on the workspace Signup Validation page, the
  domain signup-config API (``allow_base_domain``) and the colonel domain
  config editor.
