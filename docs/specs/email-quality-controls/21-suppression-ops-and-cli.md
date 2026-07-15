---
labels: email-quality, phase-1, backend, cli
depends: 20-suppression-model-and-gate
epic: TBD
---

# Email quality: suppression operations + CLI

## Context

Part of the **Email Quality Controls** epic, Phase 1.

Every suppression verb is written ONCE as a central operation (decision D3 —
the mailer is site-wide infrastructure; grounding correction 8), then slice 22
adds the colonel adapters and this slice adds the `bin/ots` adapters. The
recipe is the proven one: **op with Data.define Result + AUDIT_VERB → CLI thin
adapter → (slice 22) colonel Logic + route with BOTH auth layers.**

## Scope

- Ops under `lib/onetime/operations/email/suppression/` (namespace
  `Onetime::Operations::Email::Suppression::*`), plus a `store.rb` of shared
  key/projection primitives (the `Dlq::Store` pattern — hash computation,
  reason/scope allowlists, row projections shared byte-for-byte with the CLI):
  - `Check.new(email: | email_hash:).call` — read-only; returns entry +
    effective scope per category; no audit (CONTRACT 4).
  - `Add.new(email:, reason:, actor:, scope: nil, note: nil, expiration: nil).call`
    — validates reason/scope against allowlists, computes hash + obscured form,
    idempotent `:already_suppressed` no-op (records NO audit), else exactly one
    `AdminAuditEvent.record` with `AUDIT_VERB = 'email.suppression.add'`;
    detail carries reason/scope/source + obscured address only.
  - `Remove.new(email: | email_hash:, actor:, reason_note:).call` — decision Q6
    guardrails: refuses `complaint`-reason entries unless `allow_complaint:
    true` (only the CLI adapter passes it); `:not_suppressed` no-op without
    audit; `AUDIT_VERB = 'email.suppression.remove'`; audited on EVERY actual
    removal.
  - `List.new(page:, per_page:, reason: nil).call` — bounded pagination over
    the `instances` registry (MAX_PER_PAGE 100, the `Sessions::List`
    convention); newest-first.
  - `Import.new(io:, source:, actor:, dry_run: true).call` — CSV of addresses
    (+optional reason column) for provider-dump backfills; dry-run default
    returns counts for confirm dialogs; one audit summarizing the batch
    (count, source — never the addresses).
  - `Events.new(email: | email_hash:, limit:).call` — read-only per-address
    activity timeline from `EmailActivity`.
- CLI in `lib/onetime/cli/email/` (required from `lib/onetime/cli.rb`),
  registered as `email suppression {check,add,remove,list,import,events}`:
  `CLI_ACTOR = 'cli'`, `--format text|json`, destructive verbs use the
  dry-run→WARNING→y/N→live pattern (`DlqPurgeCommand` shape); `remove` on a
  complaint entry demands an extra `--allow-complaint` flag with a stern
  warning (Q6: complaint removal is CLI-only).
- Extend `bin/ots email validate` output to report suppression state alongside
  Truemail allowlist/denylist results.

## Grounding — files & pointers

- Op contract + placement: `lib/onetime/operations/README.md` (D3, CONTRACT 4/6)
- Verb templates: `lib/onetime/operations/ban_ip.rb` (idempotent no-op, actor-vs-stored identity), `lib/onetime/operations/ratelimit/reset.rb` (`:not_set` no-audit), `lib/onetime/operations/dlq/purge.rb` (dry-run count for confirms)
- Store pattern: `lib/onetime/operations/dlq/store.rb`, `lib/onetime/operations/sessions/store.rb` (bounded reads, JSON-only parsing)
- Sibling email ops (home + style): `lib/onetime/operations/email/{send_test,list_templates,preview_template}.rb`
- List pagination convention: `lib/onetime/operations/sessions/list_sessions.rb`
- CLI adapter templates: `lib/onetime/cli/email/test_command.rb`, `lib/onetime/cli/queue/dlq_command.rb`; registration in `lib/onetime/cli.rb`
- Bulk-import style (if Import outgrows an op): `lib/onetime/services/README.md` (multi-phase Services), CLI backfill precedent `lib/onetime/cli/migrations/backfill_email_hash_command.rb`
- Validate command: `lib/onetime/cli/email/validate_command.rb`
- Audit store: `lib/onetime/models/admin_audit_event.rb` (redaction, PUBLIC actor ids)

## Acceptance criteria

- [ ] Each verb is a stateless op with keyword init, single `#call`, immutable
      `Data.define` Result; loading requires no app boot beyond the documented
      `boot_application!` in CLI adapters; ops `require` their dependencies
      explicitly.
- [ ] Mutations record EXACTLY ONE `AdminAuditEvent` per actual change; reads,
      dry-runs, and idempotent no-ops record none; audit detail contains
      obscured addresses only (never plaintext, never full hashes as the only
      identifier — include obscured form for operator readability).
- [ ] `Remove` refuses complaint entries except via the CLI flag; the refusal
      is a distinct Result status, not an exception.
- [ ] CLI output stable enough for golden-master tryouts
      (`try/unit/operations/email_ratelimit_tools_try.rb` sibling file); RSpec
      covers allowlist rejection, audit counts, and complaint-removal policy.
- [ ] `Import --dry-run` (default) mutates nothing and audits nothing; live
      import is idempotent on re-run.
- [ ] `bin/ots email validate <addr>` reports suppression status.

## Notes / risks

- `Check`/`Add`/`Remove` accept EITHER plaintext email (hashed internally,
  discarded) or a bare hash (for webhook/event contexts) — never persist the
  plaintext argument.
- Import files are operator-supplied PII: stream-parse, never slurp into logs,
  and remind operators in `--help` to delete source files after import.
- Suppressing an address that later signs up as a customer is legitimate
  (their account-security mail still flows per scope rules) — do not add a
  customer-existence check to `Add`.
