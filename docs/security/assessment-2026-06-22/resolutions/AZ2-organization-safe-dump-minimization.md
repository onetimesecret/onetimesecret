# AZ2 — Organization safe_dump leaks internal IDs, owner custid, and contact/billing PII

- **Severity:** Medium — **CONFIRMED** (but see correction: `owner_id` in the title is already stripped)
- **Status:** Proposed fix — **superseded by re-verification correction (2026-06-24) below**
- **Affects default config?** Yes (any active org member can read the org via `get_organization`)
- **Related:** finding 02 F2; AZ5 (extid derivable once objid leaks); AZ6 (same class for Receipt)
- **Primary files:** `lib/onetime/models/organization/features/safe_dump_fields.rb`,
  `apps/api/organizations/logic/organizations/get_organization.rb`,
  `lib/onetime/models/organization.rb` (opaque-ID doc, `:10-30`)

> **⚠️ Re-verification correction (2026-06-24 blind pass — `RE-VERIFICATION-2026-06-24-independent.md` §3b/§6).**
> **Wrong sink.** The prescription below edits `safe_dump_fields.rb` and a `get_organization.rb#success_data`
> method — but the member-facing serialization actually happens in `serialize_organization` at
> `apps/api/organizations/logic/base.rb:61-80`, and the depicted `success_data` method does not exist.
> Editing `safe_dump_fields.rb` alone will not remove the leak.
>
> **Headline overstates.** `owner_id` (in the doc title) is **already stripped**: `serialize_organization`
> substitutes `owner_extid` (`:72`) then `record.delete(:owner_id)` (`:74`). The residual member-visible leak
> rides `created_by`, `contact_email`, `billing_email` (none stripped) plus the objid alias
> (`record[:id] = record[:objid]`, `:66`).
>
> **Corrected fix — edit `serialize_organization` (`apps/api/organizations/logic/base.rb:61-80`):**
> - delete `:identifier` and `:created_by` from the member baseline;
> - keep the existing `owner_id` deletion (`:74`);
> - **defer `:objid` removal** behind a coordinated migration — `record[:id] = objid` (`:66`) is a hard
>   runtime dependency (frontend zod contract + the `O-Organization-ID` interceptor), so it cannot be dropped
>   unilaterally;
> - **nil-out (do not delete)** `contact_email`/`billing_email` for non-admins — the contract requires the
>   key to be present;
> - author the missing non-raising `entitlement_in?` helper (the body references it; it does not yet exist);
> - gate the `members[]` array — `get_organization.rb:54-60` emits `member.objid` + email, a second leak the
>   body does not address.

## Problem (recap)

`Organization` safe_dump emits internal and cross-tenant-sensitive fields to any caller that can serialize
the org. `get_organization.rb:38` gates only on `api_access`, which every active member (including a plain
`member`) holds — so the dump audience is "every member," not "every admin/owner."

Leaked fields (`lib/onetime/models/organization/features/safe_dump_fields.rb`):

```ruby
base.safe_dump_field :identifier, ->(obj) { obj.identifier }  # :17 == objid
base.safe_dump_field :objid                                   # :18 internal UUIDv7 PK
...
base.safe_dump_field :owner_id                                # :22 owner's Customer custid
base.safe_dump_field :created_by                              # :27 creator's custid
base.safe_dump_field :contact_email                           # :28 tenant PII
base.safe_dump_field :billing_email                           # :29 tenant PII
```

- `objid`/`identifier` (`:17-18`) defeat the documented Opaque Identifier Pattern (`organization.rb:10-30`),
  whose entire purpose is to keep the internal UUID out of URLs/APIs. Combined with **AZ5** (plain-SHA-256
  extid derivation), a member who learns the `objid` can recompute the `extid`.
- `owner_id`/`created_by` (`:22,:27`) expose the owner/creator's internal customer custid to any member.
- `contact_email`/`billing_email` (`:28-29`) are tenant-internal PII exposed to every member, not just
  billing/org admins.

CONFIRMED-good: `stripe_customer_id`, `stripe_subscription_id`, `email_hash`, and `subscription_status` are
*not* in this list (compare `lib/onetime/models/organization/features/with_organization_billing.rb`), so the
hard billing identifiers are already withheld.

## Root cause

A single `safe_dump` field map serves all audiences. Familia's `safe_dump` is an allowlist, but the
allowlist was authored for the owner/admin console view and reused unchanged for the member-facing
`get_organization` read. There is no role/entitlement-aware projection: the same field set ships to a plain
member, an admin, and an owner.

## Prescribed resolution

Stop emitting internal IDs from `safe_dump` entirely, and gate contact/billing PII behind the entitlement
that already governs org/billing management. Two layers:

### Implementation steps

1. **Remove internal IDs from the dump unconditionally** (no audience needs the UUID; the public `extid` is
   already present at `:19`):

   ```ruby
   # safe_dump_fields.rb — delete these two lines
   base.safe_dump_field :identifier, ->(obj) { obj.identifier }   # :17
   base.safe_dump_field :objid                                    # :18
   ```

   `extid` (`:19`) remains the public reference; `find_by_extid` already resolves it. This also re-closes the
   AZ5 derivation chain (no objid in the response means nothing to feed the SHA-256/HMAC).

2. **Demote owner custid to the public extid** (or drop it). Frontends that show "owned by" should reference
   the owner by `extid`, never the internal custid:

   ```ruby
   # Replace raw custid fields with a resolved, public-safe owner reference, or remove entirely.
   base.safe_dump_field :owner_extid, ->(org) {
     Onetime::Customer.load(org.owner_id)&.extid   # public ID, not custid
   }
   # Drop :owner_id and :created_by from the member-facing dump.
   ```

   If a numeric/string owner custid is genuinely needed by an admin console, expose it only in the
   role-aware projection below — not in the default dump.

3. **Gate contact/billing emails by entitlement at the serialization boundary.** Add a role-aware serializer
   the logic class calls, instead of one flat `safe_dump`:

   ```ruby
   # apps/api/organizations/logic/organizations/get_organization.rb
   def success_data
     dump = @organization.safe_dump   # now ID-free, PII-free (member-safe baseline)
     if entitlement_in?(@organization, 'manage_org') || entitlement_in?(@organization, 'manage_billing')
       dump[:contact_email] = @organization.contact_email
       dump[:billing_email] = @organization.billing_email
     end
     { record: dump }
   end
   ```

   Add a non-raising `entitlement_in?(org, ent)` helper next to `require_entitlement_in!`
   (`lib/onetime/logic/base.rb:271`) that returns a boolean instead of raising (it can wrap the same
   `membership.can?` check). Remove `:contact_email`/`:billing_email` from the base `safe_dump` list so the
   member-facing default never carries them.

4. **Review `entitlements`/`limits` (`:41-51`).** These expose the org-level capability set, which is broader
   than the caller's own `can?` set. Confirm the frontend gates features on the *membership* entitlements
   (returned with the membership), not the org entitlements; if it does not, scope these to admin/owner too.
   *Confirm first:* whether removing them breaks the member dashboard's feature-gating before changing.

### Alternatives considered

- **Keep objid but rely on AZ5's HMAC:** rejected. Even with a keyed extid, the internal UUID has no place
  in an API response — it violates the codebase's own opaque-ID doctrine and aids correlation across logs.
- **One flat dump, drop PII for everyone:** simpler, but owners/billing admins legitimately need to see the
  org's contact/billing email in the console. The role-aware projection serves both audiences correctly.

## Test / verification

Add to `apps/api/organizations/spec/logic/organizations/get_organization_spec.rb`:
1. **Member dump:** plain member calls `get_organization` → response has `extid`, has **no** `objid`,
   `identifier`, `owner_id`, `created_by`, `contact_email`, or `billing_email`.
2. **Owner/billing dump:** owner (or `manage_billing` holder) → response includes `contact_email`/
   `billing_email`, still **no** `objid`/`identifier`.
3. **AZ5 linkage regression:** assert no `objid`/`identifier`/UUID-shaped value appears anywhere in the
   serialized org for any role.
4. **Migration/consumer check:** snapshot the member-facing JSON keys and diff against any frontend type
   definitions to catch consumers that read the removed fields.

## Effort & risk

- **Effort:** Low–Medium — field-list edits plus a small role-aware serializer and the `entitlement_in?`
  helper.
- **Back-compat / migration:** removing `objid`/`identifier`/`owner_id`/`created_by` is an API response
  change. Grep frontend + SDK consumers for these keys first; the assessment notes `owner_id`/`created_by`
  are kept "for backward-compatible JSON consumers during the deprecation window"
  (`safe_dump_fields.rb:23-26`), so coordinate the removal with that window (or expose `owner_extid` as the
  replacement before deleting `owner_id`).
- **Risk:** Low for the security goal; medium for consumer breakage — covered by the JSON-key snapshot test.
