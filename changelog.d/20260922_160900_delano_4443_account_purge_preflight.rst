.. A new scriv changelog fragment.

Changed
-------

- Every account purge, including self-service account closure, the colonel
  purge and ``ots customers purge``, now runs a read-only organization
  preflight first and fails closed. When a workspace the account owns still
  holds custom domains, billing state, other members or an unfinished v1 to v2
  migration, or its ownership, membership or contact-email index records have
  drifted, the purge is refused and the account is left intact instead of
  half-deleted. Self-service closure answers ``error_type:
  account_deletion_refused`` with the blocker codes; the customers CLI and the
  admin customer detail view show the blockers and the stage a purge stopped
  at. Transfer ownership, remove the retained resources or repair the drift
  with ``ots customers doctor``, then retry. (#4440, #4443)
- Default-workspace provisioning collisions (ownerless workspaces,
  contact-email index drift) now answer ``409`` with ``error_type:
  AccountProvisioningFailed`` and are latched on the account instead of being
  retried silently on every sign-in. ``ots customers diagnose`` reports them
  and ``ots customers doctor`` repairs them. (#4443)

Documentation
-------------

- Documented the purge preflight policy and discovery depth in
  ``docs/architecture/deleting-an-account.md`` and added the
  ``ownerless-workspace-email-index-collision`` runbook. (#4443)
