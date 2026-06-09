# docs/architecture/custom-mail-sender-ses.md
---
title: AWS SES Sender Domain Provider
type: reference
status: supported
updated: 2026-06-08
summary: Configuring AWS SES as the provider for the domain-level custom sender flow (DKIM + custom MAIL FROM provisioning, verification, teardown) including region selection and data-residency.
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

## Region

The SES provisioning region is set with its own dedicated variable,
**independent of the install-level transactional mailer**:

```bash
CUSTOM_MAIL_SES_REGION=ca-central-1   # default: us-east-1
```

This is the deliberate point of `CUSTOM_MAIL_PROVIDER`: sender-domain
provisioning is decoupled from `EMAILER_MODE` / `EMAILER_REGION` (which configure
the install's own transactional email transport). An operator can run, say, SMTP
for transactional mail and SES for sender-domain provisioning, each with its own
region. `CUSTOM_MAIL_SES_REGION` maps to `email_providers.ses.region` in
config and feeds the SESv2 API client used for provisioning, verification, and
teardown via `Mailer.provider_credentials('ses')`.

| Setting | Configures | Source |
|---|---|---|
| `CUSTOM_MAIL_SES_REGION` | SES **sender-domain provisioning** API client | `email_providers.ses.region` → `provider_credentials('ses')` |
| `EMAILER_REGION` (falls back to `AWS_REGION`) | The install's **transactional mailer** (only when `EMAILER_MODE=ses`) | `emailer.region` → delivery backend |

> **Why a dedicated var?** Earlier, the SES provisioning client pulled its region
> from `emailer.region` (`EMAILER_REGION`, which defaults to the placeholder
> `smtp`), coupling provisioning to the transactional transport. That is fixed:
> `provider_credentials('ses')` now sources region from `email_providers.ses`, so
> `EMAILER_REGION` no longer leaks into SES provisioning.

> **On validation and region:** the validation strategies (SES, SendGrid,
> Lettermint) are region-agnostic — each reads the already-provisioned records
> from `mailer_config.dns_records` and runs live DNS lookups against them, so
> there is nothing for a region to influence at validation time. Region is purely
> a **provisioning / SES-API** concern. (This is why
> [#2833](https://github.com/onetimesecret/onetimesecret/issues/2833) — threading
> a region through `ValidateSenderDomain` — is not needed: the region belongs on
> the provisioning side, which is exactly what `CUSTOM_MAIL_SES_REGION`
> drives.) Any region-specific *records* (e.g. the
> `feedback-smtp.<region>.amazonses.com` MAIL FROM MX + SPF) are emitted by
> provisioning (`SESSenderStrategy#provision_dns_records`) and are then stored on
> the `MailerConfig` and read back verbatim at verification.

## Credentials

The SES API client uses standard AWS credentials. To keep sender-domain
provisioning independent of the install's SMTP/transactional mailer, the key
pair is resolved with this precedence (highest first):

| Credential | 1st — dedicated | 2nd — AWS SDK env | 3rd — emailer config |
|---|---|---|---|
| Access key | `CUSTOM_MAIL_SES_ACCESS_KEY_ID` | `AWS_ACCESS_KEY_ID` | `SMTP_USERNAME` (emailer `user`) |
| Secret key | `CUSTOM_MAIL_SES_SECRET_ACCESS_KEY` | `AWS_SECRET_ACCESS_KEY` | `SMTP_PASSWORD` (emailer `pass`) |

The dedicated `CUSTOM_MAIL_SES_*` vars (or the `AWS_*` vars they fall back to)
flow through `email_providers.ses` and **override** the emailer-derived values in
`Mailer.provider_credentials('ses')`. The emailer `user`/`pass` are used only as
a last resort — i.e. when SES is also the delivery backend (`EMAILER_MODE=ses`)
and neither the dedicated nor the `AWS_*` vars are set.

```bash
# Either set works; the first non-empty source wins:
CUSTOM_MAIL_SES_ACCESS_KEY_ID=AKIA...
CUSTOM_MAIL_SES_SECRET_ACCESS_KEY=...
# or the standard AWS SDK vars:
AWS_ACCESS_KEY_ID=AKIA...
AWS_SECRET_ACCESS_KEY=...
```

> **Why the precedence matters (SMTP collision):** if you run authenticated SMTP
> for transactional delivery (`EMAILER_MODE=smtp`), `SMTP_USERNAME` /
> `SMTP_PASSWORD` populate the emailer `user`/`pass`. If those were the first
> source, the SES API client would silently use your SMTP login as the AWS key
> pair → opaque `InvalidClientTokenId` failures. Sourcing SES credentials from
> `CUSTOM_MAIL_SES_*` / `AWS_*` (the two rows above) keeps the SMTP login out of
> the SES client.

> **Caution:** these must be IAM access keys valid for the **SESv2 API**
> (`CreateEmailIdentity` etc.). SES *SMTP* credentials are a different artifact
> and will not authenticate the API calls, so if you run SES-over-SMTP for
> delivery, don't assume the SMTP user/pass double as API keys for provisioning.

The IAM principal needs, at minimum:

| Action | Why |
|---|---|
| `ses:CreateEmailIdentity` | Register the sender domain identity |
| `ses:PutEmailIdentityMailFromAttributes` | Configure the custom MAIL FROM domain (SPF alignment, bounce handling) |
| `ses:GetEmailIdentity` | Read DKIM tokens, MAIL FROM status, and verification status |
| `ses:DeleteEmailIdentity` | Tear the identity down on sender-config removal |
| `ses:SendEmail` | Only if SES is also the delivery transport (`EMAILER_MODE=ses`) |

## DMARC alignment (why custom MAIL FROM)

Custom MAIL FROM is what gives SES **SPF alignment**, and it is the direct
equivalent of Lettermint's Return-Path CNAME — same mechanism, different record
shape. Lettermint folds it into a single `lm-bounces.<domain>` CNAME (and
manages the SPF record on its side); SES instead exposes it as an MX + SPF TXT
that you publish on `mail.<domain>`. Both set the envelope sender (Return-Path)
to a subdomain of the sender domain, so SPF authenticates against *your* domain.

| | Lettermint | SES *with* MAIL FROM | SES *without* MAIL FROM |
|---|---|---|---|
| Records added | one `lm-bounces.<domain>` CNAME | `mail.<domain>` MX + SPF TXT | DKIM CNAMEs only |
| SPF passes | ✅ your subdomain | ✅ `mail.<domain>` | ✅ but against `amazonses.com` |
| SPF aligns with `From:` | ✅ relaxed | ✅ relaxed | ❌ |
| DKIM passes + aligns | ✅ strict | ✅ strict | ✅ strict |
| DMARC passes via | SPF **and** DKIM | SPF **and** DKIM | DKIM only |

Provisioning configures custom MAIL FROM by default, so DMARC passes via both
SPF and DKIM rather than DKIM alone — i.e. no single point of failure. (This is
also why the MAIL FROM MX is region-specific: it points at the regional SES
feedback endpoint selected by `CUSTOM_MAIL_SES_REGION`.)

## Domain-level lifecycle

### 1. Provision

`ProvisionSenderDomain` → `SESSenderStrategy#provision_dns_records`:

1. Calls `CreateEmailIdentity` (or `GetEmailIdentity` if the identity already
   exists) to register the domain and obtain its DKIM tokens.
2. Calls `PutEmailIdentityMailFromAttributes` to set a custom MAIL FROM
   subdomain (`mail.<domain>`, with `behavior_on_mx_failure: USE_DEFAULT_VALUE`),
   so SPF aligns to the sender domain and bounces are handled on the customer's
   own domain instead of the shared `amazonses.com` default.

It returns five **fully-qualified** DNS records — three DKIM CNAMEs plus the
MAIL FROM MX and SPF TXT:

```
<token1>._domainkey.<domain>  CNAME  <token1>.dkim.amazonses.com
<token2>._domainkey.<domain>  CNAME  <token2>.dkim.amazonses.com
<token3>._domainkey.<domain>  CNAME  <token3>.dkim.amazonses.com
mail.<domain>                 MX     feedback-smtp.<region>.amazonses.com   (priority 10)
mail.<domain>                 TXT    v=spf1 include:amazonses.com ~all
```

The DKIM tokens are SES-assigned per domain; the MAIL FROM MX endpoint is
region-specific (driven by `CUSTOM_MAIL_SES_REGION`). All records are stored on
the `MailerConfig` (`provider_dns_data` for the raw response, `dns_records` for
the normalized records shown to the customer) and read back verbatim at
verification. If SES rejects the MAIL FROM configuration (e.g. the region does
not support it), provisioning still succeeds with the DKIM records and the
MAIL FROM records are omitted, rather than asking the customer to add records
SES will not honor.

### MAIL FROM status lifecycle

DKIM verification and MAIL FROM configuration are **independent** in SES. An
identity can have DKIM `SUCCESS` while MAIL FROM is in any of these states:

| MAIL FROM status | Meaning | What happened |
|---|---|---|
| `NOT_STARTED` | `PutEmailIdentityMailFromAttributes` was never called | Identity created without MAIL FROM — DKIM works, but SPF authenticates against `amazonses.com` instead of the sender domain |
| `PENDING` | MAIL FROM configured, DNS propagation pending | `PutEmailIdentityMailFromAttributes` succeeded; SES is waiting for the MX and SPF TXT records on `mail.<domain>` |
| `SUCCESS` | MAIL FROM fully verified | SES detected the MX and SPF records — SPF now aligns to the sender domain under DMARC |
| `FAILED` | MX/SPF records missing or incorrect | SES checked and could not verify — re-check DNS records at the registrar |

The provisioning flow always calls `PutEmailIdentityMailFromAttributes`, so after
a successful provision the MAIL FROM status should be `PENDING` (never
`NOT_STARTED`). If the API call is rejected (e.g. unsupported region),
`mail_from_domain` is nil in the provisioning result and the success message
notes "DKIM only" — the identity still works for sending but without SPF
alignment.

`check_provider_verification_status` surfaces both DKIM and MAIL FROM status in
the `:details` hash (`mail_from_domain` and `mail_from_status`), so callers can
distinguish "DKIM verified, MAIL FROM pending" from "everything verified."

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

Set the provisioning region to the chosen region:

```bash
CUSTOM_MAIL_SES_REGION=ca-central-1
```

Note that SES is not available in every AWS region; confirm SES availability for
your target region before configuring it.

## Minimal example

SMTP transport for the install's transactional email, SES for domain-level
sender provisioning, pinned to Canada Central for data residency. Both the SES
region **and** credentials are set independently of the transactional mailer, so
the SES API client is unaffected by the SMTP login used for delivery:

```bash
EMAILER_MODE=smtp
SMTP_USERNAME=smtp-login          # used for SMTP delivery only
SMTP_PASSWORD=smtp-secret         # NOT used as the SES AWS key
CUSTOM_MAIL_PROVIDER=ses
CUSTOM_MAIL_SES_REGION=ca-central-1
# SES API credentials (dedicated knob, or set AWS_ACCESS_KEY_ID/AWS_SECRET_ACCESS_KEY):
CUSTOM_MAIL_SES_ACCESS_KEY_ID=AKIA...
CUSTOM_MAIL_SES_SECRET_ACCESS_KEY=...
ORGS_CUSTOM_MAIL_ENABLED=true
```

Here `CUSTOM_MAIL_SES_ACCESS_KEY_ID` / `CUSTOM_MAIL_SES_SECRET_ACCESS_KEY` (or
the `AWS_*` equivalents) take precedence, so the SES provisioning client uses the
AWS key pair — never the SMTP login — even though delivery runs over SMTP.

## Troubleshooting

- DNS verification failures (records not propagating, value mismatches): see
  [`docs/runbooks/dns-validation-failures.md`](../runbooks/dns-validation-failures.md).
- Provisioning fails immediately with an invalid-region error: confirm
  `CUSTOM_MAIL_SES_REGION` is a valid AWS region where SES is available
  (it defaults to `us-east-1` if unset).
- `check_provider_verification_status` returns `not_found`: the identity was
  never created (or was deleted) — re-run provisioning.

## Key files

| File | Role |
|---|---|
| `lib/onetime/mail/sender_strategies/ses_sender_strategy.rb` | Provision / verify-status / delete via `aws-sdk-sesv2` |
| `lib/onetime/domain_validation/sender_strategies/ses_validation.rb` | DNS validation from provisioned records |
| `lib/onetime/mail/delivery/ses.rb` | SES delivery backend (only when `EMAILER_MODE=ses`) |
| `lib/onetime/domain_validation/sender_strategies/provider_config.rb` | `email_providers.ses` config + region validation |
| `lib/onetime/mail/mailer.rb` | `provider_credentials('ses')` sources region from `email_providers.ses` (decoupled from `EMAILER_REGION`) |
| `etc/defaults/config.defaults.yaml` | `emailer.sender_provider`, `email_providers.ses.*` |
