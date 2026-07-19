---
title: Apex-Domain Sender Records - Integration Plan
type: plan
status: draft
updated: 2026-07-18
summary: Changes needed for sender-domain records that live on the customer's root/apex domain (MailChannels SPF include, Domain Lockdown TXT), including merge-aware SPF matching parity between the two DNS-checking layers.
---

Context: SES and Lettermint confine every customer-published record to dedicated
subdomains (`<token>._domainkey`, `mail.`, `lm-bounces.`), so exact-match DNS
checking works. MailChannels (see
[`custom-mail-sender-mailchannels.md`](./custom-mail-sender-mailchannels.md))
breaks that assumption: its SPF include lands **in the customer's root-domain
SPF TXT record**, which customers must merge into any existing record, and its
Domain Lockdown TXT sits at `_mailchannels.<domain>`. This plan covers what the
onetimesecret integration points need to support records on the apex.

## Current state (verified in code)

The codebase has **two independent DNS-checking layers**, and they have already
drifted on exactly the semantics apex SPF needs:

1. **Validation layer** — `DomainValidation::SenderStrategies::BaseStrategy`
   (`ValidateSenderDomain` → `DomainValidationWorker`). Already merge-aware:
   `txt_record_matches?` routes `v=spf1` expectations to `spf_record_matches?`,
   which extracts the `include:` directive and passes if any live `v=spf1` TXT
   contains it, regardless of other mechanisms. Non-SPF TXT uses substring
   match. **No change needed here for apex SPF.**
2. **Fact-finding layer** — `Mail::SenderStrategies::BaseSenderStrategy#`
   `check_single_dns_record` (`DnsRecordCheckWorker`, drives per-record
   `dns_exists` / `value_matches` and ultimately `dns_verified`). Exact match
   only: normalized string equality or SHA-256 digest equality. A customer with
   `v=spf1 include:example.com include:relay.mailchannels.net ~all` would
   **pass validation but fail the record check worker**.

So "support apex domain" is mostly "make layer 2 agree with layer 1, and teach
the UI about merge semantics" — plus registering the MailChannels strategy
itself.

## Work items

### 1. Shared DNS record matcher (the core fix)

Extract the matching logic from `BaseStrategy`
(`record_matches?` / `txt_record_matches?` / `spf_record_matches?`) into a
single module, e.g. `lib/onetime/utils/dns_record_matcher.rb`, and use it from
both layers:

- `BaseStrategy#record_matches?` delegates to the module (behavior unchanged).
- `BaseSenderStrategy#check_single_dns_record` computes `value_matches` via the
  module instead of digest/equality. Keep the digests in the result hash for
  debugging — they are informational, not the match criterion.

This removes the drift permanently instead of patching SPF awareness into a
second copy. Regression risk is low: for subdomain records (CNAME/MX and DKIM
TXT) the module's behavior is equality/substring, which is a strict superset of
today's equality check (substring TXT matching also fixes quoted/split TXT
edge cases).

### 2. Explicit merge semantics on the record hash

Today a stored record is `{type, name, value}` (+ `optional`, `status`). Add a
`match` hint set at provisioning time:

```ruby
{ type: 'TXT', name: 'example.com',
  value: 'v=spf1 include:relay.mailchannels.net ~all',
  match: 'spf-include' }   # default absent = exact/substring per matcher rules
```

Rationale: the matcher currently *sniffs* `v=spf1` to decide semantics. That
works, but an explicit flag (a) survives value-shape changes, (b) lets the UI
distinguish "create this record" from "merge into your existing record", and
(c) gives future apex records (e.g. a provider wanting `TXT @` verification
tokens) a place to declare semantics. The matcher treats the flag as
authoritative and falls back to sniffing when absent (backward compatible with
already-provisioned configs, which never re-provision).

Follows the `optional: true` precedent from the SES advisory DMARC record:
workers and models already tolerate extra keys on record hashes, and
`MailerConfig` stores them verbatim.

### 3. UI: merge-record presentation

`DomainEmailConfigForm.vue` (and the DNS-records display components) render
records as copy-paste rows. Apex SPF needs different copy: "add
`include:relay.mailchannels.net` to your existing SPF record; if you have none,
create this record." Drive it off `match: 'spf-include'` the same way the
dashed-border "Recommended" treatment is driven off `optional`. Also surface
the *actual* current SPF record when the check fails (the verification result
already carries `actual` values) so the customer sees what to edit rather than
a bare mismatch.

Secondary: apex TXT lookups return unrelated records (site-verification tokens
etc.), so `actual` arrays get noisy — filter display to `v=spf1`-prefixed
values for SPF-purpose records.

### 4. MailChannels strategy registration (per the research doc)

- `MailchannelsSenderStrategy` emitting the four records with the new flags:
  lockdown TXT + DKIM TXT exact-match; apex SPF with `match: 'spf-include'`;
  advisory DMARC with `optional: true`.
- `MailchannelsValidation#classify_record_purpose`: `_mailchannels` →
  `'Domain Lockdown'`, `_domainkey` → `'DKIM'`, `v=spf1` → `'SPF'`.
- Registries: `PROVIDER_STRATEGIES`, `PROVISIONING_PROVIDERS`, validation
  `Strategy` registry, `provider_credentials('mailchannels')`
  (`api_key` + `account_id` + `base_url`), `email_providers.mailchannels` in
  `config.defaults.yaml`, env plumbing (`MAILCHANNELS_API_KEY`,
  `MAILCHANNELS_ACCOUNT_ID`, `CUSTOM_MAIL_PROVIDER=mailchannels`).
- `Delivery::Mailchannels` backend gated on `EMAILER_MODE=mailchannels`
  (clone of the Lettermint backend against the new gem).

### 5. Non-issues (checked, no change needed)

- **DNS cache**: keyed `dns:cache:<host>:<type>`; the apex TXT entry is shared
  by any record on the apex — one lookup serves all, no collision.
- **`resolve_domain` / `extract_domain`**: derive the domain from
  `from_address`; apex records use that domain directly as `name`/`host`, no
  subdomain assumption exists in the resolution path.
- **Optional-record filtering**: `check_dns_records` / `computed_verification_status`
  already exclude `optional: true` records; the advisory DMARC record behaves
  exactly as it does for SES.

## Sequencing

1. Extract shared matcher + parity specs (pure refactor, ships alone; fixes
   the existing SES-SPF drift for customers who merged provider includes —
   worth doing even if MailChannels never ships).
2. `match` flag support in matcher + strategies + model passthrough.
3. UI merge-record treatment.
4. MailChannels strategy/validation/delivery + registries + config (depends on
   the `mailchannels` gem reaching a usable 0.1.0).
5. Sandbox pass: answer the research doc's open questions (DKIM create
   idempotency, `envelope_from` subdomain viability — if that pans out, the
   apex SPF record could become a subdomain record and item 3's UI work shrinks
   to nothing for MailChannels, but items 1-2 remain correct regardless).

## Test surface

- Matcher module: table-driven specs covering exact CNAME/MX, DKIM TXT,
  SPF-include-within-merged-record, SPF-missing-include, multiple TXT at apex,
  quoted/split TXT strings; parity assertion that both layers produce the same
  verdict for identical inputs (the drift regression test).
- Strategy: provision composes the four records with correct flags;
  check_provider_verification_status maps partial `check-domain` verdicts;
  teardown revoke is idempotent on 404.
- Existing tryouts under `try/unit/` for sender strategies extend naturally.
