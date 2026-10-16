# Custom domain ASCII index backfill

Use this runbook once after upgrading to the release that adds
`bin/ots domains backfill-ascii-index`, on any deployment with custom
domains registered before v0.26.14. Use it again whenever
`bin/ots domains doctor --all` reports an `ascii_index_*` finding.

On an install that ran any release from v0.26.14 to v0.26.17, the index is
still stored under its former key, `custom_domain:canonical_display_domain_index`.
Rename it before
starting the new release, with the application stopped:

```console
bin/ots migrate migrations/2026-10-15/20261015_01_rename_ascii_display_domain_index.rb --run
```

The migration also renames a `:before-backfill` copy left by an earlier run
of this runbook, and refuses to overwrite a key that already exists under
the new name.

## Background

`custom_domain:ascii_display_domain_index` holds one entry per DNS name.
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

The backfill writes only `custom_domain:ascii_display_domain_index`. It
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
bin/ots domains backfill-ascii-index
bin/ots domains backfill-ascii-index --json > ascii-index-dry-run.json
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
valkey-cli -u "$VALKEY_URL" EXISTS custom_domain:ascii_display_domain_index:before-backfill
```

If it exists, reuse it only after confirming that it was taken during this
same uninterrupted maintenance window and that no custom-domain writer has
restarted since. If the application restarted, or the backup's origin is
uncertain, preserve it under a distinct archival key with `RENAMENX` (choose
an unused name and confirm the command returns 1), then take a fresh backup.
Do not overwrite or delete the older backup to make room.

Before the first apply in this window, record whether the index exists:

```console
valkey-cli -u "$VALKEY_URL" EXISTS custom_domain:ascii_display_domain_index
```

If it returns 1 and no backup is being reused, copy the index for rollback:

```console
valkey-cli -u "$VALKEY_URL" COPY custom_domain:ascii_display_domain_index \
  custom_domain:ascii_display_domain_index:before-backfill
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
bin/ots domains backfill-ascii-index --apply
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

**Collisions.** Only one custom-domain record per A-label can be kept.
`bin/ots domains resolve-collisions` makes a read-only proposal using a fixed
keeper-selection rule. It removes records only with `--apply` and a reviewed
plan. Cached billing can require deletion approval; it does not select the
keeper.

The report distinguishes these facts for every record:

| Evidence | Meaning and limits |
| :------- | :----------------- |
| `domain_id`, `extid`, stored name | Full domain identity, with escaped spelling for non-ASCII names |
| `org_id`, `org_extid`, `org_name`, organization state | Full local organization identity and active, archived or missing state |
| Historical `dns-confirmed` timestamp | A passing TXT check stored on file, **not a fresh DNS check** or proof of current control |
| `ownership_verified`, `verified_by_override`, verification state | Stored ownership flag and whether it came from an operator override; separate from historical DNS confirmation |
| `served` / `shadow` | Whether the local name index routed requests to this record at plan time; **not a network probe** |
| Receipts, brand settings, use configs | Evidence of use under the existing rule |
| `all_configs`, non-use configs, vhost, creation timestamp | Additional local state, including configs that do not count as use |
| Billing label, `planid`, `stripe_customer_id`, `stripe_subscription_id`, `subscription_status` | Organization billing from `local_cache` only; **no live Stripe lookup** |

Neither plan generation nor its billing guard refreshes DNS or Stripe data.
An apply-time datastore comparison is not a fresh DNS or billing-provider
check. The Approximated strategy's kept-record verification is a separate
apply step described below.

1. Make the plan. This reads only, so it can run before the window:

   ```console
   bin/ots domains resolve-collisions --write collision-plan.json > collision-plan-01.txt
   ```

   Read `collision-plan-01.txt` and keep it with the JSON plan. The plan
   records its generation timestamp and `rule_version`. Version 2 adds cached
   billing and the deletion approval guard without changing keeper selection.
   Older rule-version plans are rejected: regenerate and review them with
   the current command. Do not make an old plan usable by editing its version.

   The rule runs in this order; after excluding missing organizations, the
   first step that names exactly one record decides. A step that names
   several marks the group `manual`:

   1. A record whose organization no longer exists is removed.
   2. Exactly one record has a historical passing TXT check on file: keep it.
   3. Exactly one record has `ownership_verified` (the strategy's check or a
      colonel override): keep it.
   4. Exactly one record is in use, meaning it has receipts, brand settings,
      or an SSO or mailer config: keep it. The five configs an operator action
      can create disabled (signin, signup, homepage, api, incoming) do not
      count.
   5. None is in use: keep the record a request resolves to today, or, when
      none does, the oldest.

   Historical ownership evidence outranks use in this rule. It does not
   establish current DNS control. The notes identify a proposed removal that
   was served at plan time or carries receipts, brand settings or use configs.
   Review `all_configs` too: non-use configs are not a reason to keep a
   record, but are still deleted with it. **Brand settings and configs are
   deleted, not merged into the keeper. Receipts retain their `share_domain`.**

2. Review the plan. Every group's facts, proposal and notes are in the JSON
   and text report. Check the full organization and domain IDs, historical
   ownership evidence, routing, use, all configs and cached billing before
   approving deletion.

   - For each `manual` group, set `keep` to the extid of the record to keep
     and `approved` to `true`, or set `skip` to `true` to leave it.
   - For **any** group that would remove a billing-protected record, set
     `approved` to `true` after reviewing the billing evidence, or `skip` it.
     This includes an `auto` proposal whose keeper is unambiguous. An auto
     keeper proposal is not deletion approval.
   - Billing protection covers locally cached `active`, `trialing`,
     `past_due` and `unpaid` subscriptions, and uncertain status with Stripe
     references or status. The report labels these `live_or_recoverable` or
     `unknown`. `no_local_subscription` and `not_live` describe local cache
     state only, not a current Stripe check. A plan ID alone is not live
     subscription evidence.
   - A record whose `org_id` names an organization that cannot be loaded is
     reported with state `dangling`. It is still an orphan and proposed for
     removal, but its billing cannot be read, so it is labelled `unknown` and
     the group needs `approved`. Check why the organization is gone (deleted,
     or a datastore problem) before approving. A record with no `org_id` at
     all is `missing` and is removed without approval.
   - Do not edit saved record evidence to bypass the guard. If the evidence
     changed, regenerate the plan and review it again. Billing data is not
     used to override the keeper-selection rule.

   Leave `remove` empty when changing `keep`: apply derives removals from
   `keep`. An empty `keep` is accepted only when fresh evidence confirms that
   every record in the group is an orphan, and `keep` may not name an orphan
   (state `missing` or `dangling`): nothing owns it, and apply skips the
   group. If you disagree with an `auto` proposal, change `keep` and set
   `approved`, or `skip` the group. Keep the reviewed plan with the reports.
   Plan mode exits 1 while a keeper decision or required deletion approval
   is pending. `--yes` and answering `y` bypass only the command prompt;
   neither sets `approved` on a plan group.

3. Apply, with the application stopped:

   ```console
   bin/ots domains resolve-collisions --apply --plan collision-plan.json --dry-run > collision-preview-01.txt
   ```

   Read the preview before running the non-dry apply:

   ```console
   bin/ots domains resolve-collisions --apply --plan collision-plan.json --yes > collision-apply-01.txt
   ```

   The saved-output example uses `--yes` so an interactive prompt is not
   hidden by redirection. Required group approvals must already be saved in
   the JSON. For interactive confirmation, omit `--yes` and the redirection.
   Keep each output file; choose a new filename for every retry rather than
   overwriting an earlier report. Use `--json` instead of text when needed;
   non-dry `--apply --json` also requires `--yes`. The prompt's removal count
   excludes skipped groups and unapproved approval-required groups, including
   billing-protected `auto` groups. Those groups remain skipped even with
   `--yes`.

   Both dry-run and non-dry apply finish preflight for all selected groups
   before any removal. An unreadable record anywhere in the audit refuses the
   entire run; plan generation also refuses incomplete audits. A group is
   skipped if membership, identity, organization state, cached billing,
   verification evidence, routing, receipt count, config presence, brand
   presence or vhost presence changed since the plan. Regenerate and review
   changed plans rather than editing their saved evidence.

   The dry run previews eligible removals without domain changes or
   collision-summary events. Removal previews may write `domain.remove`
   observations, and preview failures may also be audited. A failed preview
   produces a `partial` outcome and exit status 1, not a successful dry run.
   Preflight does not lock out writers: keep the application stopped.

   Non-dry apply removes each other record through the same operation as
   `bin/ots domains remove`, with a reason naming the kept record, the record
   that answers for the name last; re-enters the kept record in the exact
   name index when the name no longer resolves to it; and on the Approximated
   strategy verifies the kept record again so its stored vhost status is
   current. This verification is not part of the historical plan evidence.

   Each outcome, including a skipped group, carries saved context: `run_id`,
   run start time, `plan_generated_at`, `plan_sha256`, `rule_version`,
   decision, rule, approval flags,
   `billing_source: local_cache`, full record evidence and notes. Text apply
   reports print that evidence alongside the actual removal statuses, exact
   index result, kept-record verification result and errors. The saved record
   evidence describes the plan, not the state after apply. Preserve the
   reviewed JSON plan and console output together so the decision can be
   reconstructed after records are deleted.

   A non-dry apply records a `domain.resolve_collision` admin audit entry for
   each group outcome, including skipped groups, with its context and run ID.
   Existing `domain.remove` audit entries remain per deletion; kept-record
   verification also records its own event. Use the run ID to correlate group
   summaries with the saved report. The Administrator's Log bounds detail
   arrays to 25 entries; summary totals retain the complete counts. Console
   and JSON reports retain all records and outcomes. Match the run ID and
   reviewed plan SHA256 to the saved report for a large group.
   A dry run writes no collision summaries
   or successful deletion events, but may write preview/failure audit entries.
   `removed_audit_failed` means the deletion committed but its individual
   audit write failed; the group is `partial`, not a successful apply.

   The provider vhost is keyed by the name, which the kept record shares. The
   removals leave it in place (`keep_vhost`, recorded in each removal's audit
   detail as `vhost_kept`), so the name keeps serving throughout. Only a group
   with no kept record, all orphans, deletes it.

   Sender preflight compares remote identities across all audited records,
   including records outside the selected groups. SES and SMTP2GO identities
   are compared by sender domain; SendGrid and Lettermint use provider IDs,
   resolved from the provider's domain list. That list is read once per
   provider per run, with the installation's provider credentials, even
   during `--dry-run`: a SendGrid run pages through the account's domain
   authentications, a Lettermint run makes one list request. The cost does
   not grow with the number of custom domain records. A sender domain the
   provider's list does not hold has no identity to retain; deletion reads
   the same list and deletes nothing for it. Unreadable identities skip
   affected groups before deletion. The skip reason names the
   record it stopped on (by extid) and whether its local mailer config could
   not be read or the provider lookup failed; a provider failure is worth a
   retry, a local one needs the record repaired or its mailer config removed.
   The record named can be any audited domain, not only one in the group.

   A shared sender identity is retained, with `sender_identity_kept` in the
   removal's preview/apply audit detail. The removed record's local config is
   still deleted. This also retains identities shared by two planned removals:
   either removal might fail. If all referencing records are removed, inspect
   the provider and remove the unused identity manually. Unshared sender
   identities follow the normal provider teardown. A group with no kept
   record deletes the vhost for the name on the Approximated strategy.

   The command exits 1 when a group was skipped or did not complete; the
   report says why for each. Keeper reload or verification persistence failures
   produce a `partial` outcome without hiding earlier committed deletions.
   Preserve that report and inspect the remaining records before retrying:
   completed deletions are not rolled back. Regenerate and review a plan for
   remaining collisions, or select one group with `--group <ASCII name>`. A
   `--group` that names no group in the plan (a typo, or the Unicode spelling
   of the name) is refused with exit status 1 before anything is applied; the
   message gives the ASCII name when the Unicode spelling matched a group.

4. On the Approximated strategy, check the kept records afterwards with
   `bin/ots domains probe <name>`.

If a `manual` group has no record you can justify keeping, leave it skipped
and contact the organizations. The backfill leaves the group untouched and
keeps reporting it.

**Conflicts.** The entry for a record's A-label names a different live
record, or an entry is keyed by a name that the record it names does not
have. Compare the two records (`bin/ots domains doctor --all --json` lists
both identifiers in the `ascii_index_conflict` examples). When the entry
is wrong, release it from `bin/ots console`; the release removes it only while
it still names that identifier:

```ruby
Onetime::CustomDomain.ascii_display_domain_index
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
bin/ots domains backfill-ascii-index --apply
```

### 8. Doctor, then start the application

```console
bin/ots domains doctor --all
```

No `ascii_index_*` finding should remain. Start the application, then
delete the backup key:

```console
valkey-cli -u "$VALKEY_URL" DEL custom_domain:ascii_display_domain_index:before-backfill
```

## Rollback

The backfill changes only the ASCII index. To undo it, with the
application still stopped, put back the saved copy from this uninterrupted
maintenance window, not an archived backup from an earlier window:

```console
valkey-cli -u "$VALKEY_URL" COPY custom_domain:ascii_display_domain_index:before-backfill \
  custom_domain:ascii_display_domain_index REPLACE
```

If the absence record for this window confirms there was no index before
the first apply, delete the index instead:

```console
valkey-cli -u "$VALKEY_URL" DEL custom_domain:ascii_display_domain_index
```

Records removed in step 6 are not restored by this; restore them from the
snapshot. Roll back before the application starts: registrations made after
it starts claim entries that the saved copy does not have.

## See also

- `bin/ots domains doctor --all`: check #11 reports the same categories,
  read-only.
- `lib/onetime/operations/domains/ascii_index_audit.rb` and
  `ascii_index_backfill.rb`: the audit and the writes.
- `lib/onetime/operations/domains/collision_resolution.rb` and
  `collision_resolution/rule.rb`: the collision facts, rule, plan and
  removals behind `bin/ots domains resolve-collisions`.
- `lib/onetime/operations/domains/teardown.rb`: the `keep_vhost` option the
  removals pass so the kept record's vhost stays.
