# Privy Links

Behavioral specification for privy links: reusable, non-guessable, rotatable
URLs (`/ps/:token/join`) that admit their holder to a scope — the install, an
organization, or a custom domain — without opening public signup. Status:
proposed (pre-implementation).

Prior art: Rocket.Chat registration mode "Secret URL" (instance scope);
Keycloak organization invitation links, Kinde org invites, Kodus/Cal.com team
invite links (organization scope, rotation-as-revocation).

## Overview

A privy link is **one user-facing artifact backed by two separate policies**:

1. **Account creation** — "may the holder create an account on this host at
   all?" Owned by the signup opt-in resolution chain (`SignupConfig`,
   ADR-024) and enforced by the signup gates
   (`Core::Controllers::Base#signup_enabled?` in simple mode,
   `Auth::SignupEnabled` in full mode).
2. **Membership attachment** — "which organization does the holder join, at
   which role and scope?" Owned by `OrganizationMembership.ensure_member!`,
   the same convergence point used by emailed invitations, SSO, and SCIM.

These policies are deliberately NOT merged, mirroring the
`SigninConfig`/`SignupConfig` split (see `apps/web/auth/signup_enabled.rb`
header on `claude/signinconfig-restrict-to-3lddoo`): a privy grant is a third
*input* to the existing model-owned resolvers, never a parallel resolution
chain.

The distinction the URL path resolves: `/ps/:token/join` uses one verb —
"join" — because signup-vs-join is not two semantics but one ceremony whose
first step (account creation) is skipped when the visitor is already
authenticated.

## The `PrivyLink` model

`PrivyLink < Familia::Horreum`, Redis-backed (a rotatable token cannot live in
boot-time YAML config).

| Field | Semantics |
|---|---|
| `token` | `SecureRandom.urlsafe_base64(32)` (256-bit, same strength as invitation tokens). `unique_index :token` for `/ps/:token` lookup. |
| `scope_type` | `instance` \| `organization` \| `domain` |
| `scope_id` | nil for `instance`; `organization.objid` or `custom_domain` identifier otherwise |
| `role` | Validated to `member` only. Admin/owner roles are never grantable by link — email invite or promotion only (existing RBAC stance: owner invites are rejected even in `CreateInvitation`). |
| `expires_at` | Default 7 days (parity with `INVITATION_TTL_SECONDS`); plan-gated up to 30 days or non-expiring. Lazy check at accept, matching the membership model's expiry idiom (no Redis TTL — one expiry idiom, not two). |
| `max_uses` / `use_count` | Optional cap; counter incremented atomically (Lua/`HINCRBY`) at accept so concurrent joins cannot race past the cap. |
| `allowed_email_domains` | Optional restriction checked at accept (Kinde-style bound links). |
| `revoked_at`, `created_by`, `created_at` | Rotation-as-revocation plus audit trail. |

**One active link per scope.** "Regenerate" = revoke + create: rotates the URL
and invalidates every outstanding copy at once, with no per-copy tracking.

## Scope semantics

| `scope_type` | Holder gets | Attach mechanism |
|---|---|---|
| `instance` | An account only (self-hosted "Secret URL" mode) | none |
| `organization` | Account if needed + unscoped org membership as `member` | `ensure_member!(provisioning_source: 'privy_link')` |
| `domain` | Account if needed + **domain-scoped** org membership | same, with `domain_scope_id` set to the domain |

A domain-level privy link joins the **organization that owns the domain** —
there is no membership anywhere else to join — but scoped via the existing
`OrganizationMembership#domain_scope_id` field. Domain-scoped members are
already excluded from `manage_members` surfaces by the invitation logic
classes; a domain-scoped joiner sees the branded domain's world and none of
the org's admin surface.

## Existence precondition

A privy path is only live when the operator has opted into privy mode
(`signup_mode: privy`, see below). A hard-disabled instance
(`site.authentication.enabled: false` / `AUTH_ENABLED=false`) has **no privy
path at all** — privy narrows the existing resolution, it never re-opens a
hard off. AND-narrowing semantics per ADR-024.

`signup_mode: public | privy | off` replaces the boolean `signup_enabled` on
the per-domain `SignupConfig` (Redis, runtime-editable, default-off for custom
domains). Instance-level privy requires a small instance-scoped Redis sibling
of `SignupConfig`, since global config has no runtime mutation path.

## The `/ps/:token/join` ceremony

```
token lookup ──▶ revoked/expired? ──▶ max_uses (atomic INCR) ──▶
email domain allowed? ──▶ plan quota (ROLE_LIMIT_RESOURCES, org/domain
scopes only) ──▶ [signed out: create_account with privy grant] ──▶
attach per scope table ──▶ done
```

- Signed-out visitor: registration form; the privy token is the grant that
  satisfies the signup gate for that request. Signed-in visitor: attach only.
- The grant must satisfy the gate for the **whole ceremony** —
  `create_account`, `verify_account`, `verify_account_resend` (the
  `Auth::SignupEnabled::GATED_ROUTES` set) — or privy signups on an
  otherwise-closed host would strand at email verification.
- Any gate failure produces a typed error with **no state change**.
- `ensure_member!` makes the attach idempotent: clicking twice never
  double-adds, and a holder with a pending emailed invitation who joins via
  link converges on one membership. (Implementation must verify the staged
  emailed invitation is reaped by the lazy ghost cleanup in
  `Organization#list_pending_invitations` rather than left counting against
  `pending_invitation_count`.)

## Security model

| Property | Rule |
|---|---|
| Email verification | A shared link proves possession of a URL, not inbox ownership. Privy joiners get **no** `verified_by = 'invite_token'` shortcut (unlike `apps/web/auth/operations/accept_invitation.rb`); normal email verification always runs. |
| Privilege | `member` role only; domain scope where applicable. No link grants admin/owner. |
| Reject shape | Invalid/rotated/expired token → 404 byte-identical to an undefined route (`Auth::RestrictTo.not_found_response`, ADR-034 reject-as-not-found), so responses are no enumeration oracle. |
| Enumeration | Token lookup behind a sibling of `Onetime::Security::InviteTokenRateLimiter`. |
| Policy read failure | Raises `Onetime::SignupPolicyUnavailable` → 503, not a fail-closed 404, same carve-out rules as the sign-in/sign-up gates (#4157). |
| Leak recovery | Rotation. Regenerating the link is the revocation mechanism. |
| Blast radius | A leaked instance-scope link yields an unverified, unaffiliated account. A leaked org/domain link yields at most an unverified `member` (scoped, for domain links), subject to quota, expiry, `max_uses`, and email-domain restriction. |

Optional belt to this suspender: `Organization#requires_admin_approval?`
(currently hardcoded false, machinery present in `accept!`) can gate
link-joins as `status='accepted'` pending admin activation.

## Frontend

- `/ps/:token/join` joins the intentionally-ungated route set (like
  invite-accept and verify-account) in `handleDisabledAuthFeature`
  (`src/router/guards.routes.ts`) — reachable even when
  `authentication.signup` is false.
- `signup_mode` replaces the boolean across the config contract surface:
  bootstrap `config_serializer.rb`, Zod schemas
  (`src/schemas/contracts/config/public.ts`,
  `src/schemas/shapes/config/section/site.ts`), the router guard, and
  `DomainSignupConfigForm.vue`. Serializers must keep exposing a boolean
  `signup` (= `signup_mode == 'public'`) for existing consumers.

## Dependencies and sequencing

1. **Base:** `claude/signinconfig-restrict-to-3lddoo` — provides
   `Auth::SignupEnabled` (the seam the privy grant threads through),
   `Auth::RestrictTo.not_found_response`, and the fail-closed resolution
   rules. Privy work stacks on top of it.
2. `PrivyLink` model + tryouts (gates, atomic counter, rotation).
3. `signup_mode` on `SignupConfig` + instance-scoped sibling; resolver gains a
   `privy_grant:` input (resolution stays model-owned, ADR-034).
4. Management endpoints, mirroring `apps/api/organizations/logic/invitations/`:
   `POST|GET|DELETE /:extid/privy-links` behind
   `require_entitlement_in!(org, 'manage_members')`; domain-scoped members
   forbidden. Instance scope: colonel-only.
5. Public ceremony endpoints: `GET /ps/:token/join` (preview: scope name,
   role), `POST /ps/:token/join`.
6. Frontend contract + join page.
7. Optional phase 2: admin-approval gating for link-joins.

## Implementation References

- `lib/onetime/models/organization_membership.rb` — `ensure_member!`,
  `domain_scope_id`, token index pattern, `INVITATION_TTL_SECONDS`
- `lib/onetime/models/custom_domain/signup_config.rb` — resolution chain the
  privy grant extends (`resolve_signup_enabled_for_request`)
- `apps/web/auth/signup_enabled.rb` (signinconfig branch) — full-mode gate and
  `GATED_ROUTES`
- `apps/web/auth/operations/accept_invitation.rb` — signup-hook pattern reused
  *minus* the `verified_by` shortcut
- `lib/onetime/security/invite_token_rate_limiter.rb` — rate-limiter pattern
- `docs/adr/adr-024-custom-domain-auth-override-resolution.md`,
  `docs/adr/adr-034-restrict-to-enforcement.md` — resolution ownership and
  reject-shape rules
