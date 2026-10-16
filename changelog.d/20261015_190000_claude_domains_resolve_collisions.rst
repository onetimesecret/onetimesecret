.. A new scriv changelog fragment.

Added
-----

- ``bin/ots domains resolve-collisions`` decides which custom domain record to
  keep when two or more share one DNS name, the collision groups
  ``backfill-ascii-index`` reports and never writes. It gathers, for every
  record in a group, whether a request for the name resolves to it today, its
  DNS proof, its ownership flag, its organization's state, its receipts, its
  configs and brand settings, decides each group by a fixed rule (DNS proof,
  then ownership, then use), and writes a plan file for review. ``--apply``
  removes the other records through the same operation as ``domains remove``,
  leaving the provider vhost for the name in place for the kept record,
  re-enters the kept record in the exact name index when the removed record
  answered for the name, and on the Approximated strategy verifies the kept
  record again. Groups the rule cannot decide, and groups whose records changed
  since the plan, are left for the operator.

Changed
-------

- The custom domain name index keyed by the lower-case A-label is now called
  the ASCII index everywhere, so that "canonical" keeps its one meaning in this
  codebase, the install's own site host. ``bin/ots domains backfill-canonical-index``
  is now ``backfill-ascii-index``, the doctor's ``canonical_index_*`` findings
  are ``ascii_index_*``, the collision plan file's ``canonical`` field is
  ``ascii_name``, and the Valkey key ``custom_domain:canonical_display_domain_index``
  is ``custom_domain:ascii_display_domain_index``. An install that already has
  the old key renames it with
  ``bin/ots migrate migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index.rb --run``
  before starting the new release; until then domains registered since
  v0.26.14 are not found by their index entry, and new registrations claim
  names in an empty index. The runbook moved to
  ``docs/runbooks/custom-domain-ascii-index-backfill.md``.

- The ``backfill-ascii-index`` report marks, in each collision group, the
  record a request for the name resolves to today, and points at
  ``resolve-collisions`` instead of a by-hand removal.
