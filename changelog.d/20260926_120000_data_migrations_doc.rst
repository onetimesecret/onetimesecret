Documentation
-------------

- Added ``docs/development/data-migrations.md``, a developer reference for
  the five ways stored data gets changed after the fact: Familia migrations
  under ``bin/ots migrate``, the ``bin/ots migrations`` backfill commands,
  housekeeping chores, the scheduled audit/repair jobs and doctors, and the
  Sequel auth-database migrations. Covers when to pick each, the Redis
  registry keys, the record-level write primitives, and the legacy
  read-path tolerances that still exist in the models and what removes them.

AI Assistance
-------------

- Claude drafted the data migrations developer reference from a survey of
  the Familia and Onetime Secret migration, housekeeping, and repair code.
