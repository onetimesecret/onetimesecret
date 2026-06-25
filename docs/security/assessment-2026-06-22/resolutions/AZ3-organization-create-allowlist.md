# AZ3 — Organization.create! open `**` splat enables mass assignment

- **Severity:** Medium — **NEEDS-VALIDATION** (latent; multiple callers pass `is_default:` via the splat)
- **Status:** Proposed fix — **corrected 2026-06-24** (allowlist now includes `is_default`; `planid`
  citation fixed; see `RE-VERIFICATION-2026-06-24-independent.md` §4/§6)
- **Affects default config?** Yes (organizations are created on every signup), but **not exploitable today**
- **Related:** finding 02 F3; AZ8 (same class of defect in `Customer.create!`); AZ4 (model-layer hardening)
- **Primary files:** `lib/onetime/models/organization.rb` (`create!`, `:421-437`; sensitive fields `:65-72`
  and `with_organization_billing.rb`),
  `apps/api/organizations/logic/organizations/create_organization.rb` (primary caller; other splat callers
  pass `is_default:` — see Problem)

## Problem (recap)

`Organization.create!` forwards an open keyword splat straight into `new`:

```ruby
# lib/onetime/models/organization.rb:421-437
def create!(display_name, owner_customer, contact_email = nil, **)
  ...
  org = new(
    display_name: display_name,
    owner_id: owner_customer.custid,      # fixed from trusted positional arg — safe
    created_by: owner_customer.custid,    # fixed — safe
    contact_email: contact_email,
    **,                                   # OPEN SPLAT — any declared field becomes settable
  )
```

`owner_id`/`created_by` are pinned from the trusted `owner_customer` positional arg, so those are safe. The
risk is the bare `**`: Familia's `initialize_with_keyword_args` sets **any declared field** from kwargs with
no field-level allowlist (assessment §5, `familia/.../horreum.rb:446`). The Organization declares sensitive
plain fields — `archived_at`/`archived_comment` (`:71-72`), plus the billing fields from
`with_organization_billing` — `planid` (`with_organization_billing.rb:34`, billing tier; **not**
`organization.rb:87`, which is only the init default), `stripe_customer_id`, `stripe_subscription_id`,
`subscription_status`, `complimentary`. If **any** caller ever forwards request params into that splat, an
attacker could set their own plan tier, mark an org `complimentary`, or inject a Stripe id.
(`is_default` is also splat-settable but is a benign workspace flag legitimate callers set at create time —
see the allowlist below.)

*Confirm first:* no production caller forwards a **raw request-params hash** into the splat, so this is a
latent over-posting surface, not a live vulnerability. (Re-verification found multiple callers — 3 production
+ 6 spec — that do pass `is_default: true` via the splat, e.g. `lazy_organization_creation_spec.rb`; those
pass fixed literals, not request params, and are the reason `is_default` is allowlisted below.) Validate
there is no `Organization.create!(...**params)` sink forwarding untrusted input before sizing the work as
exploitable.

## Root cause

The model boundary trusts its callers instead of enforcing its own invariant. `create!` is the single
chokepoint for org creation, yet it accepts an unbounded attribute set. Familia's `guard_allowed_fields!`
only blocks *undeclared* fields (assessment §5, `persistence.rb:761`); it does **not** protect declared
sensitive fields like `planid`/`complimentary`. The only thing standing between a request and a
plan/billing override is caller discipline.

## Prescribed resolution

Replace the open `**` with an explicit allowlist of attributes a creator may set, and reject (or ignore)
everything else at the model boundary. Plan, billing, and lifecycle fields must be set by trusted internal
code paths (billing webhook, standalone materialization), never by create-time kwargs.

### Implementation steps

1. Define the creator-settable allowlist and filter the splat inside `create!`:

   ```ruby
   # lib/onetime/models/organization.rb
   # Attributes a caller may set at creation. is_default is a benign workspace flag
   # (delete-protection / same-customer domain-SSO) that legitimate splat callers set
   # at create time, so it is allowlisted. Everything else (planid, Stripe ids,
   # complimentary, subscription_status, archived_*) is owned by trusted internal
   # flows, NOT create-time input.
   CREATE_ALLOWED_ATTRS = %i[display_name description is_default].freeze

   def create!(display_name, owner_customer, contact_email = nil, **extra)
     raise Onetime::Problem, 'Owner required' if owner_customer.nil?

     display_name = display_name.to_s.strip
     raise Onetime::Problem, 'Display name required' if display_name.empty?

     contact_email = contact_email.to_s.strip
     contact_email = nil if contact_email.empty?

     # Fail-closed: reject any attribute not on the allowlist rather than
     # silently dropping it, so a forwarded params hash surfaces loudly in tests.
     rejected = extra.keys.map(&:to_sym) - CREATE_ALLOWED_ATTRS
     unless rejected.empty?
       raise Onetime::Problem, "Disallowed organization attributes: #{rejected.join(', ')}"
     end
     permitted = extra.slice(*CREATE_ALLOWED_ATTRS)

     org = new(
       display_name: display_name,
       owner_id: owner_customer.custid,
       created_by: owner_customer.custid,
       contact_email: contact_email,
       **permitted,
     )
     # ... unchanged ...
   end
   ```

   Note `planid` is intentionally excluded: `init` defaults it to `'free_v1'` (`:86-89`) and
   `materialize_standalone_entitlements!` / the billing webhook assign the real plan. Creation input must not
   set it.

2. Confirm the callers still work: `create_organization.rb` and the other splat callers that pass
   `display_name`/`description`/`is_default: true` now land on the allowlisted path unchanged. Because the
   filter is fail-closed, any caller passing `is_default` would have raised had it been left off the
   allowlist — hence its inclusion.

3. **Defense-in-depth at the field level (optional but recommended):** mark `planid`, the
   Stripe fields, `complimentary`, and `subscription_status` as not-externally-assignable so even a future
   bulk setter cannot reach them. If Familia supports a per-field guard, register these; otherwise document
   them in the model header as "internal-only — set via billing/materialization paths only," mirroring the
   existing `created_by` "immutable audit field" convention (`:68`).

### Alternatives considered

- **Silently drop unknown keys (`slice` only, no raise):** safer than the splat, but a forwarded params hash
  would pass silently. The fail-closed `raise` turns any future mis-wiring into a loud test failure, which is
  the long-term-safe choice for a security boundary.
- **Rely on caller discipline + a lint/grep gate:** rejected. The assessment already documents the latent
  risk; the model is the right place to enforce its own invariant once, rather than re-auditing every future
  caller.

## Test / verification

Add to the Organization model spec:
1. **Mass-assignment rejection:** `Organization.create!('Acme', owner, planid: 'enterprise_v1')` raises (or,
   if you chose drop-silently, the created org has `planid == 'free_v1'`).
2. **Billing fields blocked:** `complimentary: true`, `stripe_customer_id: 'cus_x'`,
   `subscription_status: 'active'` are all rejected/ignored.
3. **Allowed attrs pass:** `description:` and `is_default: true` are accepted and persisted.
4. **Caller regression:** existing `create_organization_spec.rb` continues to pass unchanged (no behavior
   change for the legitimate path).

## Effort & risk

- **Effort:** Low — localized to `create!`, plus a model spec.
- **Back-compat:** none broken if the allowlist matches what the real caller sends (`display_name`,
  `description`). Verify no test or seed passes `planid`/billing fields positionally before merging.
- **Risk:** Low. Behavior is unchanged for the production path; the change only constrains a currently-unused
  attack surface.
