---
labels: admin-v2, phase-3, backend, frontend, architecture
depends: 44-email-ratelimit-tools
epic: "#3653"
---

# Email sender scope + provider visibility — what belongs on Email Tools vs the custom-domain surface

## Why this doc exists

The Email Tools screen is about to gain live provider-health reads (per-provider
status/rates, a send log, a recipient lookup). Before building them we have to
answer one question that the code makes easy to get wrong: **which provider are
we reading?** OneTimeSecret has **two decoupled provider axes**, and conflating
them puts per-domain concerns on a system-wide screen (and vice versa). This doc
draws the line. It designs no fix — it scopes one.

## The two axes (not the same thing)

| | SYSTEM transport | PER-DOMAIN custom sender |
|---|---|---|
| Resolver | `Mailer.determine_provider` | `Mailer.determine_sender_provider` → `CustomDomain::MailerConfig#effective_provider` |
| Env / config | `EMAILER_MODE` → `emailer.mode` | `CUSTOM_MAIL_PROVIDER` → `emailer.sender_provider`; per-domain `MailerConfig.provider` overrides |
| Cardinality | **One** global sending identity per deployment | **One per custom domain** (its own from-address / DKIM identity) |
| Identity source | `emailer.from` / `FROM_EMAIL` | `MailerConfig.from_address` / `from_name` / `reply_to` per domain |
| What it does | Actually sends **all** mail out | White-labels the from-address on custom-domain mail (SES/SendGrid/Lettermint provisioning) |
| Surface | **Email Tools (system-wide) — this work** | **Custom-domain screen — out of scope here** |

They can differ. `GetEmailConfig` already surfaces both (`provider`,
`sender_provider`, `sender_differs`). A deployment runs **one** transport; the
sender-provisioning axis exists purely to brand outbound mail per tenant domain.

### Sharpening: per-domain means identity, not account

Provisioning is per-domain in the sense of the **sender identity/domain only**.
The AWS credentials and region are **install-level**: `ProvisionSenderDomain`
calls `Mailer.provider_credentials(provider)` (the install-wide function) and
**ignores** `MailerConfig#api_key` (a dormant encrypted field). So all custom
domains provision through **one SES account / one region**; only the from-domain
varies. Do not build UI that implies per-domain AWS accounts — the code does not
source them that way today.

## What belongs on Email Tools (this work — Track B)

Live reads against the **active system transport** (`determine_provider`), one
provider, built from `Mailer.provider_credentials(determine_provider)`:

- **Per-provider status + rates** — SES account tier (`enforcement_status` +
  quota) or Lettermint `/stats` counts with a client-computed bounce rate.
  Lettermint's `/stats` reports sent/delivered/bounced but **no complaint
  field** (verified against the gem's `stats_spec` fixtures), so the complaint
  rate reads as "not reported" (—), never a fake 0%. Numeric SES rates need a
  new gem (open decision) — tier only for now.
- **Send log** (item 9) — the transport's own message API. Lettermint
  `/messages`; **SES has no per-message API → capability = false**, surfaced
  honestly, never faked from a local log.
- **Recipient lookup** (item 10) — a single-address check against the local
  `EmailSuppression` store **and** the transport's live suppression API.

These are system-wide because there is exactly one transport. They read the
sending side's health, not any one tenant's.

## What belongs on the custom-domain surface (OUT of scope here)

Anything scoped to a single custom sender domain:

- Per-domain DNS / DKIM / SPF verification state and provisioning health.
- Per-domain sender reputation.
- Per-domain feedback (bounce/complaint) sync — see the blind spot below.

These are per-tenant and belong next to the domain they describe
(`CustomDomain` / `MailerConfig`), not on a system console. Cramming a
domain-picker onto Email Tools would misrepresent a one-transport read as a
matrix.

## The item-2 blind spot (scoped, not solved here)

`SyncProviderFeedback` defaults its provider to `Mailer.determine_provider` — the
**system transport**. It never consults `sender_provider`. Consequence:
bounce/complaint feedback for **custom sender domains** — which may live in a
different SES account or region than the transport — **is not pulled**. The
suppression list therefore reflects the system transport's feedback only.

This is a **per-domain concern**. The fix is per-domain feedback sync on the
custom-domain surface (iterate the custom domains' effective providers, pull each
one's feedback), and it belongs to the **Email Quality Controls** epic, not this
screen. See `docs/specs/email-quality-controls/00-epic.md` (feedback ingestion +
per-domain rate limits). **Do not** design or build that here; do not add a
domain axis to Email Tools to compensate. Track B reads the active transport
only and says so.

## Decision

- Email Tools provider reads target the **active transport** only
  (`determine_provider`) — one provider, no cross-provider matrix, no domain
  picker.
- Per-domain sender health and per-domain feedback sync are **explicitly
  deferred** to the custom-domain surface / the Email Quality Controls epic.
- Implementation contract for the Track-B reads: the Track-B contract handed to
  the backend + frontend implementers (endpoints, envelopes, fail-soft rules).
