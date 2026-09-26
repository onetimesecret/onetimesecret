.. A new scriv changelog fragment.

Changed
-------

- ``bin/ots migrate`` now routes every modifying path (batch, single ID or
  file, rollback) through one runner with one invariant: a run is
  dependency-checked, runs the full lifecycle, and is recorded in the
  registry exactly once, only after it succeeds. Single-migration runs are
  now tracked like batch runs. ``--dry-run`` is a real option and previews
  all pending migrations; nothing modifies data without ``--run``, including
  ``--rollback``, which now calls ``prepare`` before ``down`` and removes
  applied state only after a successful actual rollback. A migration that
  returns ``false`` or reports isolated record errors is no longer recorded
  as applied; the run exits non-zero as ``failed`` or ``partial``. An
  already-applied migration is refused for a modifying single run, and an
  ambiguous partial ID is refused instead of picking the first match.
