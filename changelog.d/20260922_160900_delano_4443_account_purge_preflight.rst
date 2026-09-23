.. A new scriv changelog fragment.

Changed
-------

- Account purges now stop before deletion when an owned workspace retains
  resources or has inconsistent ownership, membership, migration, or contact
  indexes. Resolve reported blockers or run ``ots customers doctor`` before
  retrying. #4440, #4443
- Default-workspace provisioning conflicts now return ``409`` and stop retrying
  on each sign-in. ``ots customers diagnose`` reports them and
  ``ots customers doctor`` repairs them. #4443

Documentation
-------------

- Documented purge preflight behavior in
  ``docs/architecture/deleting-an-account.md`` and added the
  ``ownerless-workspace-email-index-collision`` runbook. #4443
