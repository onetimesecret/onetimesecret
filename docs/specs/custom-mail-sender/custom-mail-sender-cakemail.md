---
title: Cakemail Sender Domain Provider (Research)
type: research
status: draft
updated: 2026-07-18
summary: Implementation research for Cakemail (Montreal) as a custom sender domain provider — API surface, OAuth2 auth model, per-address sender confirmation, DKIM/bounce-domain provisioning, Ruby library plan, and the multi-tenancy question that decides feasibility.
---

Cakemail (Montreal, QC) evaluated as a sender-domain provider alongside SES,
Lettermint, and MailChannels. Same lens as
[`custom-mail-sender-mailchannels.md`](./custom-mail-sender-mailchannels.md):
API surface, Ruby options, and fit against the sender strategy interface in
[`custom-mail-sender.md`](./custom-mail-sender.md).

**Bottom line:** the strongest Canadian-residency story of the providers
reviewed (Canadian-owned, data on Canadian servers, CASL-native, EU adequacy),
and the DKIM/DNS lifecycle maps well onto our strategy interface. But two
structural mismatches make it a harder integration than MailChannels: **OAuth2
password-grant auth** (expiring tokens, no static API keys) and **per-address
sender confirmation by emailed token** (a human at the customer's from-address
must click a link — DNS alone cannot complete provisioning). A third question —
whether bounce-domain SPF alignment is account-scoped rather than
domain-scoped — likely pushes a serious integration toward their Partner API
with one sub-account per customer. No Ruby SDK exists; we'd build our own.

## 1. Platform and API overview

| | Value |
|---|---|
| Base URL | `https://api.cakemail.dev` |
| Auth | OAuth2 password grant: `POST /token` (`grant_type=password&username&password`) → `access_token` (expires_in 432000 = 5 days) + `refresh_token`; then `Authorization: Bearer` |
| Spec | OpenAPI at `https://api.cakemail.dev/openapi.json` (indexed on Context7) |
| Scopes | `senders:read/write`, `dkim:read/write/delete`, `domains:read/write`, `emailapi:send`, `suppressions:*`, ... |
| Official SDKs | TypeScript (`cakemail-sdk`), CLI, MCP servers (`exec.mcp.cakemail.com`); PHP client archived; **no Ruby** |
| Multi-tenant | `account_id` query param on every endpoint (Partner API delegation); sub-accounts via Partner API |
| SMTP alternative | `smtp.cakemail.dev:465` (SMTPS, username/password), `x-email-api-enabled: true` header routing |
| Send docs | dev.cakemail.com — Email API guides (REST + SMTP) |

Two product generations coexist: the "Cakemail API" (campaigns/lists/contacts)
and the "Email API" (`/v2/emails`) for individual transactional/marketing
sends. We would use the Email API for delivery and the brand-level
`senders` / `dkim` / `domains` resources for identity provisioning.

### Sending model (`POST /v2/emails`)

```json
{
  "sender": { "id": "<sender_id>", "name": "Optional Override" },
  "email": "recipient@example.net",
  "content": {
    "type": "transactional",
    "subject": "…",
    "html": "…", "text": "…",
    "encoding": "utf-8"
  },
  "additional_headers": [{ "name": "X-...", "value": "..." }],
  "tracking": { "opens": false, "clicks_html": false }
}
```

Notable constraints, all different from SES/Lettermint/MailChannels:

- **`sender.id`, not a from-address.** The from identity is a reference to a
  pre-registered, confirmed sender object. The delivery backend needs a
  from_address → sender_id lookup (provision-time storage or list-and-match).
- **One recipient per call** (transactional). No personalizations/batch. CC/BCC
  are disallowed as custom headers; no cc/bcc fields on transactional sends.
- **Attachment types are whitelisted** (csv, doc(x), calendar, jpeg, pdf, png,
  xls(x)) — not arbitrary MIME types.
- Transactional + raw `email` needs no list; `marketing` type always requires
  `list_id`. Reply-to: per-template only in what the spec surfaced — confirm
  whether `/v2/emails` accepts reply_to (open question; `additional_headers`
  forbids cc/bcc but Reply-To may be allowed there).
- Response: `201` with `data.id` (UUID) + `status` (`queued|rejected|error`);
  lifecycle tracked via `GET /v2/emails/:id`, logs at `/v2/logs/emails`,
  reports at `/v2/reports/emails`. Statuses include delivered/open/click/
  bounce/spam/unsubscribe — polling-based feedback (webhooks exist in the
  platform; whether they cover `/v2/emails` events is an open question).
- Errors are FastAPI-shaped: `{"detail": [{"loc": [...], "msg": "...",
  "type": "..."}]}` on 400/422/500 — a third error-parsing dialect for the gem.

## 2. Sender identity and DNS model

Three separate mechanisms, each with its own lifecycle:

### 2.1 Sender confirmation (per address — the mismatch)

`POST /brands/default/senders` `{name, email, language}` registers a sender
identity and **sends a confirmation email to that address**. The sender is
unusable until someone clicks the link (or we call
`POST /brands/default/senders/confirm-email` with the `confirmation_id` from
that email). `GET /brands/default/senders` lists senders with `confirmed`
status; `resend-confirmation-email` re-triggers.

This is the structural conflict with our flow: our customer decision surface is
"flip on custom sender, add DNS records." Cakemail additionally requires the
customer's from-address inbox to receive and act on a confirmation email at
provision time. DNS checks cannot substitute. Integration would need a new
UI/state: "confirmation email sent to noreply@customer.com — click the link,
then re-verify" — including the failure mode where `noreply@` doesn't receive
mail at all (common for send-only addresses). `MailerConfig` would need a
provider-verification substate (`sender_pending_confirmation`) distinct from
DNS-pending.

### 2.2 DKIM keys (per domain — clean fit)

- `POST /brands/default/dkim` `{domain, selector}` → key `id`, `selector`,
  `public_key` (customer publishes `<selector>._domainkey.<domain>` TXT; we
  compose the `v=DKIM1; k=rsa; p=<public_key>` value — confirm exact expected
  value shape in sandbox).
- `POST /brands/default/dkim/{id}/activate` — **server-side live DNS check**;
  refuses if the TXT is missing or mismatched. This doubles as the provider
  verification call: attempt activate, interpret refusal as "pending."
- `GET /brands/default/dkim` lists keys (`status: active|inactive`,
  `account_default`, `domain_default`); `DELETE /brands/default/dkim/{id}` for
  teardown (a real DELETE — unlike MailChannels' status-patch).

### 2.3 Bounce/tracking domains (SPF alignment — the scoping question)

`GET/PATCH /brands/default/domains/default` shows/sets the account's `auth`,
`bounce`, `dkim`, `tracking` domains; `GET /brands/default/domains/default/validate`
returns the exact DNS entries with per-entry `valid` booleans — i.e. the
provider tells us the records and checks them, which slots directly into our
"store provisioned records verbatim, validate later" pattern.

A custom bounce domain (e.g. `bounce.customer.com`) is Cakemail's SPF-alignment
mechanism — the analogue of SES custom MAIL FROM and Lettermint's `lm-bounces`
CNAME. But the resource path is `brands/default/domains/default`: it looks
**account/brand-scoped, one bounce domain per account**, not per sending
domain. If so, a single platform account cannot give each customer domain its
own aligned envelope — SPF alignment would only work for one domain, and
everyone else rides Cakemail's shared envelope (DKIM-only DMARC, like SES
without MAIL FROM). Third-party SPF guides are contradictory (some show a
root-domain include, some show `bounce.<domain>` records against `md02.com`)
— treat the `validate` endpoint's output as the only source of truth.

**Consequence:** a multi-customer deployment probably requires the **Partner
API** — one sub-account per customer org (`account_id` param threads through
every endpoint), each with its own senders, DKIM keys, and bounce domain. That
is a bigger architectural step than any other provider needed:
`provider_credentials` would gain per-customer account context, and
provisioning would begin with ensure-sub-account. Cakemail is explicitly
partner/agency-oriented, so this is their intended shape — but it must be
priced/confirmed with them before committing.

## 3. Ruby library: build our own (again)

RubyGems has nothing for Cakemail's next-gen API. Official SDKs are
TypeScript/CLI/MCP; the PHP client is archived. A `cakemail` gem following the
lettermint/mailchannels structure works, with two deviations:

1. **TokenManager instead of a static header.** `POST /token` password grant,
   cache `access_token` with expiry, refresh via `refresh_token` (fall back to
   re-auth on refresh failure), thread-safe (mutex around refresh), and retry
   401s once after refresh. Credentials are the account's email + password (or
   a dedicated API user) — flag: store like any secret, but note there is no
   scoped/static key to rotate independently (an operational downside vs every
   other provider we run).
2. **FastAPI error mapping.** `{"detail": [{loc, msg, type}]}` → message
   joining `loc.join('.')`+`msg`; 422 ValidationError (Cakemail uses 422 like
   Lettermint, unlike MailChannels), 400 ClientError, 401 AuthenticationError
   (trigger token refresh path), 403 scope error, 5xx ServerError.

Resources for v1: `token` (internal), `senders` (create/list/confirm/resend/
delete), `dkim` (create/list/activate/delete), `domains` (show/patch/validate),
`emails` (`POST /v2/emails`, `GET /v2/emails/:id`) with an EmailMessage-style
builder constrained to single recipient; `account_id:` kwarg on every resource
call for Partner mode. Same gemspec/tooling/CI as mailchannels-ruby.

## 4. Strategy mapping (if pursued)

| Interface method | Cakemail calls |
|---|---|
| `provision_dns_records` | ensure sub-account (Partner mode) → `senders.create(from_address)` (triggers confirmation email) → `dkim.create(domain, selector)` → optionally `domains.patch(bounce: "bounce.<domain>")` → compose records: DKIM TXT + bounce/tracking entries from `domains.validate` (+ advisory DMARC). Store sender_id and dkim key id as `identity_id`/`provider_data`. |
| `check_provider_verification_status` | `senders.list` → confirmed? + `dkim.activate(id)` attempt (or key status) + `domains.validate` per-entry `valid`. Verified = sender confirmed AND dkim active AND bounce entries valid. New substate: `sender_pending_confirmation`. |
| `delete_sender_identity` | `dkim.delete(id)` + sender deletion (+ sub-account teardown in Partner mode). Idempotent on 404s. |
| Delivery backend | `POST /v2/emails` with cached sender_id; classify errors (422/400 fatal, 401 → token refresh once, 429/5xx transient); single-recipient loop for multi-recipient templates. |

DNS-validation strategy: all records come back from the provider
(`public_key`, `validate` entries) — store verbatim, standard `Array<Hash>`
normalization, no apex-SPF merge semantics needed *unless* the validate
entries turn out to be root-domain SPF includes (see open questions; if so,
the [apex plan](./custom-mail-sender-apex-plan.md) machinery covers it).

## 5. Provider comparison (Canada lens)

| | MailChannels | Cakemail |
|---|---|---|
| HQ | Vancouver, BC | Montreal, QC |
| Residency claim | Canadian-owned; **no published regional processing guarantee** | Canadian servers, CASL-native, EU adequacy documented in privacy policy — strongest claim of the set |
| Auth | static `X-Api-Key` | OAuth2 password grant, 5-day tokens + refresh |
| Sender identity | DNS-only (Domain Lockdown TXT) | **per-address email confirmation** + DNS |
| DKIM | managed keys, TXT, rotate API | managed keys, TXT, activate-with-DNS-check, DELETE |
| SPF alignment | apex include (merge) or envelope_from subdomain | custom bounce domain — possibly **account-scoped** (Partner API per customer) |
| Provider verify | `POST /check-domain` (one call, all verdicts) | assemble from senders.list + dkim activate + domains.validate |
| Send API | personalizations, batch, 30 MB | single recipient, attachment-type whitelist |
| Feedback | webhooks (signed) | status polling on `/v2/emails/:id` + logs; webhook coverage TBD |
| Fit with current architecture | drop-in after apex work | needs confirmation-substate + likely Partner API |

## 6. Open questions before committing

1. **Bounce-domain scoping** — is `brands/default/domains/default` truly one
   bounce domain per (sub-)account? If yes, Partner API sub-accounts are a
   prerequisite for per-customer SPF alignment. Ask Cakemail directly; get
   Partner terms and pricing.
2. **Sender confirmation bypass** — for Partner accounts, can sender
   confirmation be waived or completed programmatically (we control the
   `confirmation_id` email only if we can receive at the customer's address —
   we can't)? If not, the confirmation-click step is a permanent part of the
   customer UX.
3. **SPF record shape** — exact entries from `domains.validate` for a custom
   bounce domain (CNAME vs MX+TXT vs root include). Third-party guides
   disagree; sandbox it.
4. **`/v2/emails` reply_to** and whether Reply-To is settable via
   `additional_headers`.
5. **Webhooks for Email API events** (delivered/bounce/spam) vs polling only.
6. **DKIM TXT value shape** — raw `public_key` vs full `v=DKIM1; k=rsa; p=…`
   string; and idempotency of `dkim.create` for an existing domain+selector.
7. **Rate limits** and token-endpoint limits (password grant per worker
   process could hit them; TokenManager should share tokens via Redis).
8. **API user hygiene** — password-grant credentials are login credentials;
   confirm a service-user with restricted scopes is possible.

## References

- Developer portal: https://dev.cakemail.com/en
- Getting started (OAuth2): https://dev.cakemail.com/en/guides/getting-started
- Email API reference (endpoints, SMTP): https://dev.cakemail.com/en/guides/email-api-reference
- OpenAPI spec: https://api.cakemail.dev/openapi.json (Context7: `/openapi/api_cakemail_dev_openapi_json`)
- GitHub org (SDK inventory): https://github.com/cakemail
- Canadian residency claims: https://www.cakemail.com/solutions/email-marketing-for-canadian-businesses, https://www.cakemail.com/legal/privacy-policy
- Domain auth support article: https://support.cakemail.com/hc/en-us/articles/360056294574
