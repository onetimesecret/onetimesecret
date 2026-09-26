# Data migrations and record updates

How stored data gets changed after the fact, and which tool to reach for.
Onetime Secret keeps model data in Valkey/Redis through Familia and, in full
authentication mode, account data in PostgreSQL or SQLite through Sequel.
There is no single "migrations" mechanism. There are five, each with a
different lifecycle, and picking the wrong one is the usual mistake.

| Need | Tool | Tracked? | Where |
|------|------|----------|-------|
| One-shot, versioned transform of Redis data tied to a release | Familia migration + `bin/ots migrate` | Yes, in Redis | `migrations/` |
| Backfill or dedupe that needs app services (Stripe, billing ops) | `bin/ots migrations <name>` command | No | `lib/onetime/cli/migrations/` |
| Short-lived nightly convergence of drifted field values | Housekeeping chore + `bin/ots housekeeping` | No | `lib/onetime/models/*/chores/` |
| Ongoing detection and repair of index/collection drift | Scheduled maintenance jobs, `domains doctor`, `customers doctor` | No | `lib/onetime/jobs/scheduled/maintenance/` |
| Auth database schema | Sequel migration, run at boot | Yes, `schema_info` | `apps/web/auth/migrations/` |

Read-path tolerance is the sixth option and often the right first move: make
the reader accept both old and new shapes, ship, then converge the stored
bytes with a chore, then delete both the tolerance and the chore. The
`boolean_encoding` feature on the CustomDomain config models and the
`HomepageConfig#secrets_mode_value` coercion are current examples.

## Familia migrations (`bin/ots migrate`)

Familia ships a Redis-native migration framework under
`Familia::Migration`. The original `BaseMigration`, `ModelMigration` and
`PipelineMigration` classes in this repo were upstreamed to it in Familia
2.1; `lib/onetime/migration.rb` is now a one-line `require`.

Three base classes share one lifecycle: `prepare`, `migration_needed?`,
`migrate`, optional `down`.

- `Familia::Migration::Base` for key-level work with raw `redis` access.
  Subclasses set `migration_id`, `description`, and `dependencies`.
- `Familia::Migration::Model` SCANs `{prefix}:*:object` and hands each
  loaded Horreum to `process_record(obj, key)`. Per-record error isolation,
  progress logging, `@interactive = true` for pry on error, and a
  `load_from_key` override for orphan keys.
- `Familia::Migration::Pipeline` batches SCAN results and issues HMSETs
  through a Redis pipeline. Subclasses implement `should_process?` and
  `build_update_fields`, or override `execute_update` for anything other
  than HMSET. Use smaller batches (50 to 200) than for `Model`.

Dry run is the default. Wrap every write in `for_realsies_this_time? { }`;
the block is skipped without `--run`. Count work with `track_stat(:name)`;
counters print in the summary. Optional `validate_before_transform?` and
`validate_after_transform?` hooks run JSON Schema validation through
`Familia::SchemaRegistry` when schemas are configured.

Applied state lives in Redis under the `familia:migrations` prefix (the
Familia default; this app does not override it):

| Key | Type | Content |
|-----|------|---------|
| `familia:migrations:applied` | sorted set | migration_id scored by timestamp |
| `familia:migrations:metadata` | hash | migration_id to JSON (duration, keys scanned/modified, reversible) |
| `familia:migrations:schema` | hash | model name to SHA256 of its field list, for drift detection |
| `familia:migrations:backup:{id}` | hash, 24h TTL | field-level rollback data |

`Familia::Migration::Runner` orders pending migrations by a topological
sort of `dependencies`, stops at the first failure, records success in the
registry only on a real run, and refuses a rollback unless the migration is
applied, has no applied dependents, and defines `down`.
`Familia::Migration::Script` registers Lua scripts for atomic field
rename/copy/delete, TTL-preserving key rename, and backup-then-modify.

### Layout and the CLI wrapper

Migrations live in dated folders, one folder per release-day batch:

```
migrations/
  2025-07-27/20250727_01_convert_symbol_keys.rb
  2026-04-17/20260417_01_backfill_homepage_config.rb
  2026-06-06/20260606_01_unique_index_json_to_raw.rb
  2026-07-03/20260703_01_disable_homepage_auth_links.rb
  2026-07-03/20260703_02_backfill_homepage_secrets_mode.rb
  2026-07-27/20260727_01_backfill_signin_config.rb
```

`bin/ots migrate` wraps the Runner and defaults to the newest folder.

```bash
bin/ots migrate                          # status of migrations in the newest folder
bin/ots migrate --dry-run                # preview all pending
bin/ots migrate --run                    # apply all pending, in dependency order
bin/ots migrate MIGRATION_ID --run       # one migration (fuzzy match on id or class)
bin/ots migrate migrations/2026-07-27/20260727_01_backfill_signin_config.rb --run
bin/ots migrate --rollback MIGRATION_ID
bin/ots migrate --validate               # dependency cycles and missing ids
bin/ots migrate --dir migrations/2026-06-06
```

Passing a file path loads only that file, which avoids class-name
collisions between older batches. Familia's `familia:migrate` rake tasks
are not loaded in this repo; use `bin/ots migrate`.

Write tests as tryouts under `try/migrations/` (see
`unique_index_json_to_raw_try.rb` for the pattern: seed legacy data, run
dry, assert nothing changed, run for real, assert the new shape and that
the migration is a no-op on re-run).

### Ship rule

Deploy schema changes and logic changes separately. A migration that runs
against a model whose loader already assumes the new shape can fail to
load the very rows it needs to fix. The `Model` class header carries the
same warning.

## Operational backfills (`bin/ots migrations <name>`)

A separate family of hand-written commands for work that needs application
services rather than a Redis scan, or that is expected to be re-run as a
reconcile. They are not Familia migrations, are not tracked in the
registry, and are all dry-run by default with `--run` to execute.

```bash
bin/ots migrations backfill-email-hash            # Organization email_hash for federation
bin/ots migrations backfill-stripe-email-hash     # same hash into Stripe customer metadata
bin/ots migrations backfill-subscription-status   # subscription fields from Stripe
bin/ots migrations backfill-secret-counts         # per-customer secrets_active recount
bin/ots migrations grant-probono-entitlements     # legacy identity-plan customers
bin/ots migrations dedupe-instances               # JSON-quoted duplicates in class sorted sets
bin/ots migrations dedupe-participations          # same, per-instance participation sets
bin/ots migrations dedupe-relationships           # same, per-instance relationship sorted sets
```

The convention is a thin CLI adapter over an operation or job class that
owns the logic, so the scheduled job and the manual command are one
implementation. `backfill-secret-counts` over `SecretCountReconcileJob` is
the reference example. Follow it for new commands.

The three `dedupe-*` commands exist because Familia v2 JSON-encodes scalar
values, so an identifier written by application code is `"\"abc\""` while
one written raw by a migration is `abc`, and Redis sets treat those as two
members. `lib/onetime/cli/migrations/deduplication_helper.rb` holds the
shared detection.

## Housekeeping chores (`bin/ots housekeeping`)

Familia's `feature :housekeeping` adds a `chore :name do |obj| ... end`
DSL. A chore is a short-lived convergence routine: register it, run it
nightly until the data is clean, then delete it along with any read-path
tolerance it was covering for. It is not a migration and is not tracked.

```ruby
# lib/onetime/models/organization/chores/standardize_planid.rb
Onetime::Organization.chore :standardize_planid do |org|
  # return truthy when the record was modified
end
```

Chores registered today:

| Model | Chore | Converges |
|-------|-------|-----------|
| Customer | `reserialize_fields` | bare-string field values from pre-Familia-v2 records |
| CustomDomain | `migrate_incoming_secrets_to_config` | legacy `incoming_secrets` JSON blob into IncomingConfig records |
| CustomDomain | `normalize_boolean_encoding` | boolean fields on the config models to their declared storage encoding |
| Organization | `standardize_planid` | legacy planid values to the current catalog |
| Organization | `standardize_owner_id` | `created_by` backfilled from `owner_id` |
| Organization | `ensure_member_through_models` | missing OrganizationMembership rows for pre-v0.25.6 members |
| Organization | `materialize_standalone_entitlements` | entitlement snapshots for orgs created before create! materialized them |

```bash
bin/ots housekeeping list                                      # models with chores
bin/ots housekeeping run Onetime::Organization                 # every chore, every instance
bin/ots housekeeping run Onetime::Organization standardize_planid
bin/ots housekeeping run Onetime::Organization --limit 50
```

`HousekeepingJob` runs the same thing on a schedule. Configure under
`jobs.maintenance.housekeeping` (`enabled`, `cron`, `batch_size`, and an
optional `models` allowlist). Chore bodies own persistence and must be
idempotent; the job owns iteration, error isolation, and stats.

Each chore file header states its branches and the condition for removing
it. Keep that up to date; the header is the removal checklist.

## Audit and repair

Two layers, and they overlap.

**Familia's audit/repair methods** are available on every Horreum class:
`audit_instances`, `audit_unique_indexes`, `audit_multi_indexes`,
`audit_participations`, `audit_related_fields`, `audit_cross_references`,
and a combined `health_check` returning an `AuditReport`. Each has a
`repair_*!` counterpart, plus `repair_all!(verify: true)`.
`rebuild_instances` and the generated `rebuild_<index>` methods write to a
temp key under a fenced lock and swap atomically, so readers never see an
empty index. `Familia.stale_indexes` detects pre-2.10 JSON-encoded unique
index values at boot; `20260606_01_unique_index_json_to_raw` is the
migration that used it.

**Scheduled maintenance jobs** under `lib/onetime/jobs/scheduled/maintenance/`
predate the Familia layer and implement their own scans against the seven
models in `MaintenanceJob::INSTANCE_MODELS`. All ship with
`auto_repair: false`; enable only after reading the JSON audit reports they
log.

| Job | Config key | Default cadence |
|-----|------------|-----------------|
| `PhantomCleanupJob` | `jobs.maintenance.phantom_cleanup` | every 1h |
| `ParticipationGcJob` | `jobs.maintenance.participation_gc` | daily 05:00 |
| `IndexRebuildJob` | `jobs.maintenance.index_rebuild` | daily 04:00 |
| `InstancesRebuildJob` | `jobs.maintenance.instances_rebuild` | weekly, Sun 03:00 |
| `DataConsistencyAuditJob` | `jobs.maintenance.data_audit` | every 6h, read-only |
| `SecretCountReconcileJob` | (see job header) | nightly |
| `EntitlementMaterializeJob` | (see job header) | nightly |

`InstancesRebuildJob` merges rather than swaps and aborts if the diff
exceeds 20% of the set. When adding a new consistency check, prefer
Familia's audit methods so the check tracks the model's declared
relationships automatically; `domains doctor --familia-audit` shows how to
append them to a bespoke report.

**Targeted doctors with repair:**

```bash
bin/ots domains doctor DOMAIN [--familia-audit]   # ten domain integrity checks, report
bin/ots domains repair DOMAIN [--org-id X]        # the only verb that adopts an orphaned domain
bin/ots customers doctor --all --repair
bin/ots customers role reconcile [--apply]        # role multi-index vs the role field
```

`customers role reconcile` exists because Familia's partial writes
(`save_fields`, `multi_field_update`, `commit_fields`) maintain multi
indexes add-only: a value change SADDs into the new bucket and leaves the
old membership in place. Only a full `save` through the app's override
removes it.

Standalone read-only validators live in `scripts/`:
`validate_display_domain_index.rb`, `validate_org_domain_membership.rb`,
`validate_orphan_domain_zset_leaks.rb`, `detect_phantom_receipts.rb`.

## Record-level primitives

For one-off fixes in a console, prefer the narrowest write:

| Method | Writes | Notes |
|--------|--------|-------|
| `obj.save` | every persistent field | clears dirty tracking, maintains indexes fully |
| `obj.save_fields(:a, :b)` | named fields | add-only index maintenance, see above |
| `obj.multi_field_update(a: 1, b: 2)` | named fields, serialized | same |
| `obj.apply_fields(**h)` | in-memory only | follow with `save` |
| `obj.atomic_write { ... }` | scalars + collection ops | one MULTI/EXEC; `watch_keys:` for optimistic locking |
| `Model.build(...) { ... }` | create-only, atomic | raises `RecordExistsError` on collision |
| `obj.refresh!` | reloads from Redis | discards unsaved changes |
| `obj.re_encrypt_fields!` then `save` | encrypted fields | key rotation |
| `Model.storage_inspect(id)` | nothing | decodes raw HGETALL for debugging |

`obj.dirty?` and `obj.changed_fields` show what a save would write.
Familia warns, or raises depending on the class setting, when a collection
is mutated on a parent that has unsaved scalar changes or has never been
saved.

## Legacy tolerance already in the models

Three kinds of read-path tolerance exist and each has a stated end
condition. Do not extend them without one.

- **Familia deserialization** accepts legacy plain-string values and
  legacy JSON-quoted identifiers, logging `Legacy plain string in ...` or
  a rebuild warning instead of failing. The `reserialize_fields` chore and
  the index rebuild migration are the converging steps.
- **`deprecated_fields` features** on Customer, Receipt and Secret keep
  old field declarations (`custid`, `viewed`, `received`, Stripe ids on
  Customer) so legacy hashes still load. The `viewed` to `previewed` and
  `received` to `revealed` rename is the planned first use of a
  `Familia::Migration::Model` with schema validation hooks (see
  `docs/specs/schemata/schema-target-architecture.md`).
- **`with_migration_fields` and the per-model `migration_fields`
  features** carry v1 identifiers, `migration_status`, `migrated_at`, and
  an `_original_object` hashkey holding a RESTOREd copy of the v1 record.
  They belong to the 0.23 to 0.24.5 upgrade. The removal checklist is in
  `lib/onetime/models/features/with_migration_fields.rb`. The upgrade
  pipeline itself was removed from `main` and lives at the `v0.24.5` tag;
  see `scripts/upgrades/README.md`.

## Auth database (Sequel)

`apps/web/auth/migrations/` holds numbered Sequel migrations for the
Rodauth database, used only when `AUTHENTICATION_MODE=full`. They run
automatically at boot through `Auth::Migrator.run_if_needed` using
`AUTH_DATABASE_URL_MIGRATIONS` (elevated privileges) when set, with a
PostgreSQL advisory lock so concurrent instances do not race. SQLite has
no advisory lock: single-instance deployments only, stop the old instance
before starting the new one.

Two of the ten are data migrations rather than schema changes and are the
reference for writing one: `007_normalize_customer_emails.rb` (supports
`DRY_RUN=1`, touches both PostgreSQL and the Redis email index, refuses to
proceed on duplicates) and `008_issuer_scoped_identities.rb` (re-keys
`account_identities` and documents why every pre-existing row gets the
`''` issuer sentinel). Parameterized, operator-run repairs of auth data do
not belong in this directory; they are `Auth::Operations` classes with a
`bin/ots` command in front, as `sso backfill-issuer` and
`customers role reconcile` are. See `apps/web/auth/migrations/README.md`.

## Moving keys between Redis databases or instances

`Onetime::Services::RedisKeyMigrator` copies keys with COPY (same instance,
different db), DUMP/RESTORE with pipelining (cross-instance), or MIGRATE
(discouraged; destructive and prone to loopback failures). It preserves
TTLs and source keys and reports statistics. It has no CLI; drive it from
a console or a script.

## Choosing

- Data is wrong in a way tied to a specific release change, and every
  install upgrading past that release must apply the fix once: Familia
  migration in a dated `migrations/` folder, with a tryout and a changelog
  fragment telling operators to run it.
- Data drifts continuously because of TTL expiry, partial writes, or
  external systems: maintenance job with `auto_repair` off until the audit
  report is understood, or a `bin/ots migrations` reconcile command over
  the same operation.
- Old values need to converge but nothing breaks meanwhile: read-path
  tolerance now, a chore nightly, deletion of both when
  `bin/ots housekeeping run` reports zero modified for a few days.
- A single record or a handful: console, narrowest write primitive,
  `refresh!` to confirm.

Familia's own guides are the reference for the framework side:
`docs/guides/feature-migrations.md`, `feature-housekeeping.md`,
`schema-validation.md`, and `docs/migrating/v2.10.md` in the familia
repository.
