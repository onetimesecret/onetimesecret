---
labels: email-quality, work, roadmap
depends: 00-epic
epic: TBD
---

# Email Quality Controls — MVP roadmap, slice status, and delegated workflow

## Purpose

The epic (`00-epic.md`) defines thirteen slices but has no tracking surface:
there is no record of which slices are built, which existing code diverges from
the specs, or in what order the remaining work should land. This document is
that surface. It is updated in the same PR as any slice work.

Audit date: 2026-08-16, against `main` (`ddeed4f`).

Problem-space background (event taxonomy, channels beyond email, preference
design): [`../notifications/pareto-brief.md`](../notifications/pareto-brief.md).

## Slice status

| Slice | Status | Evidence |
|---|---|---|
| 00-epic | tracking only | Decisions Q0–Q6 and findings A/B/C live in `00-epic.md`; no ADR |
| 10 headers + classification | NOT STARTED | `Delivery::Base#normalize_email` still whitelists exactly `to/from/reply_to/subject/text_body/html_body`; no `category` or `headers` references in the mail layer |
| 11 keys/hashing/tokens | NOT STARTED | No `EmailProtection` namespace; no token purpose in `lib/onetime/key_derivation.rb` |
| 20 suppression model + gate | PARTIAL, divergent | Model `lib/onetime/models/email_suppression.rb` + gate at `lib/onetime/mail/delivery/base.rb:59` exist, but keyed by normalized **plaintext** address (class-level `class_hashkey :entries`), no `scope`, no `SCHEMA`, no `EmailActivity` — spec 20 requires an `email_hash`-keyed per-instance Horreum. Migration, not extension. |
| 21 suppression ops + CLI | PARTIAL, divergent | Flat ops in `lib/onetime/operations/email/` (`add_suppression`, `remove_suppression`, `ingest_feedback`, `sync_provider_feedback`, `recipient_lookup`, …); only CLI is `lib/onetime/cli/email/sync_feedback_command.rb`. No `Suppression::` namespace, no `Check`/`List`/`Import`/`Events`, no Q6 complaint-removal guardrail. |
| 22 suppression admin UI | PARTIAL, divergent | Colonel `/email/deliverability/*` routes (`apps/api/colonel/routes.txt:124-133`) + `src/apps/admin/components/EmailDeliverabilitySection.vue`. `DELETE …/suppressions/:address` puts the plaintext address in the URL, violating Q4 / piiQueryGuard. |
| 30 ESP webhook ingestion | NOT STARTED | No `apps/api/mail_events/`; ingestion is pull-based via `lib/onetime/mail/feedback/{ses,lettermint,smtp2go}.rb` + CLI sync. (SMTP2Go adapter exists but is absent from the epic's provider allowlist; SendGrid has no adapter.) |
| 31 bounce/complaint handlers | PARTIAL, divergent | Feedback normalizers exist (above) plus synchronous-5xx capture (`record_sync_bounce`, `delivery/base.rb:72`); no `ProcessProviderEvent`, no handler registry, no soft-bounce threshold/TTL policy. |
| 40 outbound rate limits | NOT STARTED | No outbound limiter in `lib/onetime/security/` (inbound limiters exist as templates); no `email:limit:` keys. |
| 50 one-click unsubscribe | NOT STARTED | No unsubscribe route in any `routes.txt`; no `List-Unsubscribe` anywhere. |
| 51 opt-back-in | NOT STARTED | No `resubscribe` references; no `Suppression::Release`. |
| 60 observability | PARTIAL, thin | Only `EmailSuppression.sends_skipped` and `Customer.emails_sent`; no `EmailHealthJob`/`HealthReport`/`/email/health`. |
| 61 hardening/cutover | NOT STARTED | `schedule_email` still in `lib/onetime/jobs/publisher.rb`, `email.message.schedule` still declared, still used by `expiration_warning_job.rb` — decision C not executed. **Live bug**: delayed expiration warnings dead-letter into `dlq.email.message` where `DlqEmailConsumerJob` discards non-auth templates. |

Grounding caveat for implementers: the shipped deliverability feature predates
the epic specs. Where they conflict, the specs win; slice PRs migrate the
existing code rather than build alongside it.

## MVP cut

Working MVP = every unsubscribable outgoing email carries RFC 8058 headers and
a footer link; the one-click POST endpoint writes a scoped suppression;
suppressed marketing/notification mail is skipped while transactional and
security mail still delivers.

Dependency-ordered PR sequence, one slice-cluster per PR, each independently
reviewable and shippable:

| PR | Slice(s) | Branch | Size | Content |
|---|---|---|---|---|
| 1 | 11 | `claude/eqc-pr1-token` | S | `EmailProtection::Token` codec + KeyDerivation purpose. Pure library, no behavior change. Unblocks everything. |
| 2 | 10 | `claude/eqc-pr2-headers` | M–L | Template category registry (replace the `Mailer.template_class_for` case statement with a metadata hash: class, category, unsubscribable) and a `headers:` channel threaded `Templates::Base#to_email` → `Mailer.deliver_raw` → worker payload → `normalize_email` → all four real backends. SESv2 stays on simple content with a headers array; warn-and-skip if the SDK lacks it — no raw-MIME rewrite in MVP. |
| 3 | 20 (alignment) | `claude/eqc-pr3-suppression` | M–L | Migrate suppression to spec 20: `email_hash` key, `scope`, category-aware gate, `unsubscribed` reason. Keep the gate location (`Delivery::Base#deliver`) and fail-open semantics. Move colonel endpoints off plaintext-address URLs (Q4). |
| 4 | 50 | `claude/eqc-pr4-unsubscribe` | M | `POST /unsubscribe/:token` (`auth=noauth csrf=exempt`; precedent: billing Stripe webhook route) + GET landing page that renders a confirm form and never mutates; footer link in `layout.html.erb`. **Completes the MVP.** |
| 5 (fast-follow) | 51 | `claude/eqc-pr5-optin` | M | Opt-back-in + category preferences (extend `update_notification_preference.rb` VALID_FIELDS, Customer hashkey per the `feature_flags` pattern, `NotificationSettings.vue`). |

Deferred beyond MVP: slice 30 (pull sync suffices for now), 40, the 22
rebuild, 60, and 61 — though 61's dropped-expiration-warning bug deserves a
separate targeted fix ahead of the rest of that slice.

### MVP acceptance test

With the logger backend: send an unsubscribable template → `List-Unsubscribe`
and `List-Unsubscribe-Post` headers plus footer link present; POST the token →
scoped suppression entry created; resend → skipped with a `suppressed` log
line; send `password_request` to the same address → delivered.

## Small-team workflow

How this lands with a small team (or one orchestrator delegating to agents),
following the practices of healthy open-source projects: spec-first, small
reviewable PRs, CI as the merge gate, decisions recorded once.

- **Roles.** An orchestrator owns sequencing, task specs, review, and PR text,
  and deliberately stays out of the code: fact-finding is delegated to
  read-only exploration, implementation (including tests) to implementation
  agents working from a task spec that quotes the relevant slice file.
- **Per-PR loop.** Write the task spec from the slice doc → implement on the
  PR branch → code review + unit lane (`tests/lanes/run unit` and
  `tests/lanes/run spec-fast`) locally → push → PR referencing the slice
  spec → CI auth-mode matrix green → land. Each PR also updates the status
  table in this document.
- **Branching.** One branch per PR off latest `main` (names above), landed
  sequentially — no long-lived integration branch, no stacked history.
- **Decision hygiene.** Design decisions stay in `00-epic.md` under their Q
  numbers; this document records status only. A decision changed mid-flight
  gets a Q-entry edit in the same PR that implements the change.

## Out of scope for this document

Slice-level design detail — each slice file remains the authority for its own
scope, acceptance criteria, and open questions.
