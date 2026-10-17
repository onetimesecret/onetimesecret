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
- The setting is off by default on two levels. Operators enable it for the
  install with ``ORGS_BASE_DOMAIN_SIGNUP_ENABLED=true``
  (``features.organizations.base_domain_signup_enabled``), and each
  organization needs the new ``base_domain_signup`` entitlement, which no
  plan grants by default (standalone installs grant every entitlement, so
  there the install flag decides). Both are checked when a sign-up is
  validated, so turning the flag off or losing the entitlement stops a saved
  setting from admitting anyone; the saved value stays and takes effect
  again once both are back.

Changed
-------

- The domain signup-config API reports ``uses_allowlist`` in place of
  ``requires_allowlist``: with ``allow_base_domain`` the allowlist strategy
  can run on an empty list, so the old name overstated it.
- The colonel domain config editor refuses a change that would leave a
  config invalid, such as switching sign-up validation to the allowlist
  strategy with nothing to admit, instead of saving it. A config that is
  already invalid can still be disabled or repaired.
