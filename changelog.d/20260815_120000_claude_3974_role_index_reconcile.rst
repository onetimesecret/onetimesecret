.. A new scriv changelog fragment.

Added
-----

- (`#3974 <https://github.com/onetimesecret/onetimesecret/issues/3974>`_)
  New ``bin/ots customers role reconcile`` command repairs drift between the
  authoritative ``role`` field and the derived ``customer:role_index:*`` sets
  that ``role list`` and ``colonel_count`` read. The default run is a dry-run
  report of per-bucket stale and missing members; ``--apply`` (with ``--force``
  or an interactive confirmation) writes the repair, and ``--json`` emits a
  machine-readable report. The repair is an incremental SADD/SREM diff rather
  than the familia-generated DEL-then-repopulate rebuild, so an interrupted
  run can never leave the index emptier than it started. Check + repair logic
  lives in the shared ``Auth::Operations::Customers::ReconcileRoleIndex`` op,
  which records one audit event per applied run.

  The index drifts through two familia 2.12 mechanisms: targeted writers
  (``save_fields`` / ``multi_field_update`` / ``commit_fields``) maintain
  multi-indexes through an add-only path that retains the previous role's
  bucket member on change, and right-to-be-forgotten TTL expiry deletes the
  customer hash while its index members persist — permanently inflating
  ``colonel_count`` until reconciled.

AI Assistance
-------------

- Claude implemented the reconcile op, CLI action, specs and tryouts,
  building on the original contribution in PR #3999. (#3974)
