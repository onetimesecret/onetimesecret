.. A new scriv changelog fragment.

Added
-----

- ``bin/ots domains resolve-collisions`` decides which custom domain record to
  keep when two or more share one DNS name, the collision groups
  ``backfill-canonical-index`` reports and never writes. It gathers, for every
  record in a group, whether a request for the name resolves to it today, its
  DNS proof, its ownership flag, its organization's state, its receipts, its
  configs and brand settings, decides each group by a fixed rule (DNS proof,
  then ownership, then use), and writes a plan file for review. ``--apply``
  removes the other records through the same operation as ``domains remove``,
  leaving the provider vhost for the name in place for the kept record,
  re-enters the kept record in the exact name index when the removed record
  answered for the name, and on the Approximated strategy verifies the kept
  record again. Groups the rule cannot decide, and groups whose records changed
  since the plan, are left for the operator. ``scripts/resolve_canonical_collisions.rb``
  runs the same operation on v0.26.17.

Changed
-------

- The ``backfill-canonical-index`` report marks, in each collision group, the
  record a request for the name resolves to today, and points at
  ``resolve-collisions`` instead of a by-hand removal.
