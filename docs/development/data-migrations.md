# Data migrations and record updates

This guide helps contributors choose a mechanism for changing stored data
and helps operators identify how to run it. Onetime Secret keeps model data
in Valkey/Redis through Familia and, in full authentication mode, account
data in PostgreSQL or SQLite through Sequel.

Use the table to choose a tool, then read its section before running it.
Tracking means recording which migrations have been applied; it does not
mean that a tool automatically backs up data.

| Need | Tool | Tracked? | Where |
|------|------|----------|-------|
| One-shot, versioned transform of Redis data tied to a release | [Familia migration + `bin/ots migrate`](#familia-migrations-binots-migrate) | Yes, through the Runner; not single-ID/file runs | `migrations/` |
| Backfill or dedupe that needs app services (Stripe, billing ops) | `bin/ots migrations <name>` command | No | `lib/onetime/cli/migrations/` |
| Short-lived nightly convergence of drifted field values | Housekeeping chore + `bin/ots housekeeping` | No | `lib/onetime/models/*/chores/` |
| Ongoing detection and repair of index/collection drift | Scheduled maintenance jobs, `domains doctor`, `customers doctor` | No | `lib/onetime/jobs/scheduled/maintenance/` |
| Auth database schema | Sequel migration, run at boot | Yes, `schema_info` | `apps/web/auth/migrations/` |

Read-path tolerance is another option: let readers accept both old and new
formats before updating stored records. The `boolean_encoding` feature on
the CustomDomain config models and `HomepageConfig#secrets_mode_value`
coercion are examples. Remove tolerance only after verifying that no records
or active writers still require the old format.

## Before running commands

Run commands from the repository root in a configured application environment,
with the project's Ruby dependencies installed. The CLI boots the application;
check that its database configuration targets the intended environment.
Stripe backfills also require billing configuration and Stripe credentials,
and can make API reads even in dry-run mode.

Review the release-specific instructions and take a recoverable backup before
changing data. Dry-run behavior differs by tool: Familia single-migration
runs and operational backfills default to dry-run, but housekeeping runs
write immediately. Auth migrations can run during application boot. A
migration dry-run is not a guarantee that boot itself is read-only.

## Familia migrations (`bin/ots migrate`)

Familia ships a Redis-native migration framework under
`Familia::Migration`. The original `BaseMigration`, `ModelMigration` and
`PipelineMigration` classes in this repo were upstreamed to it in Familia
2.1; `lib/onetime/migration.rb` is now a one-line `require`.

Three base classes share the forward lifecycle: `prepare`,
`migration_needed?`, then `migrate`. An optional `down` method implements
rollback separately.

- `Familia::Migration::Base` for key-level work with raw `redis` access.
  Subclasses set `migration_id`, `description`, and `dependencies`.
- `Familia::Migration::Model` SCANs `{prefix}:*:object` and hands each
  loaded Familia model object (`Horreum`) to `process_record(obj, key)`.
  It provides per-record error isolation and progress logging. Set
  `@interactive = true` to open Pry on errors, or override `load_from_key`
  to handle orphan keys.
- `Familia::Migration::Pipeline` batches SCAN results and issues HMSETs
  through a Redis pipeline. Subclasses implement `should_process?` and
  `build_update_fields`, or override `execute_update` for anything other
  than HMSET. Use smaller batches (50 to 200) than for `Model`.

For forward migrations invoked through the CLI, wrap every write in
`for_realsies_this_time? { }`; the block is skipped without `--run`. Count
work with `track_stat(:name)`; counters print in the summary. Model migrations
can use `validate_before_transform?` and `validate_after_transform?` hooks
for JSON Schema validation through `Familia::SchemaRegistry`. Validation
failures are counted and logged, not automatically rejected. Pipeline
migrations bypass these per-record hooks; their dry runs scan records but
do not execute the transformation callbacks.

Applied state lives in Redis under the `familia:migrations` prefix (the
Familia default; this app does not override it):`

| Key | Type | Content |
|-----|------|---------|
| `familia:migrations:applied` | sorted set | migration_id scored by timestamp |
| `familia:migrations:metadata` | hash | migration_id to JSON (duration, keys scanned/modified, reversible) |
| `familia:migrations:schema` | hash | model name to SHA256 of field names and types, for drift detection |
| `familia:migrations:backup:{id}` | hash, default 24h TTL | field-level rollback data, when explicitly backed up |

Schema digests and field backups are framework facilities, not automatic
Runner output. Each field backup refreshes the backup hash's expiry.

`Familia::Migration::Runner` orders pending migrations by a topological
sort of `dependencies` and records applied state on a real run when
`migration_needed?` is true and `migrate` completes without raising. It stops
on a failed Runner result, but isolated record errors do not necessarily
produce one: inspect error counts as well as the final status. Rollback
requires an applied migration with `down` and no applied dependents among
the loaded migration classes.
`Familia::Migration::Script` registers Lua scripts for atomic field
rename/copy/delete, TTL-preserving key rename, and backup-then-modify.

### Layout and the CLI wrapper

Migrations live in dated folders, one folder per release-day batch:

```
migrations/

  2026-04-17/20260417_01_backfill_homepage_config.rb
  2026-06-06/20260606_01_unique_index_json_to_raw.rb
  2026-07-03/20260703_01_disable_homepage_auth_links.rb
  2026-07-03/20260703_02_backfill_homepage_secrets_mode.rb
  2026-07-27/20260727_01_backfill_signin_config.rb
```

`bin/ots migrate` defaults to the newest dated folder, not every migration
in the repository. Use `--dir` to select an older batch; loading the parent
`migrations/` directory does not recursively load its dated subdirectories.

Inspect a batch and preview a specific migration:

```bash
bin/ots migrate --dir migrations/2026-07-27
bin/ots migrate --dir migrations/2026-07-27 --validate
bin/ots migrate migrations/2026-07-27/20260727_01_backfill_signin_config.rb
```

The first command lists applied and pending migrations; the second checks
dependencies. The third runs that migration without enabling its guarded
writes. The CLI does not declare a `--dry-run` option or expose an
all-pending preview. Inspect each migration's summary before applying it.

Apply the selected batch through the Runner, then check its status:

```bash
bin/ots migrate --dir migrations/2026-07-27 --run
bin/ots migrate --dir migrations/2026-07-27
```

**Single-migration execution differs from batch execution.** Passing an ID
or file with `--run` calls the migration directly, bypassing the Runner's
dependency checks and applied-state recording. A successful run can still
appear pending. Use batch execution when you need registry tracking. ID
lookup allows partial matches; a full file path avoids ambiguous selection
and loads only that file, avoiding class-name collisions between batches.

Rollback is not a general recovery procedure. None of the current migrations
defines `down`. Although the CLI exposes `--rollback MIGRATION_ID`, Familia
2.12.0 calls `down` without `prepare` or enabling guarded writes, then removes
applied state if no exception occurs. Verify a migration's rollback behavior
before relying on it; adding `--run` does not change this path.

Familia's `familia:migrate` rake tasks are not loaded in this repo; use
`bin/ots migrate`. The command dispatch is implemented in
[`migrate_command.rb`](../../lib/onetime/cli/migrate_command.rb).

Write tests as tryouts under `try/migrations/` (see
[`unique_index_json_to_raw_try.rb`](../../try/migrations/unique_index_json_to_raw_try.rb)
for the pattern: seed legacy data, run
dry, assert nothing changed, run for real, assert the new shape and that
the migration is a no-op on re-run).

### Deploy readers and data changes separately

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
values, so the JSON-encoded member `"abc"` (including the quote characters)
and the raw member `abc` can coexist. Redis treats them as distinct members. `lib/onetime/cli/migrations/deduplication_helper.rb` holds the
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

**`housekeeping run` writes immediately; it has no dry-run option.** Use
`list` to inspect available chores. `--limit` limits records scanned, not
records modified.

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

Use framework methods for model-level checks, scheduled jobs for recurring
maintenance, and doctor commands for targeted investigation.

**Familia's audit/repair methods** are available on every Horreum class:
`audit_instances`, `audit_unique_indexes`, `audit_multi_indexes`,
`audit_participations`, `audit_related_fields`, `audit_cross_references`,
and a combined `health_check` returning an `AuditReport`. Related-field and
cross-reference checks require `audit_collections: true` and
`check_cross_refs: true`, respectively. Repair methods include
`repair_indexes!` for unique indexes and `repair_all!(verify: true)` for
repair followed by verification; cross-reference drift has no automatic
repair counterpart.

`rebuild_instances` uses a temporary key and atomic swap, without a fenced
lock. Do not assume every generated `rebuild_<index>` behaves the same way:
class-level multi-index rebuilds delete live buckets before repopulating them. `Familia.stale_indexes` detects pre-2.10 JSON-encoded unique
index values at boot; `20260606_01_unique_index_json_to_raw` is the
migration that used it.

**Scheduled maintenance jobs** under `lib/onetime/jobs/scheduled/maintenance/`
predate the Familia layer and implement their own scans against the seven
models in `MaintenanceJob::INSTANCE_MODELS`. The phantom, participation,
index, and instance repair jobs default to `auto_repair: false`; review their
JSON audit reports before enabling repair. The data audit is read-only.
Secret-count reconciliation and entitlement materialization write when
scheduled and have no `auto_repair` gate.

| Job | Config key | Default cadence |
|-----|------------|-----------------|
| `PhantomCleanupJob` | `jobs.maintenance.phantom_cleanup` | every 1h |
| `ParticipationGcJob` | `jobs.maintenance.participation_gc` | daily 05:00 |
| `IndexRebuildJob` | `jobs.maintenance.index_rebuild` | daily 04:00 |
| `InstancesRebuildJob` | `jobs.maintenance.instances_rebuild` | weekly, Sun 03:00 |
| `DataConsistencyAuditJob` | `jobs.maintenance.data_audit` | every 6h, read-only |
| `SecretCountReconcileJob` | `jobs.maintenance.enabled` (master toggle; no separate enable switch) | daily 04:30 |
| `EntitlementMaterializeJob` | `jobs.maintenance.entitlement_materialize` | daily 03:00 |

`InstancesRebuildJob` merges rather than swaps and aborts if the diff
exceeds 20% of the set. When adding a new consistency check, prefer
Familia's audit methods so the check tracks the model's declared
relationships automatically; `domains doctor --familia-audit` shows how to
append them to a bespoke report.

### Inspect and repair specific records

Replace `DOMAIN` with the target domain. Start with reports:

```bash
bin/ots domains doctor DOMAIN --familia-audit
bin/ots customers doctor --all
bin/ots customers role reconcile
```

The following commands make changes:

```bash
bin/ots domains repair DOMAIN
bin/ots customers doctor --all --repair
bin/ots customers role reconcile --apply
```

`domains repair` can adopt an orphaned domain; use `--org-id` with the intended
organization ID when needed. `customers role reconcile` compares the role
multi-index with each customer's role field.

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
| `obj.save` | every persistent field | clears dirty tracking; Customer's override removes stale role memberships |
| `obj.save_fields(:a, :b)` | named fields | class-level multi-index maintenance is add-only; unique indexes track old values |
| `obj.multi_field_update(a: 1, b: 2)` | named fields, serialized | same index behavior as `save_fields` |
| `obj.apply_fields(**h)` | in-memory only | follow with `save` |
| `obj.atomic_write { ... }` | scalars + collection ops | one MULTI/EXEC; `watch_keys:` for optimistic locking |
| `Model.build(...) { ... }` | create-only, atomic | raises `RecordExistsError` on collision |
| `obj.refresh!` | reloads from Redis | discards unsaved changes |
| `obj.re_encrypt_fields!` then `save` | encrypted fields | key rotation |
| `Model.storage_inspect(id)` | nothing | decodes raw HGETALL for debugging |

`obj.dirty?` and `obj.changed_fields` show tracked in-memory changes, not
the full set of fields that `save` writes. Class-level multi-index updates
can remain add-only even on a full save unless an application override
removes stale memberships.

Depending on configuration, Familia warns or raises when a collection is
mutated on a parent with unsaved scalar changes. This guard can be disabled
and is suppressed inside `atomic_write`.

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

Two examples include data transformations:
`007_normalize_customer_emails.rb` supports `DRY_RUN=1` and updates SQL
emails and the Redis email index. SQL duplicates skip SQL normalization
without aborting the migration; Redis duplicates skip individual entries.
`008_issuer_scoped_identities.rb` changes the schema and backfills
`account_identities`, documenting why pre-existing rows receive the `''`
issuer sentinel. Parameterized, operator-run repairs of auth data do
not belong in this directory; they are `Auth::Operations` classes with a
`bin/ots` command in front, as `sso backfill-issuer` and
`customers role reconcile` are. See the [auth migration guide](../../apps/web/auth/migrations/README.md).

## Moving keys between Redis databases or instances

[`Onetime::Services::RedisKeyMigrator`](../../lib/onetime/services/redis_key_migrator.rb)
selects COPY for different databases on the same instance, or pipelined
DUMP/RESTORE for cross-instance transfers. These paths copy keys with their
TTLs and report statistics. A retained MIGRATE fallback defaults to copy
mode, but can delete source keys when called with `copy_mode: false`.
The service has no CLI; use it from a console or script after checking the
selected strategy and options.

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
  tolerance first, then a nightly chore. Before deleting either, check
  complete scans for errors and remaining legacy records, and confirm
  that active writers no longer produce the old format. Zero modified
  records in a limited scan is not enough.
- A single record or a handful: console, narrowest write primitive,
  `refresh!` to confirm.

For framework details, see the [Familia repository](https://github.com/delano/familia):
`docs/guides/feature-migrations.md`, `docs/guides/feature-housekeeping.md`,
`docs/guides/schema-validation.md`, and `docs/migrating/v2.10.md`.
The behavior described here was checked against Familia 2.12.0, the version
in this repository's lockfile.
