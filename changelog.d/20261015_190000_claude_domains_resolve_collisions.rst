.. A new scriv changelog fragment.

Added
-----

- ``bin/ots domains resolve-collisions`` creates a reviewable plan for
  duplicate custom domain records. Selection prefers historical DNS
  confirmation, then stored ownership verification, then use; it does not
  establish current DNS control. Ambiguous groups and billing-protected
  removals require explicit plan approval; ``--yes`` skips only the prompt.
  Groups whose reviewed evidence changed are skipped.

  ``--apply`` removes duplicates while preserving the kept record's provider
  vhost. Removed records' settings and branding are deleted, not merged.
  Stop all custom domain writers and snapshot the datastore before applying;
  follow the `collision-resolution procedure
  <docs/runbooks/custom-domain-ascii-index-backfill.md#6-resolve-collisions-and-conflicts>`__,
  including the backfill and doctor checks before restarting.

Changed
-------

- The normalized custom domain name index is now called the ASCII index.
  ``backfill-canonical-index`` becomes ``backfill-ascii-index``, doctor
  findings use ``ascii_index_*``, and collision plans use ``ascii_name``
  instead of ``canonical``. Regenerate and review older rule-version plans.

  Deployments with ``custom_domain:canonical_display_domain_index`` must
  migrate it before starting the new release. With the application stopped,
  follow the `ASCII index migration and backfill runbook
  <docs/runbooks/custom-domain-ascii-index-backfill.md>`__.

- Collision reports from ``backfill-ascii-index`` identify the record
  currently serving each name and direct operators to ``resolve-collisions``.
