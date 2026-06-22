# AZ8 — Customer.create! has no allowlist (role/verified mass-assignable at the model layer)

- **Severity:** Low — **NEEDS-VALIDATION** (safe today; all signup paths hardcode `role`)
- **Status:** Proposed fix
- **Affects default config?** Yes (account creation), but **not exploitable today**
- **Related:** finding 02 F8; AZ3 (identical defect in `Organization.create!`); colonel role model (§4, F11)
- **Primary files:** `lib/onetime/models/customer.rb:271-313` (`create!`),
  `lib/onetime/models/customer/features/status.rb` (`role`/`verified`/`verified_by` fields),
  callers: `apps/api/account/logic/account/create_account.rb:94,100-104`,
  `apps/web/auth/operations/create_customer.rb`, `sync_session.rb`

## Problem (recap)

`Customer.create!` forwards `**kwargs` to `super` with no field allowlist:

```ruby
# lib/onetime/models/customer.rb:271-313 (abridged)
def create!(email = nil, **kwargs)
  email ||= kwargs[:email] || kwargs['email']
  email = OT::Utils.normalize_email(email)
  raise Familia::Problem, 'email is required' if email.empty?
  raise Familia::RecordExistsError, ... if email_exists?(email)
  ...
  kwargs[:email] = email
  cust = super(**kwargs)        # any declared field settable, including role/verified
  cust.save
  cust
end
```

`role`, `verified`, and `verified_by` are plain writable Customer fields (`customer/features/status.rb`). The
colonel superuser role is *exactly* the Customer `role` field set to `'colonel'` (assessment §4, F11). So
`Customer.create!(email: 'x@y', role: 'colonel', verified: true)` would mint a verified colonel at the Ruby
level.

*Confirm first:* this is **safe today only by caller discipline**. Every production signup path hardcodes the
role and verification rather than forwarding request params:

- `create_account.rb:94` creates with `email:` only; then sets `@customer_role = 'customer'`, `cust.verified`,
  `cust.role` explicitly (`:100-104`).
- `apps/web/auth/operations/create_customer.rb` and `sync_session.rb` likewise hardcode `'customer'`
  (assessment §4).

There is currently **no** endpoint that forwards a raw params hash into `Customer.create!`. The fix prevents
a *future* endpoint from turning this into a privilege-escalation vector — the highest-impact mass-assignment
sink in the app, since `role: 'colonel'` is full site-admin.

## Root cause

Same as AZ3: the model boundary trusts callers instead of enforcing its own invariant. Familia's keyword-arg
initialization sets any declared field (assessment §5, `horreum.rb:446`), and `guard_allowed_fields!` only
blocks *undeclared* fields — it does not protect declared sensitive fields like `role`/`verified`. The single
create chokepoint accepts an unbounded attribute set.

## Prescribed resolution

Allowlist the attributes a `create!` caller may set, and **never** accept `role`, `verified`, or
`verified_by` from create-time kwargs. Account verification and role assignment must happen through explicit,
intentional calls after creation (as the current callers already do), not via the constructor.

### Implementation steps

1. Filter kwargs against an explicit allowlist and reject privilege fields:

   ```ruby
   # lib/onetime/models/customer.rb
   # Fields a caller may set at creation. Privilege/verification fields are
   # intentionally excluded — assign them explicitly after create, never from input.
   CREATE_ALLOWED_ATTRS = %i[email locale].freeze   # extend to other benign profile fields as needed
   CREATE_FORBIDDEN_ATTRS = %i[role verified verified_by].freeze

   def create!(email = nil, **kwargs)
     email ||= kwargs[:email] || kwargs['email']
     email = OT::Utils.normalize_email(email)
     loggable_email = OT::Utils.obscure_email(email)
     raise Familia::Problem, 'email is required' if email.empty?
     raise Familia::RecordExistsError, "Customer exists #{loggable_email}" if email_exists?(email)

     # Hard fail-closed on privilege fields, regardless of allowlist drift.
     sym_keys = kwargs.keys.map(&:to_sym)
     forbidden = sym_keys & CREATE_FORBIDDEN_ATTRS
     raise Familia::Problem, "Disallowed attributes at create: #{forbidden.join(', ')}" unless forbidden.empty?

     permitted = kwargs.transform_keys(&:to_sym).slice(*CREATE_ALLOWED_ATTRS)
     permitted[:email] = email

     Onetime.auth_logger.info 'Creating customer',
       { email: loggable_email, kwargs: permitted.keys, action: 'create' }

     cust = super(**permitted)
     cust.save
     # ... existing success logging ...
     cust
   end
   ```

   The explicit `CREATE_FORBIDDEN_ATTRS` raise is the security-critical line: even if the allowlist later
   gains a field by mistake, `role`/`verified`/`verified_by` can never be set through `create!`.

2. Keep the existing post-create assignment in callers (`create_account.rb:100-104` sets `role`/`verified`
   explicitly) — that path is unaffected because it assigns *after* `create!`, not through it.

3. **Defense-in-depth (recommended):** treat `role` as not-externally-assignable in general. If Familia
   supports a per-field write guard, register `role`/`verified`/`verified_by`; otherwise route all role
   changes through the CLI/`role_command` path (the only legitimate colonel writer today, §4 F11) and
   document the fields as internal-only in the model header.

### Alternatives considered

- **Silently drop forbidden keys:** weaker than raising — a future endpoint that mistakenly forwards
  `params` would pass silently and the bug would hide until an audit. The fail-closed `raise` makes
  misuse a loud test failure.
- **Rely on caller discipline + grep/lint:** rejected for the same reason as AZ3 — `role: 'colonel'` is the
  worst-case escalation in the app; the model must enforce its own invariant once rather than depend on every
  future caller being correct.

## Test / verification

Add to the Customer model spec:
1. **Privilege rejection:** `Customer.create!(email: 'a@b', role: 'colonel')` raises;
   `Customer.create!(email: 'a@b', verified: true)` raises; `verified_by:` raises.
2. **Default role:** a customer created via `create!` has the non-privileged default role (not colonel) and
   is unverified until explicitly set.
3. **Allowed attrs pass:** `email`/`locale` are accepted and persisted.
4. **Caller regression:** `create_account_spec` and the auth-operation specs still pass (they assign
   role/verified after create).

## Effort & risk

- **Effort:** Low — localized to `create!`, plus model specs.
- **Back-compat:** none broken if the allowlist matches what real callers pass (`email`, and verify whether
  any caller passes additional benign fields like `locale` at create — extend the allowlist accordingly).
- **Risk:** Low. No production path forwards privilege fields into `create!` today, so the change is
  transparent to current behavior while closing a high-impact future vector.
