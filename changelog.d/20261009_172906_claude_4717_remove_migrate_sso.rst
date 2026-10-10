.. A new scriv changelog fragment.

Removed
-------

- ``bin/ots domains migrate-sso`` and the operation behind it. Moving an
  installation's SSO users to a domain's SSO in bulk is not a supported
  operator workflow. The customer-facing transition still works through
  sign-in: a user who signs in through the domain's SSO is joined to its
  organization and it becomes their default workspace (#4717).
