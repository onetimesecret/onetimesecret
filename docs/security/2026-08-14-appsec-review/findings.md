# Findings Report

**Date:** 2026-08-14 · **Target:** `onetimesecret` @ `21c3f6a` (branch `agent/fervent-pascal-0y5cji`)

Severity uses exploitability × impact. Each finding is tagged:

- **[REPRODUCED]** — demonstrated against the locally-running instance; PoC in `poc/`.
- **[CODE-CONFIRMED]** — verified by reading the code and, where possible, by querying the live
  database/runtime; no end-to-end exploit was constructed.

---

## Summary table

| ID | Sev | Finding | Status |
|---|---|---|---|
| H-1 | High | Any org member can harvest colleagues' secret bearer tokens via `receipt/recent?scope=org` | CODE-CONFIRMED |
| H-2 | High | Non-owner member is handed the org's Stripe Customer Portal | CODE-CONFIRMED |
| H-3 | High | Tenant SSO `allowed_domains` is dead code — the documented access control has no runtime effect | CODE-CONFIRMED |
| M-1 | Medium | `email_verified` is never checked on any SSO path | CODE-CONFIRMED |
| M-2 | Medium | Magic-link lifetime is 24h, not the configured 15 minutes | CODE-CONFIRMED |
| M-3 | Medium | Account enumeration on `email-login-request` and `verify-account-resend` | CODE-CONFIRMED |
| M-4 | Medium | No rate limit on `email-login-request` (mailbox bombing) | CODE-CONFIRMED |
| M-5 | Medium | Stripe invoice PDFs / hosted URLs exposed to any org member | CODE-CONFIRMED |
| M-6 | Medium | Domain-scope enforcement missing on `receipt/recent?scope=domain` | CODE-CONFIRMED |
| M-7 | Medium | Unauthenticated Redis exhaustion via unthrottled secret creation | **REPRODUCED** |
| M-8 | Medium | CSP nonce published in the client bootstrap payload | CODE-CONFIRMED |
| M-9 | Medium | Vendored DNS widget injects remote HTML via `insertAdjacentHTML` | CODE-CONFIRMED |
| M-10 | Medium | Secret bearer tokens persisted in `sessionStorage` | CODE-CONFIRMED |
| M-11 | Medium | `sqlite3` 2.9.5 use-after-free (GHSA-mwm8-39rw-8826) | **REPRODUCED** |
| M-12 | Medium | `yq` fetched into production images with no checksum verification | CODE-CONFIRMED |
| M-13 | Medium | `claude-code-action@beta` mutable ref holds a repository secret | CODE-CONFIRMED |
| M-14 | Medium | End-user session revocation does not revoke the session | CODE-CONFIRMED |
| L-1…L-9 | Low | See §4 | Mixed |

---

## 1. High severity

### H-1 — Any organization member can harvest every colleague's secret bearer tokens

**Severity:** High · **CWE-639 / CWE-200** · **CODE-CONFIRMED**

**Where:** `apps/api/v2/logic/secrets/list_receipts.rb:41-58,126-140`,
`lib/onetime/models/receipt/features/safe_dump_fields.rb:79`
**Routes:** `GET /api/v2/receipt/recent`, `GET /api/v3/receipt/recent`

In this product, `secret_identifier` **is** the capability — possession of it is sufficient to
reveal the secret. The org-scoped receipts listing is gated at the *member* level and returns that
capability for every member's receipts:

```ruby
# apps/api/v2/logic/secrets/list_receipts.rb:46
require_entitlement!('api_access')          # member-level entitlement

# :126-139  (organization scope)
def query_organization_receipts
  @scope_label = auth_org.display_name
  auth_org.receipts.rangebyscore(since, @now)   # ALL org members' receipts
end
```

```ruby
# lib/onetime/models/receipt/features/safe_dump_fields.rb:79
base.safe_dump_field :secret_identifier, ->(m) { m.shows_share_link? ? m.secret_identifier : nil }
```

`shows_share_link?` is true for every `source == 'standard'` receipt
(`lib/onetime/models/receipt.rb:124-128`), and every authenticated create is indexed into the org
(`apps/api/v2/logic/secrets/base_secret_action.rb:486-491`).

**Attack.** Attacker = the lowest-privilege active member of any organization (an invited "member",
or anyone auto-provisioned by tenant SSO):

1. `GET /api/v3/receipt/recent?scope=org` → 30 days of every member's receipts, each carrying a
   live `secret_identifier`.
2. `POST /api/v3/secret/<secret_identifier>/reveal` with `continue=true`. The reveal path performs
   no ownership check by design (`apps/api/v2/logic/secrets/reveal_secret.rb:62-65`) — the
   identifier *is* the authorization. Result: plaintext of a colleague's unread secret.
3. Or `POST /api/v3/receipt/<identifier>/burn` to destroy them.

Passphrase-protected secrets resist step 2; most secrets carry no passphrase.

**Why this is a defect, not the intended capability model.** The sibling org-wide surface
`ListSecretActivity` requires the **admin/owner** `audit_logs` entitlement *and* deliberately
withholds full identifiers, with an explicit comment
(`apps/api/organizations/logic/organizations/list_secret_activity.rb:18-27,85`):

> *"Events carry receipt/secret shortids only — never full identifiers, which are capability tokens"*

The two surfaces contradict each other, and the weaker-gated one hands out the actual capabilities.

**Impact.** Complete intra-tenant confidentiality break of the product's core asset, available to
the least-privileged role.

**Remediation.**
1. In `ListReceipts#success_data`, redact `identifier`, `key`, and `secret_identifier` for records
   where `receipt.owner?(cust)` is false.
2. Raise the `scope=org` gate from `api_access` to `audit_logs` (or a dedicated entitlement), for
   parity with `ListSecretActivity`.

---

### H-2 — Non-owner member is handed the organization's Stripe Customer Portal

**Severity:** High · **CWE-862** · **CODE-CONFIRMED**

**Where:** `apps/web/billing/controllers/plans.rb:300-337,383-410`
**Route:** `apps/web/billing/routes.txt:20` → `GET /billing/portal … auth=sessionauth` (no `role=`)

```ruby
# apps/web/billing/controllers/plans.rb:300-329
def customer_portal_redirect
  org = find_or_create_default_organization(cust)     # NO ownership check
  ...
  portal_session = Stripe::BillingPortal::Session.create(
    { customer: org.stripe_customer_id, return_url: return_url },
  )
  res.redirect portal_session.url
```

`find_or_create_default_organization` resolves `cust.default_org_id` — and that field is repointed
to a **shared tenant organization** for a caller who is only a `member`:

```ruby
# apps/web/auth/operations/join_domain_organization.rb:84-93,155-158
membership = Onetime::OrganizationMembership.ensure_membership(
  organization, customer, role: 'member', ...)
...
customer.default_org_id = domain_org.objid
customer.save
personal_org.archive!(...)
```

Same write at `apps/web/auth/operations/bulk_sso_migration.rb:165,211` and
`apps/api/organizations/cli/add_member_command.rb:203`.

**Attack.** A pre-existing account holder signs in via the tenant's custom-domain SSO (or is swept
by `BulkSsoMigration`). Their `default_org_id` is repointed to the tenant org. They then request
`GET /billing/portal` and are 302'd into the **tenant's Stripe Customer Portal**, where they can
read the full billing history and payment instruments, change the payment method and billing
address, and **cancel the subscription**.

**Why this is an outlier, not the pattern.** Every mutating billing endpoint on the sibling
controller checks ownership — `apps/web/billing/controllers/billing.rb:77,557,941,1101` all use
`load_organization(..., require_owner: true)` — and `manage_billing` is an owner-only entitlement
(`lib/onetime/models/organization_membership.rb:99`). The parallel `Welcome#customer_portal_redirect`
(`apps/web/core/controllers/welcome.rb:178-197`) is clean: it uses the caller's own
`cust.stripe_customer_id`.

**Remediation.** Require `org.owner?(cust)` — or `require_entitlement_in!(org, 'manage_billing')` —
before creating the portal session.

---

### H-3 — Tenant SSO `allowed_domains` is dead code

**Severity:** High (for tenant/self-hosted deployments relying on it) · **CWE-1220** · **CODE-CONFIRMED**

**Where:** `lib/onetime/models/custom_domain/sso_config.rb:236-244`

```ruby
def valid_email_domain?(email)
  domains = allowed_domains
  return true if domains.empty?
  email_domain = email.to_s.split('@').last&.downcase
  return false if email_domain.nil? || email_domain.empty?
  domains.include?(email_domain)
end
```

**Verified:** a repo-wide search for callers finds production call sites only for the *SignupConfig*
class (`signup_config.rb:506` calling `signup_config.rb:189`). The `SsoConfig` method at
`sso_config.rb:236` has **zero** production callers — only specs and `try/` files reference it:

```
$ grep -rn "valid_email_domain?" --include=*.rb .
lib/onetime/models/custom_domain/signup_config.rb:189   (def)
lib/onetime/models/custom_domain/signup_config.rb:506   (CALLER)
lib/onetime/models/custom_domain/sso_config.rb:236      (def — no caller)
...remaining hits are all spec/ and try/
```

The field is fully plumbed through the API (`put_sso_config.rb:215`, `patch_sso_config.rb:317`,
`serializers.rb:34`) and rendered in the UI, so operators configure it and believe it is enforcing.

The only domain gate that actually runs in the callback is `hooks/omniauth.rb:661`, which consults
`CustomDomain::SignupConfig` or the global `site.authentication.allowed_signup_domains` — a
different config object.

**Why the impact is high.** The product's own metadata tells operators this is their access control
(`sso_config.rb:57-59`):

> `'oidc' => { requires_domain_filter: true, idp_controls_access: false, description: 'Generic OIDC provider - domain filtering recommended' }`

An operator who configures a generic OIDC IdP and restricts it to `@corp.com` has no restriction at
all: any identity the IdP will authenticate can sign in.

**Secondary issue in the same area.** The gate at `hooks/omniauth.rb:661` runs only in
`before_omniauth_create_account` — the **create path only** (acknowledged at
`hooks/omniauth.rb:224-226`). A user whose email domain is later removed from the allowlist keeps
signing in indefinitely.

**Remediation.** Call `sso_config.valid_email_domain?(email)` in the callback path, on **both**
create and login, and fail closed. Add a regression spec that asserts a disallowed domain is
rejected end-to-end.

---

## 2. Medium severity

### M-1 — `email_verified` is never checked on any SSO path
**CODE-CONFIRMED** · `apps/web/auth/config/hooks/omniauth.rb:32-33,199-209`

A repo-wide search for `email_verified` in production Ruby returns zero hits. The OIDC strategy does
surface the claim (`omniauth_openid_connect-0.8.0/.../openid_connect.rb:78`) — it is discarded.

Two consequences:

- **Auto-link.** With `OIDC_TRUST_EMAIL_FOR_LINKING` / `ENTRA_TRUST_EMAIL_FOR_LINKING` /
  `SSO_TRUST_EMAIL_FOR_LINKING` enabled, an IdP account asserting `victim@corp.com` is auto-linked
  and logged in as the victim (`hooks/omniauth.rb:199-209`). Default-off, documented as a
  self-hosted escape hatch — but the one check that would make it safe is absent.
- **JIT creation at an arbitrary asserted email.** `omniauth_create_account? true` and
  `omniauth_verify_account? true` are the default (`features/omniauth.rb:52,59`). An IdP that lets a
  user set an unverified `email` claim allows address squatting and bypasses `ALLOWED_SIGNUP_DOMAIN`,
  since the gate at `hooks/omniauth.rb:661` trusts the same unverified claim.

Google and GitHub strategies filter on verification themselves
(`google_oauth2.rb:154-156`, `github.rb:58-61`). **Generic OIDC and Entra ID do not** — precisely the
two providers offered on the tenant surface.

Combined with `ENTRA_TENANT_ID=common` (which the Entra strategy also does not issuer-check —
`omniauth-entra-id-3.1.1/.../entra_id.rb:152-204`, `JWT.decode(..., nil, false)`), this is textbook
**nOAuth**: any Entra tenant admin can set a user's `email` claim to a victim's address.

**Remediation.** Refuse to link (and refuse to create) when `omniauth_info['email_verified']` is
present and falsey; require it truthy for the `trust_email_for_linking?` branch. Reject
`common`/`organizations`/`adfs` for `ENTRA_TENANT_ID` at boot.

---

### M-2 — Magic-link lifetime is 24 hours, not the configured 15 minutes
**CODE-CONFIRMED — verified against the live migrated database**

`apps/web/auth/config/features/email_auth.rb:17-20` sets:

```ruby
# Magic links are only valid for a short period ...
auth.email_auth_deadline_interval 15.minutes
```

Rodauth only honours `*_deadline_interval` when `set_deadline_values?` is true, and that is
**MySQL-only** (`rodauth-2.45.0/lib/rodauth/features/base.rb:783-785`):

```ruby
def set_deadline_values?
  db.database_type == :mysql
end
```

The deployment is PostgreSQL/SQLite and never overrides it, so the column default applies. Read back
from the database this review actually migrated:

```
CREATE TABLE `account_email_auth_keys` (
  `id` bigint NOT NULL PRIMARY KEY REFERENCES `accounts`,
  `key` varchar(255) NOT NULL,
  `deadline` timestamp DEFAULT (datetime(datetime(CURRENT_TIMESTAMP,'localtime'),'1 days')) NOT NULL,
  ...
```

**Actual lifetime: 24 hours — 96× the configured and documented value.** Expiry *is* enforced
(`email_auth.rb:141-145`), just against the wrong number. Compounding: `create_email_auth_key`
(`email_auth.rb:104-115`) *reuses* a live key rather than minting a new one, so a single token stays
valid for the full 24h across every resend.

**Remediation.** Set `auth.set_deadline_values? true` (preferred — makes every configured interval
authoritative), or change the column default. Add a spec asserting the persisted deadline.

---

### M-3 — Account enumeration on `email-login-request` and `verify-account-resend`
**CODE-CONFIRMED** · `rodauth-2.45.0/lib/rodauth/features/email_auth.rb:56-70,185-189`

With `json_response_custom_error_status? true` (`apps/web/auth/config/base.rb:60`), three distinct
single-request responses distinguish account state:

| Case | Status | Body |
|---|---|---|
| registered + open | 200 | `{"success":"Login link sent to your email"}` |
| registered, sent <30s ago | 400 | `{"error":"Login link was recently sent..."}` |
| no account / unverified / closed | 401 | `{"error":"Error requesting login link"}` |

This is the same CWE-204 oracle the team deliberately closed for `reset-password-request`
(`apps/web/auth/config/overrides/reset_password_enumeration.rb`) — but that override is scoped by
`current_route == :reset_password_request` (line 127), so it never applies here. The same shape
exists on `verify-account-resend` (`verify_account.rb:67-93`).

**Mitigating factor found during live testing:** `/auth/email-login-request` is **not** in the CSRF
bypass list (`lib/onetime/middleware/security.rb:158-199`), so an anonymous POST is rejected with
403 before reaching Rodauth. An attacker must first establish a session and obtain a CSRF token —
trivial, but it means this is not a single-request unauthenticated oracle. `email_auth` is also
off by default (`AUTH_EMAIL_AUTH_ENABLED`).

**Remediation.** Mirror `reset_password_enumeration.rb` for the `email_auth` and
`verify_account_resend` routes: return one generic response for all branches.

---

### M-4 — No rate limit on `email-login-request`
**CODE-CONFIRMED** · no `before_email_auth_request_route` hook exists

The codebase has a deliberate limiter on the two other unauthenticated Rodauth entry points —
`hooks/reset_password_request.rb:75-82` and `hooks/create_account.rb:110-121`. There is no
equivalent for email auth (`apps/web/auth/config/hooks.rb:40` confirms only
`before_email_auth_route` and `after_email_auth_request` are owned).

The only throttle is Rodauth's per-account resend gate, set to **30 seconds**
(`features/email_auth.rb:20`). That caps emails per address but not requests per source: ~120
emails/hour/address across unlimited addresses from one IP, and unbounded-rate enumeration of M-3.

**Remediation.** Register `before_email_auth_request_route` with `ResetRequestRateLimiter`,
following the reset-password hook exactly.

---

### M-5 — Stripe invoice PDFs and hosted URLs exposed to any org member
**CODE-CONFIRMED** · `apps/web/billing/controllers/billing.rb:290-291,313-325`

```ruby
def list_invoices
  org = load_organization(req.params['extid'])   # membership only; require_owner NOT passed
  ...
  invoice_pdf: invoice.invoice_pdf,
  hosted_invoice_url: invoice.hosted_invoice_url,
```

Any active member calls `GET /billing/api/org/<extid>/invoices` and receives up to 12 Stripe
`hosted_invoice_url` / `invoice_pdf` links. Those are **unauthenticated bearer URLs** exposing the
organization's billing address, tax IDs, payment-method last4, and line-item history, and the hosted
page offers pay/download actions.

**Remediation.** `load_organization(req.params['extid'], require_owner: true)`.

---

### M-6 — Domain-scope enforcement missing on `receipt/recent?scope=domain`
**CODE-CONFIRMED** · `apps/api/v2/logic/secrets/list_receipts.rb:144-169`

```ruby
has_access = domain.accessible_by?(cust)   # org membership ONLY
```

`CustomDomain#accessible_by?` is `org.owner?(c) || org.member?(c)`
(`lib/onetime/models/custom_domain.rb:272-276`). It never consults
`OrganizationMembership#can_access_domain?` — the control every other domain surface applies
(`list_domains.rb:56-59`, `get_domain.rb:51-56`, `remove_domain.rb:42-47`,
`domain_config_authorization.rb:161-165`).

An SSO member scoped to domain A can list domain B's receipts in the same org — and thereby their
bearer tokens (chains into H-1).

**Remediation.** Add `membership.can_access_domain?(domain)` to `query_domain_receipts`.

---

### M-7 — Unauthenticated Redis exhaustion via unthrottled secret creation
**Severity:** Medium · **CWE-770** · **REPRODUCED** · PoC: `poc/02-conceal-flood-dos.sh`

There is **no rate limiter on the secret-creation path**. The limiter registry
(`lib/onetime/operations/ratelimit/registry.rb:40-93`) covers `feedback`, `passphrase`, `invite`,
`login`, `reset_request_ip`, `reset_request_email`, `create_account_ip`, and `dns`. Secret creation
(`conceal`) is absent, and `ConcealSecret#raise_concerns`
(`apps/api/v2/logic/secrets/conceal_secret.rb:27-33`) enforces only guest-route gating, non-empty
content, and size.

**Reproduced against the local instance:**

```
$ redis-cli info memory | grep used_memory_human
used_memory_human:1.63M
$ redis-cli -n 0 dbsize
107

# 200 unauthenticated POSTs, 10 KB payload each, ttl=604800 (the anonymous maximum)
$ ./poc/02-conceal-flood-dos.sh 200

$ redis-cli info memory | grep used_memory_human
used_memory_human:4.83M
$ redis-cli -n 0 dbsize
508
$ redis-cli -n 0 ttl secret:m8noi9jn...:object
604795
```

40 rapid sequential creates also returned `200` every time with no throttling.

**Impact.** ~16 KB of Redis memory per unauthenticated request, persisting for **7 days**. Redis is
the primary datastore for secrets *and* sessions, so exhausting it takes the whole service down. At
a sustained 500 req/s an attacker writes ~16 GB in roughly 35 minutes, from a single host, with no
account.

**Mitigating.** `SECRET_MAX_LENGTH` (10 000) bounds per-request cost and the TTL bounds retention;
an operator behind a CDN/WAF may have edge rate limiting. Neither is an application control.

**Remediation.** Add a `conceal_ip` limiter to the registry keyed on the masked client IP, following
`create_account_rate_limiter.rb`. Consider a lower anonymous TTL ceiling and a per-IP live-secret cap.

---

### M-8 — CSP nonce is published in the client bootstrap payload
**CODE-CONFIRMED** · `apps/web/core/views/serializers/system_serializer.rb:24`,
`src/schemas/contracts/bootstrap.ts:720`, `src/shared/composables/useDnsWidget.ts:92-106`

The per-request CSP nonce is serialized into the hydration blob and read back by app code. A
nonce-only `script-src` derives all its value from the nonce being unguessable **and unreadable from
non-script contexts**; here it sits in plaintext in a `<script type="application/json">` element.
Any HTML-injection-without-script-execution primitive (dangling markup, scriptless attribute
injection, CSS exfiltration) recovers it, and a second injection then executes with a valid nonce.

The code already has the correct fallback — `document.querySelector('script[nonce]')`
(`useDnsWidget.ts:103-105`), which works because browsers hide the content attribute but preserve
the IDL property.

**Remediation.** Drop `nonce` from `SystemSerializer` and `bootstrapSchema`; rely on the
`script[nonce]` IDL fallback alone.

---

### M-9 — Vendored DNS widget injects remote HTML via `insertAdjacentHTML`
**CODE-CONFIRMED** · `src/assets/approximated/dnswidget.v1.js:146-152,216-221,245-250,53-58`

The vendored third-party widget injects raw HTML strings straight from an Approximated API response
and interpolates DNS-lookup values (attacker-controlled by whoever owns the zone being verified)
with no escaping:

```js
widget.insertAdjacentHTML('beforeend', inst.html);
...
<textarea ...>${record.actual_values || "No value set"}</textarea>
```

**Not currently exploitable as XSS**, because production CSP is `script-src 'nonce-…'` with no
`unsafe-inline` — injected event handlers and `javascript:` hrefs are blocked, and `<script>`
elements inserted this way never execute. But the mitigation is entirely CSP-dependent, and
`CSP_ENABLED=false` or `development.enabled=true` (which adds `'unsafe-inline'`) removes it.

**Remediation.** Sanitize `inst.html` / `verify_section.html` with DOMPurify; escape the `record.*`
interpolations.

---

### M-10 — Secret bearer tokens persisted in `sessionStorage`
**CODE-CONFIRMED** · `src/shared/stores/localReceiptStore.ts:48,59,138`,
`src/schemas/ui/local-receipt.ts:30-36`

Up to 25 guest receipts are stored under `sessionStorage['onetimeReceiptCache']`, each carrying
`receiptExtid` and `secretExtid` — both capability tokens. Any script on the origin can read them.
For a product whose entire value proposition is single-use secret custody, this materially widens
the blast radius of any XSS.

Limiting factors: `sessionStorage` (tab-scoped, cleared on close) rather than `localStorage`, and
reads are schema-validated. **No auth tokens, API keys, or CSRF tokens are in web storage** — those
are correctly in-memory only.

**Remediation.** Accept with documented risk, or replace with a server-side guest receipt list keyed
on the session.

---

### M-11 — `sqlite3` 2.9.5 use-after-free
**REPRODUCED** (`bundle-audit`) · `Gemfile.lock:513`

```
Name: sqlite3   Version: 2.9.5
GHSA-mwm8-39rw-8826 — Use-After-Free in SQLite Aggregate Arguments
Solution: update to '>= 2.9.6'
```

The **only** Ruby advisory across the whole lockfile. It is a production dependency, not dev-only:
`Dockerfile:225,371` install `libsqlite3-0` into both final images, and
`docker/compose/docker-compose.full.yml:71` sets `AUTH_DATABASE_URL=sqlite://data/auth.db`.

Practical exploitability is low — all SQL is Sequel/Rodauth-generated, not user-composed. `Gemfile:96`
already declares `~> 2.0`, which permits 2.9.6, so this is a lockfile bump only.

---

### M-12 — `yq` fetched into production images with no checksum verification
**CODE-CONFIRMED** · `docker/base.dockerfile:61-71`, copied at `Dockerfile:272,392`

The binary is version-pinned but not hash-verified, and it lands in **both** shipped images. A
compromised or retagged GitHub release asset puts an attacker-controlled executable in production.

The same file already demonstrates the correct pattern 180 lines below for s6-overlay
(`Dockerfile:242-260`): fetch the publisher's `.sha256` and `sha256sum -c` before extraction, with
an explicit rationale. Apply the same treatment.

---

### M-13 — `anthropics/claude-code-action@beta` is a mutable ref holding a repository secret
**CODE-CONFIRMED** · `.github/workflows/claude-code-review.yml:78-80`, `.github/workflows/claude.yml:49`

`@beta` is mutable; whoever controls that branch controls code in a job holding
`CLAUDE_CODE_OAUTH_TOKEN` and `id-token: write`. It is the only third-party action in the repo and
the only one receiving a repository secret.

Mitigating controls are good — the job gates on `!…head.repo.fork` and `!endsWith(github.actor,
'[bot]')`, permissions are otherwise read-only, and the trigger is `pull_request` (not
`pull_request_target`). **Remediation:** pin to a release SHA, as the same file already does elsewhere.

---

### M-14 — End-user session revocation does not revoke the session
**CODE-CONFIRMED** · `apps/web/auth/routes/active_sessions.rb:86,111`

`rodauth.remove_active_session(session_id)` only deletes a SQL row
(`rodauth-2.45.0/lib/rodauth/features/active_sessions.rb:93-95`), and there is no override in this
codebase. The encrypted Redis blob `session:<sid>` — which is what actually authenticates requests —
is untouched.

The authoritative gate is `BaseSessionAuthStrategy`
(`lib/onetime/application/auth_strategies/base_session_auth_strategy.rb:31-67`); it checks
`awaiting_mfa`, `authenticated`, `external_id`, suspension, and the credential watermark, and never
consults `account_active_session_keys`. `check_active_session` — the Rodauth method that enforces
revocation and the configured deadlines — has **no call site anywhere** in the application.

**Impact.** A user who sees a suspicious device in "Active Sessions" and clicks *Remove* gets a
success response and the row disappears, but the attacker's session keeps working until its 24h idle
TTL lapses. Same for "remove all". The colonel-side operations
(`lib/onetime/operations/sessions/revoke_for_customer.rb`) *do* delete the Redis blobs correctly —
only the end-user surface is broken.

**Related:** the configured `session_inactivity_deadline` (24h) and `session_lifetime_deadline`
(30 days) at `features/active_sessions.rb:20-21` are enforced exclusively through the same
never-called methods, so there is **no absolute session lifetime** — `write_session`
(`lib/onetime/session.rb:696-697`) refreshes the TTL on every request, giving a sliding 24h idle
timeout with no cap.

**Remediation.** Make `remove_active_session` delete the Redis blob (reuse `RevokeForCustomer`), and
call `check_active_session` on the request path so the deadlines take effect.

---

## 3. Low severity

- **L-1** — `RemoveMember` (`apps/api/organizations/logic/members/remove_member.rb:39-58`)
  authorizes on role strings only, skipping the `require_entitlement_in!` layer every sibling
  member/invite operation uses, and never checks `membership.active?` for the actor. An admin whose
  `manage_members` entitlement was revoked can still remove members.
- **L-2** — `authorize_domain_incoming!` (`apps/api/domains/logic/incoming_config/base.rb:81-91`)
  omits the `can_access_domain?` check its sibling policy applies. Currently unreachable
  (`manage_org` is owner-only); latent.
- **L-3** — The `secret` field accepts a JSON object and stores its Ruby `.to_s`. **Reproduced:**
  `{"secret":{"secret":{"a":"b","c":[1,2]},"ttl":3600}}` reveals as `{"a"=>"b", "c"=>[1, 2]}`. The
  declared `concealSecret` request schema is not type-enforced. Not a security boundary; fix for
  correctness.
- **L-4** — `isValidInternalPath` (`src/utils/redirect.ts:63-72`) does not reject `/\evil.com`,
  which the WHATWG URL spec resolves to `https://evil.com/`. **Latent only** — every current caller
  passes a hardcoded value, and the other consumers use `router.push`, which throws on cross-origin.
  One-line fix: also reject `path.startsWith('/\\')`.
- **L-5** — `brace-expansion` overrides in `pnpm-workspace.yaml:29-31` pin `1.1.17`/`2.1.3`/`5.0.8`,
  each exactly one patch below the floors in GHSA-rgw5-rvv9-x895, which describes a **bypass of the
  mitigation these pins were chosen for**. All paths are `dev: true` (CI/developer DoS surface only).
  The comment above them still calls this a range-syntax false positive — that reasoning is now
  stale and will cause the next reader to dismiss a genuine advisory.
- **L-6** — `actions/setup-python@v5`, `actions/github-script@v7/@v9`, `actions/download-artifact@v4`
  pinned by mutable tag while `actions/checkout` and `actions/labeler` are correctly SHA-pinned.
- **L-7** — Redis transport TLS is neither enforced nor asserted at boot
  (`familia/lib/familia/connection.rb:126-132`); `rediss://` works if the operator supplies it.
  Session blobs are AES-256-GCM at rest, so plaintext transport leaks session ids rather than
  contents. Document an operator requirement for `rediss://` plus a key-prefix-scoped Redis ACL.
- **L-8** — Simple mode only: `apps/api/account/logic/authentication/reset_password.rb:22` looks up
  **any** `Onetime::Secret` by the submitted `key` and burns it if it is not a valid reset secret.
  Destruction only, no disclosure; requires knowing the 320-bit identifier; production runs `full`
  mode where Rodauth owns the route.
- **L-9** — Raw email addresses logged at `hooks/email_auth.rb:162-166`,
  `config/email/delivery.rb:11-18`, and `lib/onetime/jobs/publisher.rb:223`, contrary to the stated
  invariant at `hooks.rb:75` ("Emails obscured"). No token material is logged. Also
  `lib/onetime/application/request_logger.rb:93-97` writes `sid.public_id` — which
  `rack-session` aliases to `cookie_value`, i.e. the **raw session token** — under
  `LOG_HTTP_CAPTURE=debug` (off by default). One-word fix to `private_id`.

---

## 4. Blanket CSRF exemption for `/auth/sso/*` (Low–Medium, noted separately)

All three CSRF layers are simultaneously off for `POST /auth/sso/:provider`:

1. Rodauth's `route_csrf`, deliberately omitted — `hooks/omniauth.rb:560-566`
   (`⚠️ DO NOT call check_csrf / check_csrf? here`).
2. `Rack::Protection::AuthenticityToken`, bypassed by prefix match —
   `lib/onetime/middleware/security.rb:162`.
3. `Rack::Protection::HttpOrigin`, off by default — `etc/defaults/config.defaults.yaml:426`.

OAuth `state` protects the **callback** (verified — see §5), so this is not a one-shot takeover.
But a cross-site auto-submitting form can, in a victim's authenticated browser, mint or delete the
`sso_connect_intent` nonce (`hooks/omniauth.rb:605-609`) — reliably breaking an in-flight
identity-linking flow — and drive a full IdP round trip. The exemption is a **prefix match**, so any
future state-changing route under `/auth/sso/` silently inherits zero CSRF protection.

**Remediation.** Replace the prefix match with an explicit route allowlist; enable
`MIDDLEWARE_HTTP_ORIGIN` by default, or do an explicit same-origin check before honouring `connect=1`.

---

## 5. Claims investigated and REFUTED

These are recorded so they are not re-raised. A source-only reading of
`lib/onetime/session.rb:63-71` suggests that `Onetime::Session` shadows Rack's `DEFAULT_OPTIONS` and
therefore loses Rack's own defaults. **It does not** — the guard is
`unless defined?(DEFAULT_OPTIONS)`, and Ruby's constant lookup finds the *inherited*
`Rack::Session::Abstract::Persisted::DEFAULT_OPTIONS` through the ancestor chain, so the constant is
never actually defined on the subclass and `self.class::DEFAULT_OPTIONS` resolves to Rack's.

Verified by instantiating the real class inside the booted application
(`poc/04-session-options-verification.rb`):

```
default_options keys: [:defer, :domain, :expire_after, :httponly, :partitioned,
                       :path, :renew, :secret, :secure, :secure_random, :sidbits]
  httponly                  = true
  path                      = "/"
  secure_random(@sid_secure) = SecureRandom
  @cookie_only              = true

sid sample: 10466bb9c7cf07bca4462ebfc3a3a2e6cf7b11be46a578b258bb13154f470bf2
REPRODUCIBLE AFTER srand()? false   (true would mean Kernel.rand, NOT a CSPRNG)
```

| Refuted claim | Reality |
|---|---|
| Session IDs from `Kernel.rand` (Mersenne Twister), predictable | `@sid_secure == SecureRandom`; ids are not reproducible after `srand()` — **CSPRNG confirmed** |
| Session cookie missing `HttpOnly` | `httponly = true` |
| Session id accepted from request params (`cookie_only` unset) | `@cookie_only = true`; live test with `?onetime.session=<sid>` set no cookie |
| Session cookie missing `Path` | `path = "/"` |

**Genuine residual in this area:** `find_session` (`lib/onetime/session.rb:441`) adopts any
well-formed sid presented in a *cookie* even with no stored blob. Because `Rack::Protection::CookieTossing`
ships off (`config.defaults.yaml:441`), an attacker who can set a cookie from a sibling subdomain
could fix a pre-auth session. Rodauth rotates the sid on login (`apps/web/auth/config/base.rb:89-91`),
which blocks post-login takeover, so this is bounded — but enabling `CookieTossing` is cheap.

---

## 6. Verified clean

Confirmed by testing or close reading; recorded so future reviews can skip them.

**Burn-after-reading holds under concurrency (REPRODUCED).** 10 simultaneous reveals of one secret:
exactly **1** response contained the plaintext (`poc/01-burn-after-read-race.sh`). The atomic
compare-and-set in `win_reveal_claim!`
(`lib/onetime/models/secret/features/secret_state_management.rb:172-189`) is correct, and `reveal!`
decrypts *inside* the won-claim branch so a losing racer never computes the plaintext.

**Passphrase brute-force is properly rate-limited (REPRODUCED).** v2 locks after 5 attempts per
secret+IP and returns `429` with `retry_after: 1800`. Rotating `X-Forwarded-For` on every attempt
**did not** bypass it — XFF is not trusted absent a configured trusted proxy
(`otto/lib/otto/utils.rb:158-176`). PoC: `poc/03-passphrase-ratelimit.sh`.

**CSP is strict and nonce-based (REPRODUCED).** Live header:
`default-src 'none'; script-src 'nonce-…'; object-src 'none'; base-uri 'self'; form-action 'self';
frame-ancestors 'none'`. No `unsafe-inline`, no `unsafe-eval`, not report-only. The app goes out of
its way to keep `unsafe-eval` out (Zod jitless mode, `src/plugins/core/configureZod.ts`).

**No CORS configuration exists** — no `Access-Control-Allow-*` header anywhere, no `rack-cors`. The
safe default.

**Host header injection: clean (REPRODUCED).** `POST /api/v1/share` with `Host: evil.example.com`
returned links on the configured `localhost:3000`, not the attacker host.

**No mass assignment.** No `.new(params)`, `update(params)`, or `merge!(params)` anywhere in `apps/`
or `lib/`. Every logic class reads named keys through `sanitize_identifier` / `sanitize_plain_text` /
`sanitize_email`.

**No unsafe deserialization.** Zero `Marshal.load`, `YAML.load`, `YAML.unsafe_load`, or `Psych.load`
in `lib/`, `apps/`, or Familia. `Familia::JsonSerializer` uses `Oj.load(source, mode: :strict)`.

**Lua scripting is safe.** Two `EVAL`/`EVALSHA` sites, both frozen script constants with keys/argv
passed separately — no interpolation (`lib/onetime/error_handler.rb:158-189`,
`lib/onetime/services/zset_indexer.rb:95-227`).

**Cryptography is sound.** Secret identifiers are 256-bit random + 64-bit HMAC tag
(`familia/lib/familia/verifiable_identifier.rb`), compared with `OpenSSL.secure_compare`.
Passphrases use Argon2id (`t_cost: 2, m_cost: 16, p_cost: 1`). Rodauth email tokens are
`SecureRandom.urlsafe_base64(32)` compared with `timing_safe_eql?`. A sweep for `rand(` / `Random.rand`
across `lib/` and `apps/` found **zero** uses in any token path. Root `SECRET` is mandatory and
fail-closed (`CHANGEME` is rejected; the `allow_nil` escape hatch is forcibly reset outside
development); all derived material uses RFC 5869 HKDF-SHA256 with per-purpose `info` strings.

**No committed secrets.** No private keys, Stripe/GitHub/Slack/SendGrid tokens in the tree or in
history. The only `AKIA` hits are AWS's published `AKIAIOSFODNN7EXAMPLE` placeholder in specs.
`.env.example` ships every secret blank, deliberately.

**Container and compose posture.** Non-root (`USER appuser`), digest-pinned base images, no build
secrets in ARG/ENV, healthchecks present, s6-overlay SHA-256 verified. No datastore port published
to the host — Valkey and RabbitMQ use `expose:`, not `ports:`. Compose uses `${VAR:?error}` so a
missing secret aborts rather than defaulting.

**CI/CD.** The single `pull_request_target` workflow (`pr-labeler.yml`) has **no checkout step** at
all — the dangerous pattern does not occur. No Actions script injection: every `github.event.*`
reference is in an `if:` condition, never a `run:` body.

**Request logging is fail-closed.** Params and headers use an allowlist that is **empty by default**
(`request_logger.rb:151-176`), so enabling debug capture reveals no param or header values until an
operator explicitly names safe fields. Sentry scrubbing covers URL, transaction, Referer, and span
data, and fails closed to `[SCRUBBING_FAILED]`.

**SSO issuer scoping is well built.** Identities are keyed `(provider, issuer, uid)` with a real
unique index (`migrations/008_issuer_scoped_identities.rb:83`). OAuth `state` is validated in both
stacks with `secure_compare`, empty state rejected, `provider_ignores_state` left false. No
`omniauth.origin` handling exists — every post-callback redirect is a hardcoded literal, so **there
is no open-redirect surface**. SSRF is defended at save time (`ssrf_protection.rb:48-63`, https-only,
blocks resolved internal IPs, fails closed on empty resolution) and at request time
(`oidc_http_pinning.rb`, per-request IP pinning that refuses to run through a forward proxy).

**SSO link confirmation is sound.** 256-bit tokens, 300s/900s TTLs, consumed atomically via
`delete! == 1` *before* any credential check (closing the load-then-delete TOCTOU), rate-limited
before consumption, Phase-4 token delivered only to the on-file address (never the IdP-asserted one),
and fails closed on delivery failure.

**Colonel/admin API.** All 87 routes carry `auth=sessionauth role=colonel`, and every logic class
independently calls `verify_one_of_roles!(colonel: true)`. `has_system_role?` additionally requires
`cust.verified?`. Admin network isolation resolves the client IP through Otto's trusted-proxy walk
and requires `otto.via_trusted_proxy` before honouring a forwarded host — **not spoofable by default**.

**Rhales hydration escaping.** The JSON bootstrap blob escapes `<`, `>`, `&`, U+2028, U+2029
(`rhales/lib/rhales/utils/json_serializer.rb:38-46`) — escaping `<` covers both `</script>` and
`<!--` — and is delivered as `type="application/json"` + `JSON.parse`, not an inline assignment. Only
one raw `{{{ }}}` interpolation exists in the entire codebase (`{{{vite_assets_html}}}`), built
entirely from the Vite manifest and the server nonce, with no request-derived data.
