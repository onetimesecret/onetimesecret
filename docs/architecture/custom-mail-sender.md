# Custom Mail Sender Architecture

> Provider-specific setup guides: [AWS SES](./custom-mail-sender-ses.md).

## Overview

The custom mail sender system lets customers send secret-link emails from their own domain identity (from-address, reply-to) while the platform handles all provider integration transparently.

## Three Layers

### Delivery Layer

The platform operator configures one global mailer backend (SES, SendGrid, Lettermint, SMTP) via `OT.conf['emailer']`. Every email goes through that single backend. `Mailer.resolve_backend` ignores the `sender_config` argument entirely and returns the global `delivery_backend`. The underscore-prefixed parameter makes this explicit:

```ruby
# lib/onetime/mail/mailer.rb
def resolve_backend(_sender_config)
  delivery_backend
end
```

### Sender Identity Layer

When a customer enables custom sender on their domain, the system uses their `from_address` and `reply_to` in the email envelope, but the email still flows through the platform's global backend. The `provider` field on `MailerConfig` matches the platform's mailer -- it is not a customer choice, it is inherited context.

```ruby
# lib/onetime/mail/mailer.rb
def deliver_template(template, sender_config: nil)
  backend    = resolve_backend(sender_config)
  use_sender = sender_config&.enabled? && sender_config.verified?

  email = template.to_email(
    from: use_sender ? sender_config.from_address : from_address,
    reply_to: use_sender && sender_config.reply_to ? sender_config.reply_to : reply_to_address(template),
  )
  backend.deliver(email)
end
```

### Provisioning Layer

`ProvisionSenderDomain` reads `mailer_config.provider` to select the right sender strategy, then loads *platform* credentials via `Mailer.provider_credentials(provider)`. The customer never sees or provides API keys for the mail provider. They flip "use custom sender" on, provide a from-address, and the system provisions DNS records through whatever provider the platform runs.

## Customer Decision Surface

The customer's choice is: "Do I want emails from my domain to show my from-address and reply-to?"

The plumbing underneath -- which provider's API to call, what DNS record shapes to expect, where the credentials come from -- is entirely determined by the platform's global config. The customer gets visibility into the DNS records they need to add (the output), but not into which provider generated them (the mechanism).

## Environment Congruence

Different deployments can run different global mailers (e.g. one environment uses SES, another uses Lettermint). Whatever the global mailer is, that same provider is automatically used for customer sender domain provisioning and verification. The sender strategy selection flows from the platform config, not from any per-customer setting.

## Provider Comparison

Every provisioning provider produces the same outcome — DKIM **and** SPF aligned to the customer's domain so DMARC passes via both paths — but each exposes it through different APIs and DNS record shapes. If you already know one provider, this maps it onto the other; if you're starting from scratch, it's the quickest way to see the shape of the problem.

| | AWS SES | Lettermint |
|---|---|---|
| Provision API | `CreateEmailIdentity` + `PutEmailIdentityMailFromAttributes` | Team API `POST /domains` |
| DKIM records | 3 CNAMEs (`<token>._domainkey.<domain>` → `<token>.dkim.amazonses.com`) | CNAME selectors (`<sel>._domainkey.<domain>` → `<sel>.dkim.lettermint.com`) |
| SPF / envelope sender | custom MAIL FROM on `mail.<domain>`: an **MX + SPF TXT** the customer publishes directly | **one Return-Path CNAME** (`lm-bounces.<domain>`); Lettermint manages the SPF record on its side |
| Verification status | `GetEmailIdentity` (DKIM + MAIL FROM status) | `GET /domains/:id` (+ `verify` trigger) |
| Teardown | `DeleteEmailIdentity` | `DELETE /domains/:id` |
| Strategy class | `SESSenderStrategy` | `LettermintSenderStrategy` |

The one mechanism difference worth internalizing: **SES's custom MAIL FROM and Lettermint's Return-Path CNAME are equivalent** — both set the envelope sender to a subdomain of the sender domain so SPF aligns under DMARC's relaxed rules. Lettermint delegates SPF via a single CNAME (it publishes the SPF record itself); SES has no CNAME-delegated SPF, so the customer publishes an MX (to the regional `feedback-smtp.<region>.amazonses.com` endpoint) plus an SPF TXT directly. SendGrid (`automatic_security`) is CNAME-based like Lettermint. See the [SES guide](./custom-mail-sender-ses.md#dmarc-alignment-why-custom-mail-from) for the full DMARC alignment table.

Validation is identical across providers: each reads the provisioned `dns_records` and runs live DNS lookups — no provider API call (see `ValidateSenderDomain`). Region is purely a provisioning concern (it selects SES's DKIM region and MAIL FROM endpoint); it plays no part in validation.

## Key Files

| File | Role |
|------|------|
| `lib/onetime/mail/mailer.rb` | Global delivery backend, `resolve_backend`, `provider_credentials` |
| `lib/onetime/mail/sender_strategies.rb` | Factory for provider-specific sender strategies |
| `lib/onetime/mail/sender_strategies/base_sender_strategy.rb` | Strategy interface (provision, verify, cleanup) |
| `lib/onetime/operations/provision_sender_domain.rb` | Orchestrates provisioning with platform credentials |
| `lib/onetime/operations/validate_sender_domain.rb` | DNS verification via provider strategy |
| `lib/onetime/models/custom_domain/mailer_config.rb` | Per-domain sender config model (from_address, dns_records, verification state) |

## DNS Record Normalization

All strategies normalize their DNS records to a common `Array<Hash>` shape before storage:

```ruby
[{ type: 'CNAME', name: 'selector._domainkey.example.com', value: 'selector.dkim.provider.com' }, ...]
```

This normalization happens inside each strategy (SES: `build_dkim_records`, SendGrid: `build_dns_records`, Lettermint: `normalize_dns_records`). The model's `provisioned?` and `required_dns_records` methods depend on this consistent Array shape.
