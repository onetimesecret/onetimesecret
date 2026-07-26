.. A new scriv changelog fragment.

Removed
-------

- ``bin/ots domains bulk-repair`` is gone. It now prints ``use: bin/ots domains
  doctor --all --repair`` and exits non-zero. The old command was wrong in two
  ways a compatibility wrapper would have preserved: its membership test compared
  an array of domain *objects* against a domain id *string*, so it was always
  false and every org-owned domain in the install was reported as "mismatched"
  and then "repaired"; and its mutation loop recorded no admin audit event at
  all. ``domains doctor --all --repair`` covers the same ground with a correct
  test, an audited repair, and index checks bulk-repair never had. Orphaned
  domains still need a per-domain decision via ``bin/ots domains repair DOMAIN
  --org-id ORG``.

Changed
-------

- ``bin/ots domains doctor --repair`` now fixes a missing ``org.domains``
  membership through the same ``Operations::Domains::Repair`` operation the
  ``domains repair`` command and the colonel endpoint use, rather than writing to
  the sorted set directly. That means the repair is now recorded as a
  ``domain.repair`` admin audit event, and it is now blocked (loudly, per domain,
  without aborting an ``--all`` scan) when the domain already belongs to a
  different organization — the raw write bypassed that guard. Detection is
  unchanged and still O(1) per domain. Two operational consequences: the sorted
  set score for a *repaired* entry is now the repair time rather than the
  domain's creation time, which can reorder that entry in listings; and a repair
  that fails is reported under a new ``failed_repairs`` key and makes the command
  exit non-zero even when other domains were fixed.

- ``bin/ots domains doctor`` now reports domains with no organization at all
  (orphans) as a HIGH finding, pointing at ``domains repair --org-id``. It never
  repairs them — assigning an organization stays a human decision. Doctor
  previously skipped orphans entirely, so ``doctor --all`` gave a knowingly
  incomplete picture unless the operator also ran ``domains orphaned``. On an
  install that has orphans, ``doctor --all`` will now exit non-zero where it
  previously exited clean.
