# Security Assessment 02 — Authorization, Multi-Tenant Isolation, IDOR, Privilege Escalation, Mass Assignment

**Target:** OneTimeSecret (`/home/user/onetimesecret`), deps `familia` (Redis ORM), `otto` (web framework)
**Branch:** `claude/vigilant-goldberg-97ijfl`
**Scope:** API authorization enforcement, tenant/org isolation, IDOR, privilege escalation (colonel), mass assignment, invite flow, incoming feature.
**Method:** Read-only source review. Evidence cited as `file:line`. Findings tagged CONFIRMED / NEEDS-VALIDATION.
**Date:** 2026-06-22

---

## Executive Summary

The authorization architecture is **mature and largely sound**. It centers on an entitlement-based model
(`require_entitlement!` / `require_entitlement_in!`) layered over org membership, with a system-level
"colonel" superuser role gated by a verified-email requirement. Secrets/receipts use a possession-based
access model backed by HMAC-signed, 256-bit unguessable identifiers, which neutralizes the obvious IDOR
class for that data.

**No Critical or High severity exploitable issues were confirmed.** The most valuable hardening items are
Medium-severity defense-in-depth gaps: an inconsistent authorization path on member removal, sensitive
internal identifiers exposed in organization `safe_dump`, an organization `create!` mass-assignment splat,
and a model-layer `change_role!` that accepts `'owner'` without a guard. Several NEEDS-VALIDATION items
depend on deployment configuration (extid HMAC secret, proxy IP resolution, presence of an upstream rate
limiter).

### Top Findings

| # | Severity | Status | Finding | Evidence |
|---|----------|--------|---------|----------|
| F1 | Medium | CONFIRMED | `RemoveMember` is the only member-mgmt endpoint NOT using `require_entitlement_in!`; relies on raw role-string checks (inconsistent, not fail-closed-by-entitlement) | `apps/api/organizations/logic/members/remove_member.rb:39-58,135-181` |
| F2 | Medium | CONFIRMED | Organization `safe_dump` leaks internal `objid`/`identifier`, owner's `owner_id`/`created_by` custid, and billing/contact emails to any active member | `lib/onetime/models/organization/features/safe_dump_fields.rb:17-29` |
| F3 | Medium | NEEDS-VALIDATION | `Organization.create!` forwards an open `**` splat into `new` — `planid`/`is_default`/Stripe/`complimentary` mass-assignable IF any caller forwards user params | `lib/onetime/models/organization.rb:431-437`; `with_organization_billing.rb:32-61` |
| F4 | Medium | NEEDS-VALIDATION | `OrganizationMembership#change_role!` rejects `colonel` but ACCEPTS `owner` with no caller/last-owner guard at the model layer | `lib/onetime/models/organization_membership.rb:258-274` |
| F5 | Medium | NEEDS-VALIDATION | Organization `extid` derived with plain SHA-256, no keyed HMAC `secret:` — defense-in-depth gap if an `objid` ever leaks (and objid IS leaked by F2) | `lib/onetime/models/organization.rb:46`; `familia/lib/familia/features/external_identifier.rb:323-336` |
| F6 | Low | CONFIRMED | Receipt `safe_dump` exposes creator's `owner_id` via possession-based (unauthenticated) receipt/burn/batch endpoints | `lib/onetime/models/receipt/features/safe_dump_fields.rb:56-57`; `apps/api/v3/logic/secrets.rb:216-255` |
| F7 | Low | CONFIRMED | `show_invite` (noauth) discloses inviter email + `account_exists` boolean to any token holder | `apps/api/invite/logic/base.rb:51-64`; `apps/api/invite/logic/invites/show_invite.rb:97-99` |
| F8 | Low | CONFIRMED | `Customer.create!` has no allowlist guard — `role`/`verified` mass-assignable at model layer; safe only by caller discipline (all hardcode `'customer'`) | `lib/onetime/models/customer.rb:271-313`; `status.rb:23` |
| F9 | Low–Medium | NEEDS-VALIDATION | Incoming `/secret` and `/validate` (anonymous) have no in-logic rate limiter; each `/secret` enqueues an email to a configured recipient | `apps/api/incoming/logic/create_incoming_secret.rb:216-235` |
| F10 | Low | NEEDS-VALIDATION | Invite noauth rate limiter is high (100/10min) and falls back to a shared `0.0.0.0` IP bucket if proxy IP not resolved | `lib/onetime/security/invite_token_rate_limiter.rb:31-38` |
| F11 | Info/Positive | CONFIRMED | Colonel role: granted only via Redis `role` field (CLI), checked at edge (`role=colonel`) + every one of 22 logic actions; verified-email gate | see Section 4 |
| F12 | Info/Positive | CONFIRMED | Secrets/receipts use HMAC-signed 256-bit identifiers (no committed default secret) — possession model is sound | `familia/lib/familia/verifiable_identifier.rb:45-71` |

---

## 1. API Authorization Enforcement

### How the current principal is resolved
- Authentication is post-routing (Otto `RouteAuthWrapper`), not middleware. Strategies live in
  `lib/onetime/application/auth_strategies/*`. The authenticated `Customer` is exposed to logic as `cust`.
- **Organization context** (`auth_org` / `auth_membership`) is resolved by
  `lib/onetime/application/organization_loader.rb`. Selection priority: `O-Organization-ID` header →
  session `organization_id` → custom-domain host → customer `default_org_id` → `is_default` org → first org → nil.
- The client-controllable `O-Organization-ID` header is **validated** with `org.member?(customer)` AND
  domain-scope (`can_access_domain?`) before use — `organization_loader.rb:242-267`. A user cannot select
  an org they are not a member of. **CONFIRMED safe.**

### How ownership/entitlement is enforced
- The canonical gate is `require_entitlement!(entitlement)` (`lib/onetime/logic/base.rb:183-256`) and
  `require_entitlement_in!(org, entitlement)` (`:271-318`). Both are **fail-closed**: missing
  org/membership/inactive-membership raise; anonymous users in `require_entitlement_in!` are rejected.
  Colonels bypass via `has_system_role?('colonel')`.
- `require_entitlement_in!` always resolves the target org from the URL `extid` (`load_organization`) and
  then checks the *caller's* membership in that specific org — so changing the `extid` param to another
  org fails the membership/entitlement check. **CONFIRMED safe** across organizations, domains, invitations.

### GetAccount and self-scoped reads
- `apps/api/account/logic/account/get_account.rb:32-41` returns the session `cust` only (no param-based
  customer lookup). No account IDOR. The full account API operates on `cust`, not on client-supplied IDs.

---

## 2. Tenant / Organization Isolation

### Identity model (CONFIRMED, Info)
- `objid` = internal UUIDv7 primary key; `extid` (format `on<id>s`) = public ID derived from objid.
  `find_by_extid` does an explicit `extid_lookup` and returns nil on miss (no scan/enumeration).
- `find_by_org_customer(org.objid, cust.objid)` (`organization_membership.rb:635-640`) uses a deterministic
  composite key — scoped to both org and customer objids, so no cross-org membership confusion.
- `Organization#owner?` (`organization.rb:101-106`) and `#member?` (`:112-123`) check the membership record
  scoped to this org. `owner?` requires an active membership with `role == 'owner'`. No cross-org collision.

### Effective entitlements (CONFIRMED, Info, with notes)
- `ROLE_ENTITLEMENTS` (owner ⊇ admin ⊇ member) at `organization_membership.rb:102-106`.
- Membership `can?` → materialized set or `compute_entitlements_from_role`. Effective =
  `(org.entitlements ∩ ROLE_ENTITLEMENTS[role]) + membership_grants − membership_revokes`
  (`organization_membership/features/with_materialized_entitlements.rb:100-140`).
- **Note (Low, NEEDS-VALIDATION):** membership-level grants are unioned *after* the org∩role intersection,
  so an operator grant can exceed the role/plan ceiling. Intentional override design; grants are
  operator-only today (no production endpoint writes membership grants), so not currently reachable.
- **Note (Low, NEEDS-VALIDATION):** a nil role defaults to `member` (`:92,:231`) — fail-open-to-member
  rather than fully fail-closed. Defensible but worth tightening.

### F1 — RemoveMember authorization inconsistency (Medium, CONFIRMED)
`apps/api/organizations/logic/members/remove_member.rb` is the **only** member-management endpoint that
does NOT call `require_entitlement_in!(org, 'manage_members')`. Every sibling does
(`create_invitation.rb:42`, `revoke_invitation.rb:25`, `resend_invitation.rb:28`, `list_invitations.rb:24`,
`update_member_role.rb:45`, `delete_organization.rb:38`). Instead it relies on raw **role-string** checks
in `validate_removal!` (`remove_member.rb:135-181`).
- **Not directly exploitable today:** a plain `member` falls to the `else` branch and is denied (`:174-179`).
- **Risk:** it diverges from the entitlement model the rest of the app uses; a stale/elevated role string,
  or an operator membership-level revoke of `manage_members`, would not be honored. The code comments
  (`organization_membership.rb:62-65`) explicitly state authority should live in entitlements, not role
  strings.
- **Remediation:** adopt `require_entitlement_in!(@organization, 'manage_members')` for consistency and
  fail-closed alignment.

### F2 — Organization safe_dump leaks internal/cross-tenant data (Medium, CONFIRMED)
`lib/onetime/models/organization/features/safe_dump_fields.rb`:
- `:objid` (`:18`) and `:identifier` (`:17`, == objid) — internal UUID the opaque-ID design is meant to hide
  (`organization.rb:10-30`). Exposing it defeats the opaque-ID pattern and, combined with F5, lets a holder
  derive the extid.
- `:owner_id` (`:22`) and `:created_by` (`:27`) — the owner's Customer custid. `get_organization.rb:38`
  requires only `api_access`, so **any active member** (including a plain member) sees the owner's custid.
- `:contact_email` / `:billing_email` (`:29`) — tenant-internal PII visible to every member.
- `:entitlements` / `:limits` (`:41-51`) — org-level capability set, broader than the caller's own `can?` set
  (capability disclosure; confirm the frontend gates on membership entitlements, not org entitlements).
- **Good news (CONFIRMED):** `stripe_customer_id`, `stripe_subscription_id`, `email_hash`,
  `subscription_status` are **NOT** in safe_dump (`with_organization_billing.rb:31-76` vs the dump list).
- **Remediation:** remove `objid`/`identifier`/`owner_id`/`created_by` from org safe_dump; gate billing
  emails to `manage_billing`/`manage_org` holders.

### Domain config / cross-domain (CONFIRMED, mostly safe)
- Domain config endpoints (`apps/api/domains/policies/domain_config_authorization.rb:152-168`) load domain by
  extid, resolve owning org, require `manage_org`, check the org plan entitlement, AND enforce per-membership
  domain scope (`can_access_domain?`, `organization_membership.rb:286-290`). Strong, layered.
- `GetDomain` / `RemoveDomain` (`apps/api/domains/logic/domains/get_domain.rb`, `remove_domain.rb`) load by
  extid, check `accessible_by?` (org owner/member), require `custom_domains` entitlement, and enforce domain
  scope. Consistent and fail-closed.
- `AddDomain` (`add_domain.rb`) resolves an explicit `org_id` param via `resolve_target_organization`
  (returns only orgs where `org.member?(@cust)`) and then re-checks `require_entitlement_in!(org,
  'custom_domains')` — the entitlement check is the real authority, so the looser `member?` gate on
  resolution does not weaken it. CONFIRMED safe. It also rejects domains already owned by another org
  (`:80-89`), preventing cross-tenant domain takeover.

---

## 3. IDOR — Secrets, Receipts, Domains, Orgs, Memberships

### Possession-based model (CONFIRMED, Info — F12)
Secrets and Receipts are accessed by identifier alone, intentionally:
`apps/api/v2/logic/secrets/burn_secret.rb:15-27` documents that the receipt URL is the credential. This is
safe **because** identifiers are HMAC-signed 256-bit random values minted by
`Familia::VerifiableIdentifier` (`familia/lib/familia/verifiable_identifier.rb:45-88`), which refuses a
committed default secret (`KeyError` if `VERIFIABLE_ID_HMAC_SECRET` unset) — fail-closed. The `Secret#owner?`
(`secret.rb:78-80`) and `Receipt#owner?` (`receipt.rb:148-150`) predicates are used only for display flags
(e.g. `is_owner`), not for access control on show/burn — by design.

- `update_receipt` (mutation) correctly DOES check ownership: `raise OT::Unauthorized ... unless
  receipt.owner?(cust)` (`apps/api/v2/logic/secrets/update_receipt.rb:30`). Good contrast — writes are
  owner-gated, reads are possession-gated.
- `list_receipts` correctly scopes by the authenticated customer / org (`auth_org.receipts`) / domain
  (`domain.accessible_by?(cust)`) — `apps/api/v2/logic/secrets/list_receipts.rb:121-169`. No IDOR.

### F6 — Receipt safe_dump owner_id disclosure (Low, CONFIRMED)
Receipt `safe_dump` emits `owner_id` (`lib/onetime/models/receipt/features/safe_dump_fields.rb:56-57`).
Because receipt show/burn/`ShowMultipleReceipts` are possession-based and reachable anonymously
(`apps/api/v3/logic/secrets.rb:216-255` returns `safe_dump` for up to 25 receipts by id), anyone holding a
receipt identifier learns the creator's internal customer objid. Low severity (identifier is unguessable and
typically only the creator holds it), but the internal ID need not be in the dump.
- **Remediation:** remove `owner_id`/`custid` from receipt safe_dump, or strip them in the
  possession-based serialization path.

---

## 4. Privilege Escalation — Colonel (Admin) Role

**No exploitable escalation path found.** (CONFIRMED — F11, positive.)

- **Grant mechanism:** colonel = the Customer Redis `role` field set to `'colonel'`
  (`lib/onetime/models/customer/features/status.rb:23`). The only production writer is the CLI
  (`lib/onetime/cli/customers/role_command.rb:85`). The config-based `ColonelAssignment.colonel?(email)`
  (`colonel_assignment.rb:43-51`) has **no production callers** — dead code; there is no email→colonel
  auto-promotion.
- **Edge check:** every colonel route declares `auth=sessionauth role=colonel`
  (`apps/api/colonel/routes.txt:10-50`). `role=colonel` is matched against `metadata[:user_roles]`, which
  `SessionAuthStrategy` populates from the freshly-loaded Customer record
  (`session_auth_strategy.rb:25-29`) — server-side, not client-supplied.
- **Logic check:** all **22** colonel logic actions independently call `verify_one_of_roles!(colonel: true)`
  in `raise_concerns` (e.g. `update_user_plan.rb:28`, `delete_secret.rb:19`,
  `manage_entitlement_override.rb:74`, `get_user_details.rb:19`). No action relies solely on routes.txt.
- **Verified-email gate:** `has_system_role?('colonel')` returns false unless `cust.verified?`
  (`lib/onetime/application/authorization_policies.rb:52-68`) — defense against registering an admin email
  before the legitimate owner verifies.
- **role_index** (`customer/features/role_index.rb`) is a derived read-side projection; authorization never
  reads it, so poisoning it (which requires Redis write access) cannot grant runtime colonel. Low.

### F8 — `role`/`verified` mass-assignable at Customer model layer (Low, CONFIRMED)
`Customer.create!` forwards `**kwargs` to `super` with no allowlist (`customer.rb:271-313`), and `role`,
`verified`, `verified_by` are plain writable fields (`status.rb:23-26`). `Customer.create!(role: 'colonel')`
works at the Ruby level. **Safe today only because every signup path hardcodes** `role = 'customer'`
(`create_account.rb:100,104`; `apps/web/auth/operations/create_customer.rb:62-64`;
`sync_session.rb:175-178`). Any future endpoint that forwards request params as `**kwargs` would become a
privilege-escalation vector.
- **Remediation:** strip/reject `role`, `verified`, `verified_by` from externally-sourced kwargs in
  `Customer.create!` rather than relying on caller discipline.

---

## 5. Mass Assignment / Over-Posting

**No exploitable over-posting vulnerability found.** (CONFIRMED.) Every create/update endpoint reads named
params individually and assigns to specific, validated fields. No production code passes a raw params hash
into a model constructor or bulk setter. Grep across `apps/**` + `lib/**` (excluding specs) for
`.new(params)`, `.new(**params)`, `.create!(**params)`, `from_hash(params)`, `.merge(params`, `params.each`
→ zero production hits.

### ORM capability (the latent risk surface)
- `familia/lib/familia/horreum.rb:446` `initialize_with_keyword_args` sets any declared field from kwargs
  (no field-level allowlist).
- `apply_fields` / `multi_field_update` (`familia/lib/familia/horreum/persistence.rb:371,427,522`) call
  `guard_allowed_fields!` (`:761`) which only blocks *undeclared* fields — it does NOT protect declared
  sensitive fields. The protection lives entirely in the application layer.

### Endpoint review (all CONFIRMED safe)
- `create_account.rb` — reads login/password/skill; hardcodes role/verified.
- `update_account_field.rb` — abstract base; each subclass hardcodes a single field. `UpdateLocale`,
  `UpdateDomainContext`, `UpdatePassword`, `UpdateNotificationPreference`. None allow role/verified/planid.
- `update_notification_preference.rb:50-61` — the only dynamic `send("#{field}=")`, constrained by
  `VALID_FIELDS = %w[notify_on_reveal]` allowlist (re-checked in `perform_update`), value coerced to bool.
- `create_organization.rb` / `update_organization.rb` — positional/named args only; update writes only
  display_name/description/billing_email/contact_email behind `manage_org`.
- `update_member_role.rb` — `VALID_ROLES = %w[member admin]`, rejects `owner`.
- `welcome.rb` (billing) — only Stripe-derived keys; never request params.

### F3 — Organization.create! open splat (Medium, NEEDS-VALIDATION)
`lib/onetime/models/organization.rb:431-437`:
```ruby
org = new(display_name:, owner_id: owner_customer.custid, created_by: owner_customer.custid,
          contact_email:, **)
```
`owner_id`/`created_by` are fixed from the trusted positional `owner_customer` arg (safe). But the open `**`
splat means sensitive fields (`planid`, `is_default`, `stripe_customer_id`, `stripe_subscription_id`,
`complimentary`, `subscription_status` — all plain fields per `organization.rb:70`,
`with_organization_billing.rb:32-61`) become mass-assignable IF any caller forwards user params. Today the
only caller (`create_organization.rb:99`) passes a fixed positional set — safe. Recommend an explicit
allowlist instead of the open splat.

---

## 6. Invite Flow

**Well-designed; most attacker hypotheses are mitigated.** (CONFIRMED.)

- **Token (A1):** `SecureRandom.urlsafe_base64(32)` (256-bit), indexed via `token_lookup`
  (`organization_membership.rb:552,576,599-606`). Not derived/sequential.
- **Email binding (A2):** accept enforces normalized `invitation.invited_email == cust.email` at logic
  (`apps/api/invite/logic/invites/accept_invite.rb:72-84`) AND model (`organization_membership.rb:331-334`)
  AND Rodauth signup (`apps/web/auth/operations/accept_invitation.rb:56-58`). A different-email attacker
  cannot accept someone else's invite.
- **Role escalation (A3):** role comes only from the server-stored invitation
  (`accept_invite.rb:105,113,125`; `activate!` `organization_membership.rb:394,407`); `process_params` parses
  only `token`. Owner invites blocked at creation (`create_invitation.rb:59-66`). Not possible.
- **Replay / revoke / expiry (A4):** single-use (token removed from lookup on accept,
  `organization_membership.rb:339-341,417`), double-accept guard (`:319-322`,
  `accept_invite.rb:51-59`), 7-day TTL + `expired?` checks (`:196-201`, `accept_invite.rb:62-69`), revoke
  destroys the model (`:477-493`). Tokens cannot be replayed or accepted after revoke/expiry.
- **signup_and_accept (A5):** email derived from the invite token, not user input
  (`signup_and_accept.rb:62-65`); org/role server-controlled. Cannot forge arbitrary org membership.
- **Authorization/scoping (A6):** create/resend/revoke require `manage_members` in the extid-named org;
  resend/revoke additionally verify the invitation belongs to that org (`resend_invitation.rb:43-44`,
  `revoke_invitation.rb:40-41`). Domain-scoped members are forbidden from member ops. Changing `extid` to an
  unmanaged org fails the entitlement check.

### F7 — show_invite information disclosure (Low, CONFIRMED)
`GET /api/invite/:token` (noauth) returns org name+extid, invited email, role, **inviter's email**, expiry,
and an **`account_exists` boolean** to any token holder (`apps/api/invite/logic/base.rb:51-64`;
`show_invite.rb:97-99`). The token holder is the intended recipient, so most of this is acceptable; the
marginal leak is the inviter's email and the account-existence oracle. Low (token is 256-bit, rate-limited).
Product decision recommended on exposing inviter email pre-accept.

### F10 — Invite rate limiter (Low, NEEDS-VALIDATION)
`lib/onetime/security/invite_token_rate_limiter.rb:31-38`: 100 attempts / 600s per IP. Against a 256-bit
token, brute force is infeasible regardless, so this is an abuse/DoS control more than an anti-enumeration
one. IP falls back to `'0.0.0.0'` when `metadata[:ip]` is absent — verify the production proxy populates the
real client IP (`lib/onetime/application/auth_strategies/helpers.rb`) so the limiter buckets correctly.

---

## 7. Incoming Feature

**Anonymous by design; abuse constrained by recipient-hash indirection and per-domain entitlement gating.**

- **Anonymous endpoints (B1):** all three routes are `noauth` (`apps/api/incoming/routes.txt:22-24`;
  `auth_strategies.rb:24-27`). Intentional (anonymous tip submission). Senders supply an opaque SHA256 hash
  of the recipient, never a raw email; the backend resolves hash→email server-side
  (`create_incoming_secret.rb:57,168`).
- **Domain context (B4):** derived from the validated `Host` header by middleware
  (`lib/onetime/middleware/domain_strategy.rb:104-138`), not a client body param. The resolver enforces
  strict per-domain separation (canonical YAML recipients vs per-domain Redis config, no cross-fallback,
  `recipient_resolver.rb:39-100`). A hash valid on domain A will not resolve via domain B's config. No
  cross-tenant injection.
- **Ownership/entitlement (B3):** per-domain config is 1:1 with a CustomDomain
  (`custom_domain/incoming_config.rb:46-49`); on custom domains all three endpoints require the domain-owning
  org to hold `incoming_secrets` (`create_incoming_secret.rb:71`, `get_config.rb:43`,
  `validate_recipient.rb:38`), failing closed for orphaned domains
  (`lib/onetime/incoming/recipient_resolver.rb:117-146`).
- **Recipient resolution (B5):** resolved email re-validated via Truemail before notification
  (`create_incoming_secret.rb:86-98`); entitlement checked before Redis I/O to avoid existence/timing leaks.

### F9 — No in-logic rate limit on anonymous incoming submit (Low–Medium, NEEDS-VALIDATION)
`GET /api/incoming/config` publishes the recipient list (hash + display_name)
(`apps/api/incoming/logic/get_config.rb:56-60`), so valid hashes are not secret (recipient *emails* are still
not recoverable). Neither `/secret` nor `/validate` applies a rate limiter in its logic class, and each
`/secret` enqueues an email to a configured recipient (`create_incoming_secret.rb:216-235`). If no upstream
middleware limiter exists, an attacker can spam configured recipients or flood Redis with anonymous secrets.
**Validate** whether an upstream per-IP limiter is applied; if not, add one. Medium absent any limiter,
otherwise Low.

---

## Consolidated Remediation Priorities

1. **F1** — Add `require_entitlement_in!(@organization, 'manage_members')` to `RemoveMember`.
2. **F2 / F6** — Remove internal IDs (`objid`/`identifier`/`owner_id`/`created_by`) and gate billing emails
   in Organization safe_dump; remove `owner_id`/`custid` from Receipt safe_dump.
3. **F3 / F8** — Replace open `**` splats in `Organization.create!` / `Customer.create!` with explicit
   allowlists (reject `role`, `verified`, `planid`, `is_default`, Stripe/billing fields from external input).
4. **F4** — Make `OrganizationMembership#change_role!` reject `'owner'` (force a dedicated
   `transfer_ownership!` with a last-owner check) so the only protection isn't one endpoint's validator.
5. **F5** — Configure a keyed `secret:` for the Organization `external_identifier` so extids are not
   forgeable/derivable from a leaked objid.
6. **F9 / F10** — Verify/add anonymous rate limiting on incoming submit; verify production proxy IP
   resolution for the invite limiter.
7. **F7** — Product decision on exposing inviter email + account-existence in `show_invite`.

## Verified-Safe Areas (no action needed)
- Entitlement gating across v1/v2/v3 secrets, account, domains, organizations, invitations (fail-closed).
- `O-Organization-ID` header is membership- and domain-scope-validated (no org spoofing).
- Colonel role: server-side `role` field, edge + 22/22 logic checks, verified-email gate, no config
  auto-promotion, role_index is non-authoritative.
- Possession-based secret/receipt model backed by HMAC-signed 256-bit identifiers (no committed default).
- Mass assignment: no production raw-params sink; dynamic setters are allowlisted.
- Invite flow: unguessable single-use tokens, strict email binding, server-controlled role, expiry +
  revocation enforced, org-scoped management.
- Incoming: per-domain entitlement gating, server-derived host, strict per-tenant recipient separation.
