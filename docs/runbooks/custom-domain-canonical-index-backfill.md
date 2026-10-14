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
- Remove a duplicate record with `bin/ots domains remove <extid>`, never by
  deleting keys or index fields directly.

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
the RDB file once `LASTSAVE` changes). Then keep a copy of the index itself
for a quick rollback:

```console
valkey-cli -u "$VALKEY_URL" COPY custom_domain:canonical_display_domain_index \
  custom_domain:canonical_display_domain_index:before-backfill
```

`COPY` returns 1 when it copied. It returns 0 when the index does not exist
yet (the rollback is then a `DEL`), or when the backup key is left from an
earlier attempt: keep that older copy, it holds the state before the first
apply.

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
override, and creation date. For each group:

1. Find the record whose organization has proven DNS ownership. A record with
   a recent `dns-confirmed` date passed the TXT check. `ownership_verified`
   alone can be an operator override. To check now, run
   `bin/ots domains verify <extid> --dry-run` for each record in the group.
   `--dry-run` saves nothing to the record. It still records an audit event,
   and on the Approximated strategy it creates the vhost for the name when
   none exists.
2. Keep that record. Remove each other record in the group by its extid:

   ```console
   bin/ots domains remove <extid>
   ```

   The command shows what it will remove and asks for confirmation
   (`--dry-run` only shows; `--apply` skips the prompt). Use the extid, not
   the domain name: the name resolves to one record of the group, not
   necessarily the one to remove. If the extid is not found, pass the
   record's objid instead (`domain_id` in the `--json` report).

   It works with the application stopped: it writes to Valkey/Redis from the
   shell. It also calls external services over the network. On the
   Approximated strategy it deletes the vhost registered for the removed
   record's name, and when the record has a mail sender configured it deletes
   that sender identity at the mail provider.
3. On deployments using the Approximated strategy, the deleted vhost can be
   the one the kept record uses. Run `bin/ots domains verify <extid>` for the
   kept record (it creates the vhost again when it is missing), then
   `bin/ots domains probe <name>`.

If no record in the group can show DNS ownership, leave the group in place
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
application still stopped, put the saved copy back:

```console
valkey-cli -u "$VALKEY_URL" COPY custom_domain:canonical_display_domain_index:before-backfill \
  custom_domain:canonical_display_domain_index REPLACE
```

If there was no index before the first apply, delete the index instead:

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
