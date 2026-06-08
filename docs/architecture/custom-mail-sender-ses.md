# docs/architecture/custom-mail-sender-ses.md
---
title: AWS SES Sender Domain Provider
type: reference
status: supported
updated: 2026-06-08
summary: Configuring AWS SES as the provider for the domain-level custom sender flow (DKIM provisioning, verification, teardown) including region selection and data-residency.
---

AWS SES is a supported provider for the **domain-level custom sender flow**: when an
organization enables a custom sender identity on one of its custom domains, the
platform calls SES on the organization's behalf to register a sender identity,
returns the DKIM records the customer must add at their registrar, verifies those
records, and tears the identity down when the sender config is removed.

This document covers the SES-specific configuration. For the provider-agnostic
design (the three layers, who picks the provider, how credentials flow), see
[`custom-mail-sender.md`](./custom-mail-sender.md).

## Scope

SES here is the **sender-domain provisioning provider**, selected once per
installation. It is **not** a per-customer choice and is **not** something an
end user picks from a dropdown — exactly as with Lettermint, the operator
configures the provider, and the customer's only decision is "do I want emails
from my domain to use my from-address/reply-to?" (see the *Customer Decision
Surface* section of the architecture overview).

The work this provider enables is the **domain-level lifecycle**:

```
enable custom sender → provision SES identity → show DKIM CNAMEs
                     → customer adds DNS → verify → (later) delete
```

## Selecting SES

Set the provisioning provider:

```bash
CUSTOM_MAIL_PROVIDER=ses
```

`CUSTOM_MAIL_PROVIDER` decouples *domain provisioning* from the *sending
transport* (`EMAILER_MODE`). You can run SMTP (or any transport) for outbound
delivery while still using SES for sender-domain DKIM provisioning. If
`CUSTOM_MAIL_PROVIDER` is unset, the provisioning provider falls back to
`EMAILER_MODE`.

## Regions — two knobs

SES configuration exposes **two** region settings that serve different layers.
Set the provisioning region (`EMAILER_REGION`) to the intended region; the
validation knob is **currently inert** (see the #2833 decision below), but
keeping both aligned is recommended and future-proofs the config:

| Env var | Drives | Used by |
|---|---|---|
| `EMAILER_REGION` (falls back to `AWS_REGION`) | The SES API client endpoint | Provisioning (`create/get/delete_email_identity`) and delivery |
| `CUSTOM_MAIL_SES_REGION` | `email_providers.ses.region` config | Validation config only — **currently inert** (see the #2833 decision below) |

```bash
EMAILER_REGION=ca-central-1
CUSTOM_MAIL_SES_REGION=ca-central-1
```

> **Gotcha:** `EMAILER_REGION` defaults to the literal placeholder `smtp`, not a
> real AWS region. Because that placeholder is non-empty it wins over
> `AWS_REGION`, so the SES client would be built with an invalid region and
> provisioning would fail. **You must set `EMAILER_REGION` (or `EMAILER_MODE=ses`
> with a real `EMAILER_REGION`) to a valid AWS region when using SES.**

> **Decision ([#2833](https://github.com/onetimesecret/onetimesecret/issues/2833) — resolved by design):**
> `CUSTOM_MAIL_SES_REGION` is **not** threaded through `ValidateSenderDomain`,
> and it does not need to be. The validation strategies (SES, SendGrid,
> Lettermint) are uniform: each reads the already-provisioned records from
> `mailer_config.dns_records` and runs live DNS lookups against them. They
> generate nothing from a region, so there is no validation-time value for a
> region to influence. Region is purely a **provisioning / SES-API** concern —
> the client region comes from `EMAILER_REGION` (→ `AWS_REGION`), and whatever
> records SES assigns for that region are stored on the `MailerConfig` and read
> back verbatim at verification.
>
> Concretely, `email_providers.ses.region` is merged by `ProviderConfig` but then
> dropped by the strategy factory (the validation strategies declare no
> `accepted_options`), so the value is currently inert. SES DKIM records are
> token-based CNAMEs and region-independent; any region-specific records (e.g. the
> `feedback-smtp.<region>.amazonses.com` MAIL FROM MX + SPF) must be emitted by
> **provisioning** (`SESSenderStrategy#provision_dns_records`), not by validation —
> that work belongs to this SES-promotion effort, not #2833. The earlier #2833
> premise (a region-parameterized validation strategy that *generated* regional
> records) predates the refactor to reading provisioned records and no longer
> applies.
>
> Practical guidance is unchanged: set `EMAILER_REGION`/`AWS_REGION` to the
> intended region. This two-knob region surface is transitional and expected to
> consolidate, so prefer driving region from the provisioning side and treat
> `CUSTOM_MAIL_SES_REGION` as a no-op for now.

## Credentials

The SES API client uses standard AWS credentials, resolved (per
`Mailer.build_provider_config`) from the emailer config with fallback to the
AWS SDK environment variables:

```bash
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

(When `SMTP_USERNAME` / `SMTP_PASSWORD` are left empty, the resolver falls back
to `AWS_ACCESS_KEY_ID` / `AWS_SECRET_ACCESS_KEY`.)

The IAM principal needs, at minimum:

| Action | Why |
|---|---|
| `ses:CreateEmailIdentity` | Register the sender domain identity |
| `ses:GetEmailIdentity` | Read DKIM tokens and verification status |
| `ses:DeleteEmailIdentity` | Tear the identity down on sender-config removal |
| `ses:SendEmail` | Only if SES is also the delivery transport (`EMAILER_MODE=ses`) |

## Domain-level lifecycle

### 1. Provision

`ProvisionSenderDomain` → `SESSenderStrategy#provision_dns_records` calls
`CreateEmailIdentity` (or `GetEmailIdentity` if the identity already exists) and
returns three DKIM CNAME records, relative to the sender domain:

```
<token1>._domainkey  CNAME  <token1>.dkim.amazonses.com
<token2>._domainkey  CNAME  <token2>.dkim.amazonses.com
<token3>._domainkey  CNAME  <token3>.dkim.amazonses.com
```

The tokens are SES-assigned per domain and stored on the `MailerConfig`
(`provider_dns_data` for the raw response, `dns_records` for the normalized
records shown to the customer).

### 2. Verify

`ValidateSenderDomain` → `SesValidation` reads the **provisioned** records from
`mailer_config.dns_records` (never hardcoded placeholders) and performs live DNS
lookups. Provider-side status is also available via
`SESSenderStrategy#check_provider_verification_status`, which maps the SES DKIM
status (`SUCCESS` / `PENDING` / `FAILED` / `TEMPORARY_FAILURE` / `NOT_STARTED`)
to a human-readable message.

### 3. Delete

Removing the sender config dispatches to
`SESSenderStrategy#delete_sender_identity`, which calls `DeleteEmailIdentity`.
A missing identity is treated as already-deleted (idempotent teardown). This is
covered by the multi-provider deletion dispatch
([#3369](https://github.com/onetimesecret/onetimesecret/pull/3369)).

## Data residency

Choose the SES region to match the data-residency requirements of the
installation and its customers. SES sender identities, DKIM key material, and
sending metadata live in the region you provision against. Notable regions for
data-residency-sensitive deployments:

| Region | Location |
|---|---|
| `ca-central-1` | Canada (Central) |
| `ap-southeast-2` | Asia Pacific (Sydney) |
| `eu-west-1` | Europe (Ireland) |
| `us-east-1` | US East (N. Virginia) — default |

Set both region knobs to the chosen region:

```bash
EMAILER_REGION=ca-central-1
CUSTOM_MAIL_SES_REGION=ca-central-1
```

Note that SES is not available in every AWS region; confirm SES availability for
your target region before configuring it.

## Minimal example

SMTP transport for delivery, SES for domain-level sender provisioning, pinned to
Canada Central for data residency:

```bash
EMAILER_MODE=smtp
CUSTOM_MAIL_PROVIDER=ses
EMAILER_REGION=ca-central-1
CUSTOM_MAIL_SES_REGION=ca-central-1
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
ORGS_CUSTOM_MAIL_ENABLED=true
```

## Troubleshooting

- DNS verification failures (records not propagating, value mismatches): see
  [`docs/runbooks/dns-validation-failures.md`](../runbooks/dns-validation-failures.md).
- Provisioning fails immediately with an invalid-region error: confirm
  `EMAILER_REGION` is a real region (see the gotcha above), not the `smtp`
  placeholder.
- `check_provider_verification_status` returns `not_found`: the identity was
  never created (or was deleted) — re-run provisioning.

## Key files

| File | Role |
|---|---|
| `lib/onetime/mail/sender_strategies/ses_sender_strategy.rb` | Provision / verify-status / delete via `aws-sdk-sesv2` |
| `lib/onetime/domain_validation/sender_strategies/ses_validation.rb` | DNS validation from provisioned records |
| `lib/onetime/mail/delivery/ses.rb` | SES delivery backend (only when `EMAILER_MODE=ses`) |
| `lib/onetime/domain_validation/sender_strategies/provider_config.rb` | `email_providers.ses` config + region validation |
| `etc/defaults/config.defaults.yaml` | `emailer.sender_provider`, `email_providers.ses.*` |
