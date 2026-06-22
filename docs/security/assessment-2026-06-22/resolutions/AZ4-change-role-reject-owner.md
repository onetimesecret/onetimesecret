# AZ4 — change_role! accepts `owner` at the model layer (escalation guard lives only in one validator)

- **Severity:** Medium — **NEEDS-VALIDATION** (no current endpoint reaches it with `owner`)
- **Status:** Proposed fix
- **Affects default config?** Yes (role management is a default org feature)
- **Related:** finding 02 F4; AZ1 (RemoveMember entitlement gate); `update_member_role.rb` validator
- **Primary files:** `lib/onetime/models/organization_membership.rb` (`change_role!`, `:258-274`;
  `ROLE_ENTITLEMENTS`, `:102-106`),
  `apps/api/organizations/logic/members/update_member_role.rb` (`validate_role_change!`, `:129-167`)

## Problem (recap)

`OrganizationMembership#change_role!` validates only that the new role is a known role-entitlement key:

```ruby
# organization_membership.rb:258-262
def change_role!(new_role)
  new_role = new_role.to_s
  unless ROLE_ENTITLEMENTS.key?(new_role)
    raise Onetime::Problem, "Invalid role: ... Must be one of: #{ROLE_ENTITLEMENTS.keys.join(', ')}"
  end
  ...
```

`ROLE_ENTITLEMENTS` (`:102-106`) has keys `'owner'`, `'admin'`, `'member'`. So the model **rejects
`'colonel'`** (not a key) but **accepts `'owner'`**. The only thing preventing a promotion to `owner`
through the role-change flow is the endpoint validator:

```ruby
# update_member_role.rb:29  VALID_ROLES = %w[member admin]
# update_member_role.rb:159-167
return unless @new_role == 'owner'
raise_form_error(error_key: 'api.organizations.members.errors.cannot_promote_to_owner', ...)
```

The escalation guard ("you cannot make someone an owner via this endpoint") lives in exactly **one place**.
Any future caller of `change_role!('owner')` — a bulk-migration script, a colonel tool, an SSO
auto-provisioning path, a refactor that adds a second role endpoint — would silently mint a second owner
with no last-owner accounting and no ownership-transfer semantics.

*Confirm first:* there is currently no production caller that passes `'owner'` to `change_role!` other than
through `update_member_role`, which blocks it. There is also **no `transfer_ownership!`** method in the
codebase today (grep confirms zero references), so ownership change has no first-class, guarded path.

## Root cause

`change_role!` treats "owner" as just another assignable role, but owner is special: it carries
`OWNER_ENTITLEMENTS` (`manage_billing`, `manage_org`, `manage_sso`, etc., `:90-100`) and there must always be
exactly one accountable owner. Promotion to owner and demotion of the last owner are *ownership-transfer*
operations, not ordinary role edits — yet the model exposes them through the generic path and relies on a UI
validator to forbid them.

## Prescribed resolution

Make `change_role!` reject `owner` (and any future privileged role) at the model layer, and route ownership
changes through a dedicated, guarded `transfer_ownership!`. The model becomes the authoritative guard so the
protection no longer depends on a single endpoint validator.

### Implementation steps

1. Add an explicit assignable-role allowlist and reject `owner` in `change_role!`:

   ```ruby
   # lib/onetime/models/organization_membership.rb
   # Roles assignable via the ordinary role-change path. 'owner' is excluded:
   # ownership is a single accountable seat and changes only via transfer_ownership!.
   ASSIGNABLE_ROLES = %w[member admin].freeze

   def change_role!(new_role)
     new_role = new_role.to_s
     unless ASSIGNABLE_ROLES.include?(new_role)
       raise Onetime::Problem,
         "Role '#{new_role}' cannot be set via change_role!. " \
         "Assignable roles: #{ASSIGNABLE_ROLES.join(', ')}. " \
         "Use transfer_ownership! to change ownership."
     end
     return true if role == new_role
     self.role = new_role
     raise Onetime::Problem, "Materialization failed for role change to #{new_role}" unless materialize_for_role!
     true
   end
   ```

   This rejects both `'owner'` and `'colonel'` (and anything else), so the model is fail-closed regardless of
   what `ROLE_ENTITLEMENTS` happens to contain. `ROLE_ENTITLEMENTS` still legitimately includes `owner` for
   the *entitlement-materialization* lookup (`compute_entitlements_from_role`); only *assignment* is
   restricted.

2. Add a first-class, guarded ownership transfer (currently missing entirely):

   ```ruby
   # Promote `target` to owner and demote the current owner to admin, atomically,
   # enforcing the "exactly one owner" invariant. Last-owner protection lives here.
   def self.transfer_ownership!(organization, current_owner_membership, target_membership)
     raise Onetime::Problem, 'Current owner mismatch' unless current_owner_membership.owner?
     raise Onetime::Problem, 'Target must be an active member' unless target_membership.active?
     # ... within an atomic_write / lock on the org:
     #   target_membership.role = 'owner'; target_membership.materialize_for_role!
     #   current_owner_membership.role = 'admin'; current_owner_membership.materialize_for_role!
     # Re-check post-condition: org has exactly one active owner membership.
   end
   ```

   Mirror the atomicity discipline used elsewhere (`Familia::Lock` / `atomic_write`, as in C1) so a
   concurrent transfer cannot leave zero or two owners. The dedicated method is where the **last-owner /
   single-owner** invariant is enforced, instead of being scattered across validators.

3. Keep `update_member_role.rb`'s `VALID_ROLES`/`cannot_promote_to_owner` guard as a second layer (it now
   produces a friendly form error before the model would raise a generic one). Defense-in-depth: endpoint
   validator + model guard.

### Alternatives considered

- **Reject only `'owner'`, keep `ROLE_ENTITLEMENTS.key?` for the rest:** weaker — still relies on
  `ROLE_ENTITLEMENTS` never gaining a future privileged key. An explicit positive allowlist
  (`ASSIGNABLE_ROLES`) is strictly fail-closed.
- **Allow owner promotion in `change_role!` but add a last-owner check there:** rejected — conflates two
  semantics (demotion vs. transfer) and still lacks the demote-the-old-owner half of a transfer. A dedicated
  `transfer_ownership!` is the principled long-term shape.

## Test / verification

Add to `lib/onetime/models/spec` (or the membership spec) and `update_member_role_spec.rb`:
1. **Model guard:** `membership.change_role!('owner')` raises; `change_role!('colonel')` raises;
   `change_role!('admin')`/`'member'` succeed and re-materialize.
2. **Endpoint still blocks owner:** PATCH role=`owner` → existing `cannot_promote_to_owner` form error
   (unchanged).
3. **Transfer invariant:** `transfer_ownership!` promotes target, demotes old owner, and leaves exactly one
   active owner; concurrent transfers do not produce zero/two owners (drive with the lock/atomic harness).
4. **Last-owner protection:** attempting to demote the only owner via any path is rejected.

## Effort & risk

- **Effort:** Medium — small `change_role!` change is trivial; the new `transfer_ownership!` with atomicity
  and last-owner accounting is the bulk of the work. If ownership transfer is out of scope for this pass,
  ship step 1 (reject `owner`) alone — it closes the escalation surface — and track `transfer_ownership!`
  separately.
- **Back-compat:** any internal script that relied on `change_role!('owner')` must move to
  `transfer_ownership!`. Grep confirms none exist today.
- **Risk:** Low for step 1 (no current caller passes `owner`); Medium for the transfer method since it
  touches the single-owner invariant — cover with the concurrency test.
