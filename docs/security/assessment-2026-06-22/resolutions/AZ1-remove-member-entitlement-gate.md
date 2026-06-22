# AZ1 — RemoveMember authorization inconsistency (entitlement-gate the only un-gated member op)

- **Severity:** Medium — **CONFIRMED** (defense-in-depth / consistency, not directly exploitable today)
- **Status:** Proposed fix
- **Affects default config?** Yes (organization member management is a default feature)
- **Related:** finding 02 F1; siblings `create_invitation.rb`, `revoke_invitation.rb`, `resend_invitation.rb`,
  `list_invitations.rb`, `update_member_role.rb`, `delete_organization.rb`; AZ4 (owner-guard at model layer)
- **Primary files:** `apps/api/organizations/logic/members/remove_member.rb`,
  `lib/onetime/logic/base.rb` (`require_entitlement_in!`),
  `lib/onetime/models/organization_membership.rb` (`ROLE_ENTITLEMENTS`)

## Problem (recap)

`RemoveMember` is the **only** member-management endpoint that does not call `require_entitlement_in!`.
Every sibling routes its authority through the entitlement model:

- `manage_members`: `create_invitation.rb:42`, `resend_invitation.rb:28`, `list_invitations.rb:24`,
  `revoke_invitation.rb:25`
- `manage_org`: `update_member_role.rb:45`, `delete_organization.rb:38`
- `api_access`: `list_members.rb:35`, `get_organization.rb:38`

`RemoveMember` instead authorizes with raw **role-string** comparisons in `validate_removal!`
(`remove_member.rb:135-181`):

```ruby
# remove_member.rb:159-181
actor_role  = @actor_membership.role
target_role = @target_membership.role
case actor_role
when 'owner' then true
when 'admin' then raise ... if target_role == 'admin'
else raise ...   # members denied
end
```

A plain `member` falls to the `else` branch and is denied, so there is no direct privilege-escalation
today. The defect is architectural: authority lives in role strings rather than entitlements, contradicting
the model's own contract — "authority lives in the materialized entitlements, not role string checks"
(`organization_membership.rb:63-65`).

## Root cause

Two parallel authorization mechanisms coexist. The canonical one (`require_entitlement_in!`,
`lib/onetime/logic/base.rb:271-318`) is fail-closed: it rejects anonymous callers, requires an **active**
membership, and consults `membership.can?(entitlement)` — which honors per-membership grants/revokes and the
org plan ceiling. The role-string path in `RemoveMember` bypasses all of that:

- A per-membership **revoke** of `manage_members` (operator action) would be ignored — a demoted admin could
  still remove members as long as the `role` field still read `admin`.
- A stale or out-of-band `role` string is trusted directly, with no entitlement reconciliation.
- The colonel bypass is re-implemented locally (`remove_member.rb:94-98,152-153`) instead of reusing the
  vetted `has_system_role?('colonel')` path inside `require_entitlement_in!`.

## Prescribed resolution

Add the same entitlement gate the sibling member-management endpoints use, then keep the role-hierarchy
rules only as a secondary, post-entitlement business-rule check (owner-protection, self-removal, admin
cannot remove admin). Entitlement is the *authority*; the role rules are *who-may-remove-whom* policy.

### Implementation steps

1. In `remove_member.rb#raise_concerns`, after loading the organization and **before** the role-string
   validation, add:

   ```ruby
   # apps/api/organizations/logic/members/remove_member.rb (raise_concerns)
   @organization = load_organization(@extid)

   # Canonical, fail-closed authority — matches every other member-mgmt endpoint.
   require_entitlement_in!(@organization, 'manage_members')

   @actor_membership = load_actor_membership(@organization)
   # ... domain-scope check, target load, validate_removal! ...
   ```

   `require_entitlement_in!` already (a) rejects anonymous users, (b) requires an active membership,
   (c) bypasses for colonels via `has_system_role?('colonel')`, and (d) checks
   `membership.can?('manage_members')`. `manage_members` is in `ADMIN_ENTITLEMENTS`
   (`organization_membership.rb:80-88`), so it is held by `admin` and `owner` roles and honors operator
   revokes.

2. Keep `validate_removal!` for the *target-protection* rules that entitlements do not express:
   - cannot remove the owner (`remove_member.rb:137-142`),
   - cannot remove yourself (`:145-150`),
   - admin cannot remove another admin (`:166-173`).

   These remain valid business rules layered on top of the entitlement check.

3. Simplify the now-redundant colonel handling: with `require_entitlement_in!` running first, a colonel
   already passes the gate even with no membership. `load_actor_membership` can still return `nil` for a
   colonel (`:93-98`); guard the role-string branch so a nil actor membership for a colonel does not raise
   (the existing `return if cust.role?(:colonel)` at `:153` already covers this — verify it stays before any
   `@actor_membership.role` dereference).

### Alternatives considered

- **Leave role-string checks, add no entitlement gate:** rejected — perpetuates two authorization models and
  silently ignores per-membership revokes; the assessment explicitly flags this divergence.
- **Replace role-string rules entirely with entitlements:** the *who-can-remove-whom* hierarchy (admin
  cannot remove admin; owner is unremovable) is finer-grained than the `manage_members` boolean, so the
  role rules must stay as a second layer. Use entitlement for the gate, role rules for the policy.

## Test / verification

Add to `apps/api/organizations/spec/logic/members/`:
1. **Entitlement-revoke regression:** an `admin` whose membership has `manage_members` revoked
   (operator override) attempts removal → now `Forbidden` (was previously allowed by role string). This is
   the behavior change that proves the fix.
2. **Member denied:** plain `member` → `Forbidden` (unchanged).
3. **Happy paths:** owner removes admin/member; admin removes member — all succeed.
4. **Target protection unchanged:** removing the owner, removing self, admin removing admin → still raise the
   existing errors.
5. **Colonel bypass:** colonel with no membership removes a member → succeeds and emits the existing audit
   line (`remove_member.rb:70-72`).

## Effort & risk

- **Effort:** Low — one added line plus a small re-ordering and one regression spec.
- **Risk:** Low. The only behavior change is correctly denying actors whose `manage_members` entitlement was
  revoked out-of-band; all role-based happy paths are preserved by the retained `validate_removal!`.
- **Priority:** highest of the AZ set — it closes a model/role divergence cheaply and aligns the endpoint
  with the rest of the codebase.
