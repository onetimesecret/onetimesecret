# Custom domain canonical index backfill

Use this runbook once after upgrading to the release that adds
`bin/ots domains backfill-canonical-index`, on any deployment with custom
domains registered before v0.26.14. Use it again whenever
`bin/ots domains doctor --all` reports a `canonical_index_*` finding.

## Background

`custom_domain:canonical_display_domain_index` holds one entry per DNS name.
The key is the name's lower-case A-label (`xn--bcher-kva.example.com` for
`bücher.example.com`) and the value is the identifier of the record registered
for it. Domains registered since v0.26.14 claim their entry when they are
created; this backfill adds the entries for domains registered earlier.

The command compares every custom domain record with the index and puts each
record in one category:

| Category        | Meaning                                                              | Backfill action |
| :-------------- | :------------------------------------------------------------------- | :-------------- |
| `ok`            | The entry for the record's A-label names this record                 | none |
| `missing`       | There is no entry for the record's A-label                           | claims the entry for the record |
| `stale`         | The entry names a record that no longer exists                       | releases it, then claims it for the record |
| `collision`     | Two or more records share one A-label                                | none: resolve by hand (below) |
| `conflict`      | The entry names a different record that exists                       | none: resolve by hand (below) |
| `unconvertible` | The record's name is blank or has no A-label form                    | none |

It also reports index entries keyed by a name that no record has: `stale`
when they name a deleted record (the backfill releases them) and `conflict`
when they name a live record whose own name is different.

The backfill writes only `custom_domain:canonical_display_domain_index`. It
never changes a domain record, `display_domain_index`, or any other key.
Each claim is a server-side compare-and-set that is read back afterwards, and
each release removes an entry only while it still names the identifier the
audit found. A second `--apply` over the same data changes nothing.

## Safety rules

- Run `--apply` only while the application is stopped. The backfill takes no
  lock shared with domain registration and removal, so it is only safe while
  nothing else writes custom domains.
- Keep `jobs.maintenance.index_rebuild.auto_repair` set to `false` (the
  default) during the backfill. The index-rebuild job is fixed in PR #4787.
- Snapshot the datastore before `--apply`.
- Remove duplicate records with `bin/ots domains resolve-collisions --apply`
  (or, for one record, `bin/ots domains remove <extid>`), never by deleting
  keys or index fields directly.

## Procedure

### 1. Check the index-rebuild job setting

Look in the deployment's configuration file (`etc/config.yaml`, or wherever
your deployment keeps it) for:

```yaml
jobs:
  maintenance:
    index_rebuild:
      auto_repair: false
```

A missing key means the default, `false`. If it is `true`, set it to `false`
before the application starts again.

### 2. Dry run (application may still be running)

The dry run reads only, so it can run before the maintenance window to size
the work:

```console
bin/ots domains backfill-canonical-index
bin/ots domains backfill-canonical-index --json > canonical-index-dry-run.json
```

The text report prints the count per category, the planned writes (the first
20; `--json` lists all), every collision group, conflicts and unconvertible
names. Names that are not plain ASCII are printed twice, as stored and
escaped, so that two spellings that look identical can be told apart.

The command exits 1 while collisions, conflicts or unreadable records exist,
and 0 otherwise. `--apply` writes nothing while any record cannot be loaded;
resolve those first (see **Unreadable** in step 6).

### 3. Stop the application

Stop every process that writes custom domains: the web process, the
background worker (`bin/ots worker`) and the scheduler (`bin/ots scheduler`).
In the container image these are the `web`, `worker` and `scheduler`
services; on a Procfile install, the `web`, `worker` and `scheduler` entries.
Leave Valkey/Redis running. Run the remaining commands from a shell with the
application's configuration and `VALKEY_URL`/`REDIS_URL`, for example a
one-off container.

### 4. Snapshot

Take a full snapshot (a managed-service snapshot, or `BGSAVE` and a copy of
the RDB file once `LASTSAVE` changes). Then check for an existing index backup:

```console
valkey-cli -u "$VALKEY_URL" EXISTS custom_domain:canonical_display_domain_index:before-backfill
```

If it exists, reuse it only after confirming that it was taken during this
same uninterrupted maintenance window and that no custom-domain writer has
restarted since. If the application restarted, or the backup's origin is
uncertain, preserve it under a distinct archival key with `RENAMENX` (choose
an unused name and confirm the command returns 1), then take a fresh backup.
Do not overwrite or delete the older backup to make room.

Before the first apply in this window, record whether the index exists:

```console
valkey-cli -u "$VALKEY_URL" EXISTS custom_domain:canonical_display_domain_index
```

If it returns 1 and no backup is being reused, copy the index for rollback:

```console
valkey-cli -u "$VALKEY_URL" COPY custom_domain:canonical_display_domain_index \
  custom_domain:canonical_display_domain_index:before-backfill
```

Confirm `COPY` returns 1. A return of 0 is not a successful backup: check the
source and destination before proceeding. If the index was absent before
the first apply, record that fact instead; rollback for this window is a
`DEL`. Keep this backup or absence record across retries while writers remain
stopped, and never reuse it for a later maintenance window.

### 5. Review and apply

Run the dry run again with the application stopped and compare it with the
earlier one. Then apply:

```console
bin/ots domains backfill-canonical-index --apply
```

The command asks whether the application is stopped; answer `y`. In scripts,
use `--apply --yes` (and `--apply --yes --json` for machine-readable output).

After the writes the command audits the index again. The counts and lists in
the report describe the index as the apply left it, and the report lists every
write with its outcome:

| Outcome        | Meaning |
| :------------- | :------ |
| `claimed`      | The entry now names the record |
| `already_held` | The entry already named the record |
| `released`     | A stale entry was removed |
| `skipped`      | The data changed since the audit; nothing was written |
| `refused`      | Another record holds the name; nothing was written |
| `unverified`   | The claim reported success but read back differently; the claim was released |
| `error`        | The write raised (the detail names the error); the remaining writes still ran |

The command exits 1 when a write did not land (`refused`, `unverified` or
`error`) or when entries are still `missing` or `stale` after the writes.
`refused` and `unverified` should not happen with the application stopped.
If they do, something else is writing: stop it and run the command again. An
`error` usually means the datastore connection failed; run the command again
once it is back.

### 6. Resolve collisions and conflicts

**Collisions.** Each group lists every record that shares one A-label, with
its extid, stored name, organization, verification state, date of the last
passing DNS check (`dns-confirmed`), whether ownership was set by an operator
override, and creation date, and marks the one record a request for the name
resolves to today (`served`); the others are `shadow`. Only one record per
name can be kept. `bin/ots domains resolve-collisions` decides which, by a
fixed rule, and removes the others.

1. Make the plan. This reads only, so it can run before the window:

   ```console
   bin/ots domains resolve-collisions --write collision-plan.json
   ```

   For every record it gathers: whether a request for the name resolves to
   it, its DNS proof, its ownership flag, its organization's state, its
   receipts, its configs and brand settings. It decides each group by this
   rule, in order; the first step that names exactly one record decides, and
   a step that names several marks the group `manual`:

   1. A record whose organization no longer exists is removed.
   2. Exactly one record has a passing TXT check on file: keep it.
   3. Exactly one record has `ownership_verified` (the strategy's check or a
      colonel override): keep it.
   4. Exactly one record is in use, meaning it has receipts, brand settings,
      or an SSO or mailer config: keep it. The five configs an operator action
      can create disabled (signin, signup, homepage, api, incoming) do not
      count.
   5. None is in use: keep the record a request resolves to today, or, when
      none does, the oldest.

   Ownership evidence outranks use on purpose: a record that proved DNS
   control is kept over a record that was used without proof, and the plan
   notes it when the removed record answers for the name today or carries
   receipts, brand settings or configs. Brand settings and configs are
   deleted with the record; receipts keep their `share_domain`.

2. Review the plan. Every group's facts and decision are in the file and in
   the report. For each `manual` group set `keep` to the extid of the record
   to keep and `approved` to `true`, or set `skip` to `true` to leave it.
   Leave `remove` empty: apply derives it from `keep`. Do not edit `auto`
   groups' records; change `keep` and set `approved` if you disagree with the
   rule, or `skip` the group.

3. Apply, with the application stopped:

   ```console
   bin/ots domains resolve-collisions --apply --plan collision-plan.json --dry-run
   bin/ots domains resolve-collisions --apply --plan collision-plan.json
   ```

   The dry run checks each group against the datastore and previews the
   removals. The apply, for each group: compares the group with a fresh audit
   and skips it when its records or their identity changed since the plan;
   removes each other record through the same operation as
   `bin/ots domains remove`, with a reason naming the kept record, the record
   that answers for the name last; re-enters the kept record in the exact
   name index when the name no longer resolves to it; and on the Approximated
   strategy verifies the kept record again so its stored vhost status is
   current. Each removal and verification records its own audit event.

   The provider vhost is keyed by the name, which the kept record shares. The
   removals leave it in place (`keep_vhost`, recorded in each removal's audit
   detail as `vhost_kept`), so the name keeps serving throughout. Only a group
   with no kept record, all orphans, deletes it.

   A removal calls external services: when the removed record has a mail
   sender configured it deletes that sender identity at the mail provider,
   and in a group with no kept record it deletes the vhost for the name on
   the Approximated strategy.

   The command exits 1 when a group was skipped or did not complete; the
   report says why for each. Fix the plan or the record and apply again, or
   apply one group with `--group <canonical name>`.

4. On the Approximated strategy, check the kept records afterwards with
   `bin/ots domains probe <name>`.

If a `manual` group has no record you can justify keeping, leave it skipped
and contact the organizations. The backfill leaves the group untouched and
keeps reporting it.

**Conflicts.** The entry for a record's A-label names a different live
record, or an entry is keyed by a name that the record it names does not
have. Compare the two records (`bin/ots domains doctor --all --json` lists
both identifiers in the `canonical_index_conflict` examples). When the entry
is wrong, release it from `bin/ots console`; the release removes it only while
it still names that identifier:

```ruby
Onetime::CustomDomain.canonical_display_domain_index
  .release_field('<a-label>', '<identifier the entry names>')
```

**Unconvertible.** The record's name has no A-label form, so it cannot be
indexed, and a name like it cannot be registered again. No action is needed;
remove the record if it is junk.

**Unreadable.** A record exists but could not be loaded. `--apply` writes
nothing while any remain, because such a record may have a name that a claim
would give to another record. Inspect it from `bin/ots console`; this shows
each stored field raw and decoded:

```ruby
Onetime::CustomDomain.storage_inspect('<domain_id>')
```

The `domains` commands load the record too, so correct the stored field that
does not decode before using them on it.

### 7. Run the backfill again

Removing a record releases its own entries, so a kept record may now be
`missing` or `stale`. Apply again until the command exits 0:

```console
bin/ots domains backfill-canonical-index --apply
```

### 8. Doctor, then start the application

```console
bin/ots domains doctor --all
```

No `canonical_index_*` finding should remain. Start the application, then
delete the backup key:

```console
valkey-cli -u "$VALKEY_URL" DEL custom_domain:canonical_display_domain_index:before-backfill
```

## Rollback

The backfill changes only the canonical index. To undo it, with the
application still stopped, put back the saved copy from this uninterrupted
maintenance window, not an archived backup from an earlier window:

```console
valkey-cli -u "$VALKEY_URL" COPY custom_domain:canonical_display_domain_index:before-backfill \
  custom_domain:canonical_display_domain_index REPLACE
```

If the absence record for this window confirms there was no index before
the first apply, delete the index instead:

```console
valkey-cli -u "$VALKEY_URL" DEL custom_domain:canonical_display_domain_index
```

Records removed in step 6 are not restored by this; restore them from the
snapshot. Roll back before the application starts: registrations made after
it starts claim entries that the saved copy does not have.

## See also

- `bin/ots domains doctor --all`: check #11 reports the same categories,
  read-only.
- `lib/onetime/operations/domains/canonical_index_audit.rb` and
  `canonical_index_backfill.rb`: the audit and the writes.
- `lib/onetime/operations/domains/collision_resolution.rb` and
  `collision_resolution/rule.rb`: the collision facts, rule, plan and
  removals behind `bin/ots domains resolve-collisions`.
- `lib/onetime/operations/domains/teardown.rb`: the `keep_vhost` option the
  removals pass so the kept record's vhost stays.
