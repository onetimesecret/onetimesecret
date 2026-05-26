---
title: Organization Invites
type: reference
status: draft
updated: 2026-05-25
summary: Invite lifecycle, API surface, and the dimensions that matter for SaaS invite flows
---

# Organization Invites

End-to-end flow from "owner clicks invite" to "invitee is an active org member." The lifecycle is one record (`OrganizationMembership`) progressing through states; the token is the unguessable handle that drives the invitee's view.

## Lifecycle

`OrganizationMembership.status` is the FSM. Token is set during `pending`, cleared on terminal transitions.

| State | Set by | Token | Indexed in |
|-------|--------|-------|------------|
| `pending` | `Organization#invite_member` | yes | `token_lookup`, `org_email_lookup`, `pending_invitations` |
| `accepted` | `accept!` when `requires_admin_approval?` returns true (gated; awaiting approval workflow) | nil | none |
| `active` | `activate!` (auto-promoted from `accept!`) | nil | `org.members`, `org_customer_lookup` |
| `declined` | `decline!` | nil | none |
| expired | implicit (`pending_at + 7d`) | yes (until cleanup) | unchanged |
| revoked | `revoke!` | — | record destroyed |

`lib/onetime/models/organization_membership.rb` is the canonical reference. `INVITATION_TTL_SECONDS = 7.days`.

## Flow

```
owner POST /api/org/:extid/invitations   → status=pending, token issued, email queued
invitee GET /invite/:token               → AcceptInvite.vue resolves state
       │
       ├─ unauthenticated, no account   → inline signup → /accept
       ├─ unauthenticated, account exists → inline signin → /accept
       ├─ authenticated, email matches  → explicit Accept click → /accept
       ├─ authenticated, email mismatch → must logout + reauthenticate
       └─ Decline                       → /decline
```

Acceptance is **always an explicit user click**. Signup/signin establishes auth; the invite is not auto-claimed in the auth hook. See `src/apps/session/views/AcceptInvite.vue` and `src/apps/session/composables/useInviteAuth.ts`.

## API surface

| Method | Path | Auth | Logic class |
|--------|------|------|-------------|
| GET | `/api/invite/:token` | noauth (rate-limited) | `InviteAPI::Logic::Invites::ShowInvite` |
| POST | `/api/invite/:token/accept` | sessionauth | `InviteAPI::Logic::Invites::AcceptInvite` |
| POST | `/api/invite/:token/decline` | noauth | `InviteAPI::Logic::Invites::DeclineInvite` |
| GET | `/api/org/:extid/invitations` | sessionauth (admin) | `OrganizationAPI::Logic::Invitations::ListInvitations` |
| POST | `/api/org/:extid/invitations` | sessionauth (admin) | `OrganizationAPI::Logic::Invitations::CreateInvitation` |
| POST | `/api/org/:extid/invitations/:token/resend` | sessionauth (admin) | `OrganizationAPI::Logic::Invitations::ResendInvitation` |
| DELETE | `/api/org/:extid/invitations/:token` | sessionauth (admin) | `OrganizationAPI::Logic::Invitations::RevokeInvitation` |

`ShowInvite` returns structured responses for *every* invitation state (pending/accepted/declined/expired). Only truly unknown tokens 404. The response carries computed flags `actionable` and `account_exists` so the frontend can branch without a second round-trip.

## Dimensions we track

Reference: industry comparison across 10 SaaS products (Clerk, GitHub, Slack, Notion, Linear, Figma, 1Password, Atlassian, WorkOS, Zitadel). These are the dimensions on which invite systems differ, and where OTS sits.

| Dimension | OTS position | Notes |
|-----------|--------------|-------|
| Invite channel | Email only | No secret link, no Slack app, no SCIM yet |
| Expiry | 7 days, hardcoded | Matches GitHub. Not configurable. |
| Token lifecycle | New token on resend (old invalidated) | `ResendInvitation` calls `generate_token!`, max 3 resends |
| Role at invite | Set at invite (`through_attrs[:role]`) | Majority pattern |
| Account creation | Embedded in flow | Inline `InviteSignUpForm` / `InviteSignInForm` |
| Account-exists branching | Returned in `ShowInvite` response (`account_exists`) | Same pattern as Clerk `__clerk_status`, WorkOS user-exists fork |
| Admin confirmation | Not required (`requires_admin_approval?` hardcoded `false`) | Branch exists in `accept!` for the future approval workflow |
| Email match | Strict, case-insensitive | Enforced in `accept!` and at signup hook (`before_create_account`) — defense in depth |
| Anti-enumeration | `InviteTokenRateLimiter` on GET (per-IP) | Mirrors GitHub verified-email matching, in spirit |
| Acceptance trigger | Explicit user click | No auto-accept post-auth; intentional anti-phishing posture |
| Post-accept onboarding | None | Lands on `/orgs` |

## Frontend state machine

`AcceptInvite.vue` drives the view via a single computed `inviteState`:

```
loading → { signup_required | signin_required | direct_accept | wrong_email |
            already_accepted | invalid }
                                  ↓ (user action resolves)
                            { accepted | declined }
```

`accepted`/`declined` are terminal pins — once set, the state machine ignores further transitions until the redirect timer fires. This prevents the action row from flickering back into view during the redirect delay. The pattern mirrors `useSecretLifecycle` (see [Secret Lifecycle](secret-lifecycle.md)).

## Anti-abuse

- **Rate limiter on `GET /api/invite/:token`** (`Onetime::Security::InviteTokenRateLimiter`) — per-IP, prevents token enumeration on the noauth endpoint.
- **Email match in `accept!`** — even with a valid session and valid token, the authenticated email must match the invite. The check is repeated at signup hook level so partial Redis state never lands.
- **Token consumed on accept/decline** — `token_lookup` index entry is removed; resending generates a fresh token (old one becomes a dead lookup).
- **Resend cap** — 3 resends per invitation.
- **Pending-state indexes cleared atomically** in `accept!` with a rescue that restores them on Redis/validation failure.

## Open decisions

These map to dimensions in the industry comparison that OTS hasn't resolved yet.

- **Approval workflow** — `requires_admin_approval?` is hardcoded `false` pending the approval endpoint. The `accepted` state and `awaiting_approval` staging set are scaffolded for the follow-up that flips the gate.
- **Open invite links** — no Notion-style secret link or 1Password-style sign-up link. Adding one would require admin confirmation (1Password model) to bound blast radius.
- **Domain-aware behavior** — no consumer-vs-corporate domain distinction (WorkOS pattern). Currently treats `user@gmail.com` and `user@acme.com` identically.
- **Custom branding propagation** — `ShowInvite` returns custom-domain branding when the request hits a branded domain. Confirmed working; not yet documented as a guarantee.

## Related

- [Secret Lifecycle](secret-lifecycle.md) — the same Context/Lifecycle separation pattern
- `lib/onetime/models/organization_membership.rb` — model + lifecycle methods
- `apps/api/invite/` — invitee-facing API
- `apps/api/organizations/logic/invitations/` — owner-facing API
- `src/apps/session/views/AcceptInvite.vue` — frontend state machine
