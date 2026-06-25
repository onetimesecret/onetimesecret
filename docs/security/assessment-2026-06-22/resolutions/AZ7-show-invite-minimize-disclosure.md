# AZ7 — show_invite discloses inviter email and an account-exists oracle

- **Severity:** Low — **CONFIRMED**
- **Status:** Proposed fix — **superseded by re-verification correction (2026-06-24) below** (product decision still required on inviter-email exposure)
- **Affects default config?** Yes (the noauth `GET /api/invite/:token` endpoint)
- **Related:** finding 02 F7; F10 (invite token rate limiter)
- **Primary files:** `apps/api/invite/logic/base.rb:51-64` (`serialize_invitation_public`),
  `apps/api/invite/logic/invites/show_invite.rb:65-99` (`success_data`, `account_exists?`)

> **⚠️ Re-verification correction (2026-06-24 blind pass — `RE-VERIFICATION-2026-06-24-independent.md` §5).**
> Escalated to **incomplete_regresses**: the prescribed **backend-only** minimization breaks invite acceptance
> in the frontend. `AcceptInvite.vue:134` runs `showInviteResponseSchema.parse(response.data.record)`, and that
> schema requires both fields non-optionally — `invited_by_email: z.string().nullable()`
> (`src/schemas/api/invite/responses/show-invite.ts:80`) and `account_exists: z.boolean()` (`:83`). Dropping
> either from the backend response throws a zod parse error before the screen renders. `account_exists` also
> drives the signin-vs-signup branch at `AcceptInvite.vue:97`, and `invited_by_email` is rendered in the
> template (`AcceptInvite.vue:430-431`, +492/577/653).
> **Correction:** ship the frontend change in lockstep with the backend minimization — relax the zod schema
> (`show-invite.ts:80,83`) to make the fields optional/removed, rederive the signin/signup branch (`:97`) from
> client auth state, and drop the inviter-email template bindings. Do **not** land the backend edit alone.
> Severity unchanged (Low).

## Problem (recap)

`GET /api/invite/:token` is `noauth` (the token is the credential) and returns, to any token holder, more
than the recipient needs to decide whether to accept:

```ruby
# apps/api/invite/logic/base.rb:55-63
{
  organization_name: organization&.display_name,
  organization_id: organization&.extid,
  email: invitation.invited_email,
  role: invitation.role,
  invited_by_email: inviter&.safe_dump&.dig(:email),   # :60 — inviter's email address
  expires_at: invitation.invitation_expires_at,
  status: effective_invitation_status(invitation),
}
```

```ruby
# apps/api/invite/logic/invites/show_invite.rb:70-71, 97-99
result[:record][:account_exists] = account_exists?
...
def account_exists?
  Onetime::Customer.email_exists?(@invitation.invited_email)   # account-existence oracle
end
```

Two marginal leaks:
- **Inviter email** (`base.rb:60`): the token holder learns a specific employee's email address. Useful for
  targeted phishing if a token leaks (forwarded mail, shared link, log).
- **Account-existence oracle** (`show_invite.rb:97-99`): the response reveals whether a OneTimeSecret account
  already exists for the invited email. Although keyed to the *invited* email (which the holder already
  knows), it confirms account existence on this platform for that address.

Severity is Low: the token is a 256-bit single-use value and the endpoint is rate-limited
(`InviteTokenRateLimiter`, F10). The recipient is the intended audience for most of the payload. The fix is
about *minimizing disclosure to whatever holds the token*, in case the token is not solely in the intended
recipient's hands.

## Root cause

The serializer was built to power a rich pre-acceptance UI ("You've been invited by Alice to Acme; you
already have an account, sign in to accept") and exposes the data needed for that UX directly on the
unauthenticated endpoint. The convenience fields (`invited_by_email`, `account_exists`) are not required to
*render the accept decision* and are disclosed before the holder has proven they are the recipient.

## Prescribed resolution

Minimize the pre-acceptance payload to what is needed to render the accept/decline screen, and replace the
raw oracle/email with non-identifying signals. Drive the "sign in vs. create account" branch off auth state
the client already has, not off a server-side existence probe.

### Implementation steps

1. **Drop the inviter's email; use the inviter's display name (or org-level attribution) instead.** If the UI
   needs to show who invited the user, show a name, not a contactable address:

   ```ruby
   # apps/api/invite/logic/base.rb — serialize_invitation_public
   {
     organization_name: organization&.display_name,
     organization_id:   organization&.extid,
     email:             invitation.invited_email,   # the recipient already knows their own email
     role:              invitation.role,
     invited_by_name:   inviter&.safe_dump&.dig(:display_name),  # name, not email; or omit entirely
     expires_at:        invitation.invitation_expires_at,
     status:            effective_invitation_status(invitation),
   }
   ```

   *Confirm first (product decision):* whether to show inviter attribution at all pre-acceptance. The
   safest option is to omit inviter identity until the invite is accepted (post-auth). If attribution is
   desired for trust, a display name is the minimal disclosure.

2. **Remove the account-existence oracle from the response.** The frontend can decide between "sign in" and
   "create account" from the *user's own* session/auth state and the available `auth_methods`
   (`show_invite.rb:101-105`), not from a server probe of the invited email:

   ```ruby
   # apps/api/invite/logic/invites/show_invite.rb — success_data
   result[:record][:actionable] = actionable?
   # remove: result[:record][:account_exists] = account_exists?
   ```

   Delete the `account_exists?` helper (`:97-99`). If a "you may already have an account" hint is genuinely
   required, defer it to *after* the user submits their email through the authenticated accept/signup flow,
   where existence is revealed only to the address owner — not to any token holder.

3. Keep the existing rate limiter (`show_invite.rb:36-40`) and the 256-bit token; AZ7 reduces what a leaked
   token discloses, it does not replace the token's protection.

### Alternatives considered

- **Leave inviter email, justify by "recipient is the audience":** acceptable today given the strong token,
  but tokens leak (forwarded emails, chat, proxy logs). Minimizing the payload is the long-term-safe default
  and costs little.
- **Keep `account_exists` but only when the request is authenticated as the invited email:** more complex and
  the endpoint is `noauth` by design (pre-account). Removing the oracle and branching on client auth state is
  simpler and leaks nothing.

## Test / verification

Add to `apps/api/invite/spec/logic/invites/`:
1. **No inviter email:** `show_invite` response has no `invited_by_email` key (and, if attribution kept, only
   `invited_by_name`).
2. **No oracle:** response has no `account_exists` key.
3. **UI signals intact:** `actionable`, `auth_methods`, `branding` still present and correct so the frontend
   can render the screen and the accept/decline flow still works end-to-end.
4. **Accept flow unchanged:** existing accept/signup-and-accept specs still pass (email binding enforced
   downstream, assessment §6 A2).

## Effort & risk

- **Effort:** Low — serializer edits and removing one helper, plus the product decision on attribution.
- **Back-compat:** the pre-acceptance UI must stop reading `invited_by_email`/`account_exists`. Coordinate the
  frontend change; the accept flow itself is unaffected.
- **Risk:** Low. No change to token validation, single-use, expiry, or email binding.
