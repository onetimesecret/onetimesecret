.. A new scriv changelog fragment.

Added
-----

- ``bin/ots domains resolve-collisions`` creates a reviewable plan for
  duplicate custom domain records, preferring DNS proof, then verified
  ownership, then use. ``--apply`` removes duplicates while preserving the
  kept record's provider vhost. Ambiguous groups require an operator decision;
  groups whose records changed since the plan are skipped. Stop the
  application before applying; follow
  ``docs/runbooks/custom-domain-ascii-index-backfill.md``.

Changed
-------

- The normalized custom domain name index is now called the ASCII index.
  ``backfill-canonical-index`` becomes ``backfill-ascii-index``, doctor
  findings use ``ascii_index_*``, and collision plans use ``ascii_name``
  instead of ``canonical``.

  Deployments with ``custom_domain:canonical_display_domain_index`` must
  migrate it before starting the new release. With the application stopped,
  run
  ``bin/ots migrate migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index.rb --run``.
  See ``docs/runbooks/custom-domain-ascii-index-backfill.md`` for the
  migration and backfill procedure.

- Collision reports from ``backfill-ascii-index`` identify the record
  currently serving each name and direct operators to ``resolve-collisions``.
