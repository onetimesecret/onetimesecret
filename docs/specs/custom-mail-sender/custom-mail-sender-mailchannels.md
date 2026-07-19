---
title: MailChannels Sender Domain Provider (Research)
type: research
status: draft
updated: 2026-07-18
summary: Implementation research for adding MailChannels as a custom sender domain provider — API surface, Ruby library plan (self-maintained, modeled on our Lettermint gem), and integration into the sender strategy / DNS validation pipeline.
---

MailChannels (Vancouver, BC — the "Canada mail" provider) as a third sender-domain
provider alongside AWS SES and Lettermint. This doc collates everything needed to
(a) build a Ruby client library and (b) wire it into the custom sender domain
provisioning/validation flow described in
[`custom-mail-sender.md`](./custom-mail-sender.md).

**Bottom line:** there is no usable Ruby library — we build our own, modeled on
our Lettermint gem. The API maps cleanly onto the `BaseSenderStrategy` interface,
with one structural difference that affects DNS validation: MailChannels has **no
domain resource to provision**. Provisioning is "create a managed DKIM key +
compose two TXT records ourselves," and the SPF record lands on the customer's
**root domain**, which forces merge-aware SPF validation instead of exact-match.

## 1. MailChannels Email API overview

Single REST API, single auth scheme — no Lettermint-style Sending/Team API split.

| | Value |
|---|---|
| Base URL | `https://api.mailchannels.net/tx/v1` |
| Auth | `X-Api-Key: <key>` header on every request (created in Console → Settings → API Keys, `api` scope) |
| Spec | OpenAPI 3.0, v1.4.0: `https://docs.mailchannels.com/email-api/api-reference/openapi.yaml` |
| Docs index | `https://docs.mailchannels.com/llms.txt` (LLM-friendly, every page available as `.md`) |
| Official SDKs | Node (`mailchannels-sdk`), Python (`mailchannels`), PHP — **no Ruby** |
| Max message size | 30 MB including attachments |

Endpoints relevant to us:

| Endpoint | Purpose |
|---|---|
| `POST /send` (and `?dry-run=true`) | Send email; dry-run returns rendered message without sending |
| `POST /send-async` | Queue send, returns request ID immediately |
| `POST /domains/{domain}/dkim-keys` | Create MailChannels-managed DKIM key pair; returns public key + DNS TXT record |
| `GET /domains/{domain}/dkim-keys` | Retrieve keys by domain, optional `selector` filter |
| `PATCH /domains/{domain}/dkim-keys/{selector}` | Update key status: `revoked` / `retired` / `rotated` |
| `POST /domains/{domain}/dkim-keys/{selector}/rotate` | Rotate: old key `rotated` (3-day signing grace, auto-`retired` at 2 weeks), new key created |
| `POST /check-domain` | Provider-side verification: DKIM + SPF + Domain Lockdown + sender-domain MX/A verdicts |
| Webhooks (`/webhook` group) | Enroll endpoint, event types (delivered, hard/soft-bounced, complained, unsubscribed), signing-key retrieval, batch resend |
| Sub-accounts, suppressions, metrics, usage | Not needed for v1; sub-accounts noteworthy for future tenant isolation (100K+ plans only) |

### Sending model

`POST /send` body (SendGrid-style):

```json
{
  "personalizations": [{ "to": [{ "email": "r@example.net" }] }],
  "from": { "email": "noreply@customer.com", "name": "Customer" },
  "reply_to": { "email": "support@customer.com" },
  "subject": "…",
  "content": [
    { "type": "text/plain", "value": "…" },
    { "type": "text/html", "value": "…" }
  ]
}
```

Returns `202` with `request_id` and per-personalization `results[]` (`message_id`,
`status: sent|failed`, `reason`). `400/403/413/500/502` carry `{ "errors": [...] }`.
Optional fields we care about: `dkim_selector` (choose which managed key signs;
if only one active key exists, signing is automatic), `envelope_from` (override
envelope sender — see §3.3), `headers`, `campaign_id`, `transactional` (default
true — keep it true; non-transactional adds List-Unsubscribe handling).
Mustache templates via `content[].template_type: "mustache"` +
`personalizations[].dynamic_template_data`.

### Sender identity model (replaces "domain provisioning")

Three DNS-visible mechanisms, per sending domain:

1. **Domain Lockdown** (MailChannels-proprietary, required): TXT at
   `_mailchannels.<domain>` binding the domain to our account:
   `v=mc1 auth=<our_account_handle>`. Multiple `auth=`/`senderid=`/`sidw=`
   fields allowed; message passes if any field matches. `senderid=` pins an exact
   sender identity (`<account>|x-authsender|<email>`, visible in the
   `X-MailChannels-SenderId` header); `sidw=` is the same with one `*` wildcard
   in the sender part. Since we are the platform account and the customer's
   domain should only send via us, plain `auth=<our_handle>` is correct and
   simplest. Account handle is shown in the MailChannels dashboard footer.
2. **DKIM**: bring-your-own keys (pass `dkim_domain`/`dkim_selector`/
   `dkim_private_key` per send) **or MailChannels-managed keys** via the
   dkim-keys API. Managed is the right choice — no private key custody on our
   side. `POST /domains/{domain}/dkim-keys` with
   `{ "selector": "mc1", "algorithm": "rsa", "key_length": 2048 }` returns:

   ```json
   {
     "domain": "customer.com", "selector": "mc1", "status": "active",
     "public_key": "MIIBIjANBg…",
     "dkim_dns_records": [
       { "name": "mc1._domainkey.customer.com", "type": "TXT",
         "value": "v=DKIM1; k=rsa; p=MIIBIjANBg…" }
     ]
   }
   ```

   Note: **TXT record with inline public key**, not a CNAME delegation like
   SES/Lettermint. Rotation therefore requires the customer to update DNS
   (managed-rotation flow exists; see endpoint table).
3. **SPF**: add `include:relay.mailchannels.net` to the sending domain's SPF
   TXT. New record: `v=spf1 include:relay.mailchannels.net ~all`; existing
   record: append the include. MailChannels does not pre-check SPF/DKIM/DMARC at
   send time — mail is accepted regardless, deliverability is on us.

Additionally, the sender domain must have **an MX or A record** (their SDNF —
"Sender Domain Not Found" — block). Nearly always already true for a real
customer domain; `check-domain` reports it.

### Provider-side verification: `POST /check-domain`

Request `{ "domain": "customer.com" }` (optional `dkim_settings[]` for BYO keys —
omit and it uses all stored managed keys; optional `sender_id` only if using
`senderid=` lockdown). Response:

```json
{
  "check_results": {
    "dkim": [{ "dkim_domain": "…", "dkim_selector": "mc1",
                "dkim_key_status": "active", "verdict": "passed", "reason": "…" }],
    "spf": { "verdict": "passed", "spfRecord": "v=spf1 …", "reason": "…" },
    "domain_lockdown": { "verdict": "passed", "reason": "…" },
    "sender_domain": { "verdict": "passed", "a": {…}, "mx": {…} }
  },
  "references": ["…docs links when something failed…"]
}
```

DKIM/lockdown/sender-domain verdicts are `passed|failed`; SPF has the full SPF
result range (`passed`, `failed`, `soft failed`, `neutral`, `none`, `temporary
error`, `permanent error`, `unknown`). This endpoint is the direct analogue of
Lettermint's `GET /domains/:id` + `verify` trigger and SES `GetEmailIdentity`,
with the bonus that it re-evaluates live DNS on each call (no separate "trigger
re-check" step needed).

## 2. Ruby library: build our own

RubyGems has exactly one hit for "mailchannels": `mailchannels-worker-rails`
0.1.3 (~2.5K downloads, ActionMailer adapter for the **discontinued** Cloudflare
Workers integration — lockdown-by-`cfid` died Aug 2024). Nothing targets the
current Email API. MailChannels ships official Node/Python/PHP SDKs only. So we
go the Lettermint route: a small Faraday-based gem we maintain.

### Proposed gem: `mailchannels-ruby` (require `mailchannels`)

Mirror the lettermint gem's architecture one-for-one, minus the dual-client
split (MailChannels has one API and one auth header, so a single
`MailChannels::Client` plays both roles that `Lettermint::Client` +
`Lettermint::TeamAPI` play):

```ruby
client = MailChannels::Client.new(
  api_key: 'key',                                   # → X-Api-Key header
  base_url: 'https://api.mailchannels.net/tx/v1',   # default
  timeout: 30,                                      # default
)
```

Resources (v1 scope — what the integration actually calls):

```ruby
# Sending — keep the builder DSL so Delivery::MailChannels reads like
# Delivery::Lettermint:
client.email
  .from('noreply@customer.com', name: 'Customer')
  .to('r@example.net')
  .reply_to('support@customer.com')
  .subject('…')
  .text('…')
  .html('…')
  .deliver                     # POST /send → SendResults
# also: .deliver_async (POST /send-async), .dry_run (POST /send?dry-run=true),
# .dkim_selector('mc1'), .envelope_from('bounces@…'), .header(k, v)

# DKIM keys (the "provisioning" surface):
client.dkim_keys.create('customer.com', selector: 'mc1', algorithm: 'rsa', key_length: 2048)
client.dkim_keys.list('customer.com', selector: 'mc1')   # GET, optional filter
client.dkim_keys.update_status('customer.com', 'mc1', status: 'revoked')
client.dkim_keys.rotate('customer.com', 'mc1', new_selector: 'mc2')

# Verification:
client.check_domain('customer.com')                       # POST /check-domain

# v1.1 (feedback loop parity with lib/onetime/mail/feedback/):
client.webhooks.enroll(url)/list/delete/signing_key/batches
```

Error hierarchy — identical names to the lettermint gem so both
`Delivery#classify_error` and the sender strategy rescue blocks translate
mechanically:

```
MailChannels::Error
├── MailChannels::TimeoutError                  # Faraday timeout
├── MailChannels::ClientError                   # bad input, pre-request
└── MailChannels::HttpRequestError              # status_code, response_body, error_type
    ├── MailChannels::ValidationError           # 400  ({"errors": [...]} parsed into message)
    ├── MailChannels::AuthenticationError       # 401/403 (403 doubles as "feature not on plan")
    ├── MailChannels::RateLimitError            # 429
    └── MailChannels::ServerError               # 5xx (500/502 documented)
```

Retry/idempotency notes: 429 semantics and DKIM-create-on-existing-selector
behavior (409? 400? success-with-existing?) are **not documented** — pin both
down with a sandbox key during gem development and encode the answer in the gem
(the same way the lettermint gem documents its "Domain has already been added"
ValidationError quirk). Error payload shape is uniform (`{"errors": ["…"]}`),
simpler than Lettermint's three shapes.

Gemspec skeleton: `faraday ~> 2.0` as sole runtime dep, same dev tooling as the
lettermint gem, MFA required, Ruby ≥ 3.0.

## 3. Integration into the custom sender domain flow

App-side, this is a fourth entry in the existing strategy registries. Consumed
config: `email_providers.mailchannels.{api_key, account_id, base_url}` via
`Mailer.provider_credentials('mailchannels')`; env
`CUSTOM_MAIL_PROVIDER=mailchannels`, `MAILCHANNELS_API_KEY`,
`MAILCHANNELS_ACCOUNT_ID`. **`account_id` (the account handle) is required
platform config** — unlike SES/Lettermint, the provider API does not hand us the
lockdown record; we compose it from the handle.

### 3.1 Files

| File | Contents |
|---|---|
| `Gemfile` | `gem 'mailchannels', require: false` (lazy-loaded like lettermint) |
| `lib/onetime/mail/sender_strategies/mailchannels_sender_strategy.rb` | provision / provider-verify / teardown (below) |
| `lib/onetime/mail/sender_strategies.rb` | add to `PROVIDER_STRATEGIES` and `PROVISIONING_PROVIDERS` |
| `lib/onetime/domain_validation/sender_strategies/mailchannels_validation.rb` | DNS-level validation; reads `mailer_config.dns_records` like `LettermintValidation` |
| `lib/onetime/domain_validation/sender_strategies/strategy.rb` | register validation strategy |
| `lib/onetime/mail/delivery/mailchannels.rb` | delivery backend (only when `EMAILER_MODE=mailchannels`) |
| `lib/onetime/domain_validation/sender_strategies/provider_config.rb` | `email_providers.mailchannels` config |
| `etc/defaults/config.defaults.yaml`, `.env.reference` | config + env plumbing |

### 3.2 Strategy mapping

**`provision_dns_records(mailer_config, credentials:)`**

1. Extract domain from `from_address` (inherited helper).
2. `client.dkim_keys.create(domain, selector: 'mc1')` — idempotent wrapper: on
   "already exists," fall back to `client.dkim_keys.list(domain, selector:
   'mc1')` (mirrors `create_or_get_domain` in the Lettermint strategy).
3. Compose and normalize the record set (standard `Array<Hash>` shape,
   `type`/`name`/`value`):

```
_mailchannels.<domain>       TXT  v=mc1 auth=<account_id>            (required — Domain Lockdown)
mc1._domainkey.<domain>      TXT  v=DKIM1; k=rsa; p=<public_key>     (required — from dkim_dns_records)
<domain>                     TXT  v=spf1 include:relay.mailchannels.net ~all   (required — see §3.3)
_dmarc.<domain>              TXT  v=DMARC1; p=none;                  (optional: true — advisory, same as SES)
```

`identity_id` → selector (or `<domain>/mc1`); `provider_data` → key status,
algorithm, created_at, account_id used.

**`check_provider_verification_status(mailer_config, credentials:)`**

One call: `client.check_domain(domain)`. `verified = dkim.all?(passed) &&
spf.verdict == 'passed' && domain_lockdown.verdict == 'passed' &&
sender_domain.verdict == 'passed'`. Map partial passes to
`'pending'`-style statuses with the per-check `reason` strings in `:details`
(they're human-readable and good enough to surface directly). No pre-trigger
call needed — unlike Lettermint, `check-domain` evaluates live DNS.

**`delete_sender_identity(mailer_config, credentials:)`**

`client.dkim_keys.update_status(domain, selector, status: 'revoked')` — there is
no domain object and no lockdown-record API to delete; the customer removes the
TXT records themselves (the UI already shows required records; removal guidance
belongs in the teardown message). 404 → already-deleted (idempotent, same as SES
/ Lettermint).

**`Delivery::MailChannels`** — clone of `Delivery::Lettermint` with the same
builder chain, `classify_error` (TimeoutError/429/5xx transient;
ValidationError/ClientError/4xx fatal), Sentry context tagged
`provider: 'mailchannels'`.

### 3.3 The one real integration wrinkle: SPF on the root domain

SES and Lettermint both confine SPF alignment to a dedicated subdomain
(`mail.<domain>` MX+TXT, `lm-bounces.<domain>` CNAME). MailChannels' documented
setup puts `include:relay.mailchannels.net` **in the customer's root-domain SPF
record**, because the envelope sender defaults to the from address itself.
Consequences:

1. Customers with an existing SPF record must **merge**, not add — two SPF
   records on one name is an SPF permerror. The UI copy for this record needs
   "add this include to your existing record" treatment, unlike every other
   record we show.
2. `ValidateSenderDomain` DNS checking cannot exact-match this TXT. The
   MailChannels validation strategy needs a per-record match mode: for the SPF
   record, pass if the domain's TXT set contains an SPF record whose mechanisms
   include `include:relay.mailchannels.net` (the `check-domain` endpoint's
   `spf.verdict` can serve as the authoritative tiebreaker). `classify_record_purpose`:
   `_mailchannels` → `'Domain Lockdown'`, `_domainkey` → `'DKIM'`, `v=spf1` → `'SPF'`.
3. DMARC posture: DKIM passes and aligns strictly (key is on the customer's
   domain), so DMARC passes via DKIM regardless. SPF passes via the include and
   aligns when the envelope stays on the from domain. That is equivalent to the
   SES-with-MAIL-FROM column of the alignment table in
   [`custom-mail-sender-ses.md`](./custom-mail-sender-ses.md) — but with the
   include on the root record.

**Possible subdomain alternative** (unverified): the send API accepts
`envelope_from`. Setting it to e.g. `bounces.<domain>` and publishing the SPF
TXT there instead would replicate the SES `mail.<domain>` pattern and leave the
customer's root SPF untouched — relaxed alignment still holds. Unknowns: whether
MailChannels applies SDNF (MX/A required) to that envelope subdomain, and where
bounces then land. Worth a support ticket / sandbox test before choosing;
default plan is the documented root-domain include.

### 3.4 Provider comparison (extends the table in custom-mail-sender.md)

| | AWS SES | Lettermint | MailChannels |
|---|---|---|---|
| Provision API | `CreateEmailIdentity` + MAIL FROM attrs | Team API `POST /domains` | `POST /domains/{d}/dkim-keys` + self-composed lockdown/SPF TXT |
| Domain resource at provider | identity | domain object | **none** (keys only) |
| DKIM records | 3 CNAMEs | CNAME selectors | **1 TXT** (inline public key, managed keypair) |
| SPF / envelope | MX + SPF TXT on `mail.<domain>` | Return-Path CNAME `lm-bounces.<domain>` | `include:relay.mailchannels.net` in **root** SPF (merge!) |
| Anti-spoofing | — (implicit in identity) | — | Domain Lockdown TXT `_mailchannels.<domain>` |
| Verification | `GetEmailIdentity` | `GET /domains/:id` + verify trigger | `POST /check-domain` (live, no trigger) |
| Teardown | `DeleteEmailIdentity` | `DELETE /domains/:id` | `PATCH dkim-keys status=revoked` |
| Auth | AWS SigV4 (SDK) | dual token (Bearer team / x-lettermint-token send) | single `X-Api-Key` |
| Ruby SDK | official `aws-sdk-sesv2` | ours (`lettermint`) | **ours (to build)** |

### 3.5 Open questions before implementation

1. **DKIM create idempotency** — response for an existing domain+selector
   (informs `create_or_get` in both gem and strategy). Sandbox test.
2. **`envelope_from` subdomain viability** (§3.3) — SDNF applicability, bounce
   routing. Support ticket.
3. **Rate limits** — undocumented; confirm 429 shape for `RateLimitError`.
4. **Data residency** — MailChannels is Canadian-owned (Vancouver), but no
   published regional processing guarantee equivalent to SES `ca-central-1`. If
   the Canada angle is a compliance claim rather than a vendor-locality
   preference, get it in writing from them before advertising it.
5. **Plan gating** — `check-domain` documents a 403 "no access to this feature";
   confirm our plan tier includes it (and webhooks + open/click tracking if
   wanted later).
6. **Webhook ingestion** (v1.1) — event types map well onto
   `lib/onetime/mail/feedback/`; signing-key verification endpoint exists.
   Scope into the feedback-sync work, not the sender-domain work.

## References

- Email API overview: https://docs.mailchannels.com/email-api/overview
- Authentication: https://docs.mailchannels.com/email-api/authentication
- Domain Lockdown: https://docs.mailchannels.com/email-api/domain-lockdown
- DKIM management: https://docs.mailchannels.com/email-api/configuring-dkim
- SPF/DKIM/DMARC: https://docs.mailchannels.com/email-api/spf-dkim-dmarc
- check-domain reference: https://docs.mailchannels.com/api-reference/dkim/dkim-spf-&-domain-lockdown-check
- Send reference: https://docs.mailchannels.com/api-reference/send/send-an-email
- OpenAPI spec: https://docs.mailchannels.com/email-api/api-reference/openapi.yaml
- Docs index (all pages as .md): https://docs.mailchannels.com/llms.txt
