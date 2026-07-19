---
title: SendGrid Sender Domain Provider
type: reference
status: supported
updated: 2026-07-18
summary: Configuring Twilio SendGrid as the provider for the domain-level custom sender flow (Domain Authentication with automatic_security CNAMEs, provider-side validation, teardown), including credential resolution and current limitations.
---

Twilio SendGrid is a supported provider for the **domain-level custom sender
flow**: when an organization enables a custom sender identity on one of its
custom domains, the platform calls SendGrid's Domain Authentication API
(historically "whitelabel") on the organization's behalf, returns the CNAME
records the customer must add at their registrar, verifies those records, and
tears the domain authentication down when the sender config is removed.

This document covers the SendGrid-specific configuration. For the
provider-agnostic design (the three layers, who picks the provider, how
credentials flow), see [`custom-mail-sender.md`](./custom-mail-sender.md).
Siblings: [AWS SES](./custom-mail-sender-ses.md) (supported),
[MailChannels](./custom-mail-sender-mailchannels.md) (research).

## Scope

SendGrid here is the **sender-domain provisioning provider**, selected once per
installation. It is not a per-customer choice — the operator configures the
provider, and the customer's only decision is "do I want emails from my domain
to use my from-address/reply-to?" (see *Customer Decision Surface* in the
architecture overview).

The work this provider enables is the **domain-level lifecycle**:

```
enable custom sender → create domain authentication → show 3 CNAMEs
                     → customer adds DNS → validate → (later) delete
```

## Selecting SendGrid

```bash
CUSTOM_MAIL_PROVIDER=sendgrid
```

As with SES, `CUSTOM_MAIL_PROVIDER` (config: `emailer.sender_provider`)
decouples *domain provisioning* from the *sending transport* (`EMAILER_MODE`).
You can run SMTP for outbound delivery while provisioning sender domains
through SendGrid. If `CUSTOM_MAIL_PROVIDER` is unset, the provisioning provider
falls back to `EMAILER_MODE`.

## Credentials

Everything — provision, validate, delete, and (when SendGrid is also the
transport) delivery — authenticates with a single SendGrid API key sent as
`Authorization: Bearer <key>`. `Mailer.provider_credentials('sendgrid')`
resolves it in this order (first non-empty wins):

| Priority | Source | Notes |
|---|---|---|
| 1 | `emailer.sendgrid_api_key` (config) | Not present in `config.defaults.yaml` — only set if your own config defines it |
| 2 | `emailer.pass` (`SMTP_PASSWORD`) | Intended for `EMAILER_MODE=sendgrid` installs that put the key in the password slot |
| 3 | `SENDGRID_API_KEY` env var | Fallback |

> **Caution — SMTP collision:** unlike SES, SendGrid has **no dedicated
> `CUSTOM_MAIL_SENDGRID_API_KEY` override** and no credential entry under
> `email_providers.sendgrid`. If you run authenticated SMTP for delivery
> (`EMAILER_MODE=smtp` with `SMTP_PASSWORD` set), `emailer.pass` outranks the
> `SENDGRID_API_KEY` env var and your **SMTP password is used as the SendGrid
> API key**, producing opaque HTTP 401s from the SendGrid API. Work around it
> by setting `sendgrid_api_key` in your emailer config (e.g.
> `sendgrid_api_key: <%= ENV['SENDGRID_API_KEY'] %>`). This is the same class
> of collision the SES provider fixed with its `CUSTOM_MAIL_SES_*` vars.

The API key must be a Full Access key, or a restricted key with the **Domain
Authentication (`whitelabel`) scopes** — create, read, and delete at minimum
(read covers the list + validate calls). Add the Mail Send scope only if
SendGrid is also the delivery transport (`EMAILER_MODE=sendgrid`).

Both the sender strategy and the delivery backend call the API with plain
`Net::HTTP` — the `sendgrid-ruby` gem in the Gemfile (`require: false`) is
**not used** by either path. That is deliberate (simpler dependencies and error
handling per the note in `delivery/sendgrid.rb`) and prudent: the gem's last
release is 6.7.0 (December 2023) and it has been effectively dormant since.

## DMARC alignment (automatic security)

The strategy always creates the domain with `automatic_security: true`, so
SendGrid manages SPF, DKIM keys, and DKIM rotation behind **three CNAMEs** —
the CNAME-delegated model, same family as Lettermint, in contrast to SES's
publish-it-yourself MX + TXT:

| | SendGrid (`automatic_security`) | Lettermint | SES (custom MAIL FROM) | MailChannels (research) |
|---|---|---|---|---|
| DKIM | 2 CNAMEs (`s1`/`s2._domainkey`) | CNAME selectors | 3 CNAMEs (tokens) | TXT (managed key) |
| SPF / envelope sender | 1 mail CNAME (`em####.<domain>`) | 1 CNAME (`lm-bounces.<domain>`) | MX + SPF TXT on `mail.<domain>` | SPF TXT on **root** domain |
| Who maintains SPF | SendGrid | Lettermint | customer publishes it | customer publishes it |

The mail CNAME is the return-path host: SendGrid sets the envelope sender
(Return-Path) to `em####.<domain>`, so SPF authenticates against a subdomain of
the sender domain and aligns under DMARC's relaxed rules — the direct
equivalent of Lettermint's `lm-bounces` CNAME and SES's custom MAIL FROM. With
DKIM aligning too, DMARC passes via both paths. Domain authentication is also
what removes the "via sendgrid.net" annotation recipients otherwise see.

With `automatic_security: false` SendGrid instead returns 2 TXT + 1 MX for
manual key management; the strategy never requests this mode.

Unlike the SES strategy, the SendGrid strategy does **not** emit an advisory
`_dmarc` TXT record — `build_dns_records` maps exactly what SendGrid returns.
(The validation layer would classify a DMARC record correctly if one ever
appeared in the provisioned set.)

## Domain-level lifecycle

### 1. Provision

`ProvisionSenderDomain` → `SendGridSenderStrategy#provision_dns_records`:

1. Extracts the domain from `mailer_config.from_address`.
2. `POST /v3/whitelabel/domains` with body
   `{ "domain": "<domain>", "automatic_security": true }`. No `subdomain`,
   `custom_dkim_selector`, or `region` is passed — SendGrid assigns the
   branding subdomain (`em####`) and default selectors (`s1`/`s2`) itself.
3. `build_dns_records` normalizes the response's `dns` object (`mail_cname`,
   `dkim1`, `dkim2`) to the standard `Array<Hash>` shape with `type` / `name` /
   `value` plus a `purpose` key carrying the SendGrid record label.

For `example.com` (SendGrid user id 1446226) the three required records look
like:

```
em1234.example.com         CNAME  u1446226.wl123.sendgrid.net             (mail_cname — return-path/SPF)
s1._domainkey.example.com  CNAME  s1.domainkey.u1446226.wl123.sendgrid.net (dkim1)
s2._domainkey.example.com  CNAME  s2.domainkey.u1446226.wl123.sendgrid.net (dkim2)
```

The result also stores `provider_data` (`domain_id`, `subdomain`, the raw
`dns` hash, `valid`) alongside the normalized `dns_records` on the
`MailerConfig`; the records are read back verbatim at verification. A missing
or empty API key fails fast (`missing_api_key`) before any HTTP call.

### 2. Verify

Two independent checks, as with every provider:

- **DNS propagation** — `ValidateSenderDomain` → `SendgridValidation` reads the
  provisioned records from `mailer_config.dns_records` (never hardcoded
  selectors; returns an empty set with an error log if nothing was
  provisioned) and runs live DNS lookups.
- **Provider-side validation** —
  `SendGridSenderStrategy#check_provider_verification_status` looks up the
  domain id (from `credentials['domain_id']` if present, else by paginating
  `GET /v3/whitelabel/domains?limit=50&offset=...` and matching on the domain
  name), then `POST /v3/whitelabel/domains/{id}/validate`. SendGrid checks all
  records on its side; the strategy reports `verified` when the domain's
  `valid` flag is true or every entry in `validation_results` is valid, else
  `pending`. Per-record results are surfaced in `:details`. Other statuses:
  `not_found` (no matching domain authentication), `invalid` (bad
  from_address), `error`.

### 3. Delete

Removing the sender config dispatches to
`SendGridSenderStrategy#delete_sender_identity`: resolve the domain id (same
lookup as verify), then `DELETE /v3/whitelabel/domains/{id}`. Note this is
**not idempotent the way SES teardown is**: if the domain authentication no
longer exists, the result is `deleted: false` with "Domain authentication not
found" rather than treating it as already-deleted.

## Configuration surface

`email_providers.sendgrid` in `config.defaults.yaml` defines `subdomain`
(default `em`, env `CUSTOM_MAIL_SENDGRID_SUBDOMAIN`), `dkim_selectors`
(`s1`/`s2`), and `spf_include` (`sendgrid.net`), with matching defaults in
`ProviderConfig`. **These are currently inert for this flow**: the strategy
does not pass a subdomain or selectors to the API (SendGrid assigns its own),
and validation reads provisioned records rather than composing them from
config. Treat them as documentation of SendGrid's defaults, not as knobs.

Minimal working example (SMTP transport, SendGrid provisioning):

```bash
EMAILER_MODE=smtp
CUSTOM_MAIL_PROVIDER=sendgrid
SENDGRID_API_KEY=SG.xxxxxxxx        # see SMTP-collision caution above if SMTP_PASSWORD is set
ORGS_CUSTOM_MAIL_ENABLED=true
```

## Limitations and considerations

- **EU regional subusers are unsupported.** The strategy hardcodes
  `https://api.sendgrid.com/v3`; EU regional subusers require
  `api.eu.sendgrid.com` and the `region: eu` request field, neither of which
  the strategy sends.
- **Subusers / `on-behalf-of`** are not used; domains are authenticated
  directly on the account the API key belongs to. SendGrid allows up to 3,000
  authenticated domains per user, so a single platform account scales fine.
- **Link branding is separate.** Domain authentication covers sending identity
  (DKIM/SPF, removing "via sendgrid.net"); click/open-tracking links are a
  different SendGrid feature (`/v3/whitelabel/links`) that the platform does
  not provision.
- **Domain matching is exact-string.** `find_domain_id` matches
  `d['domain'] == domain`, so a domain authenticated for `mail.example.com`
  will not be found for `example.com` or vice versa.

## Troubleshooting

- DNS verification failures (propagation, value mismatches, registrars
  appending the zone to CNAME hosts): see
  [`docs/runbooks/dns-validation-failures.md`](../runbooks/dns-validation-failures.md).
- HTTP 401/403 from provisioning: wrong or under-scoped API key — check the
  Domain Authentication (whitelabel) scopes, and rule out the SMTP-collision
  case where `SMTP_PASSWORD` is being used as the key.
- `check_provider_verification_status` returns `not_found`: the domain
  authentication was deleted, was created under a different account/subuser,
  or the from-address domain doesn't exactly match — re-run provisioning.
- Validate returns `pending` with some records valid: inspect `:details`
  (SendGrid's per-record `validation_results`) to see which CNAME is wrong.
- Delete reports "Domain authentication not found": already removed on the
  SendGrid side; safe to treat as done, but the strategy reports it as a
  failure (see lifecycle note above).

## Key files

| File | Role |
|---|---|
| `lib/onetime/mail/sender_strategies/sendgrid_sender_strategy.rb` | Provision / validate / delete via raw `Net::HTTP` against `api.sendgrid.com/v3` |
| `lib/onetime/domain_validation/sender_strategies/sendgrid_validation.rb` | DNS validation from provisioned records (no hardcoded fallback) |
| `lib/onetime/mail/delivery/sendgrid.rb` | Delivery backend via `/v3/mail/send` (only when `EMAILER_MODE=sendgrid`) |
| `lib/onetime/domain_validation/sender_strategies/provider_config.rb` | `email_providers.sendgrid` defaults (currently inert for this flow) |
| `lib/onetime/mail/mailer.rb` | `provider_credentials('sendgrid')` — api_key resolution (see SMTP-collision caution) |
| `etc/defaults/config.defaults.yaml` | `emailer.sender_provider`, `email_providers.sendgrid.*` |
