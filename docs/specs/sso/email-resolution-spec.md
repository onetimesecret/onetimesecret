# Implementation Spec: SSO Email Resolution (#3478)

This document captures design decisions, security constraints, code structure, and test requirements for resolving GitHub issue #3478. Use it during implementation to keep the work aligned with the reviewed design.

---

## 1. Architecture context

### Callback flow (rodauth-omniauth 0.6.2)

The gem's `_handle_omniauth_callback` runs this sequence:

```
1. before_omniauth_callback_route          ← logging only
2. retrieve_omniauth_identity(provider, uid)
   ├─ found  → account_from_omniauth_identity(account_id)
   └─ nil    → account_from_omniauth()     ← THE LINKER (by email)
3. verify/status checks
4. transaction:
   ├─ no account → omniauth_create_account()
   │   ├─ omniauth_new_account()           ← builds { login_column => login }
   │   ├─ before_omniauth_create_account   ← validation hook
   │   ├─ omniauth_save_account            ← INSERT
   │   └─ after_omniauth_create_account    ← Customer/org setup
   └─ create_omniauth_identity / update_omniauth_identity
5. login("omniauth")
```

**Key point:** `account_from_omniauth` (step 2) runs BEFORE account creation. If it fails to find an existing account that should match, the flow creates a duplicate and hits the unique index on `accounts.email`. Both the lookup and creation paths must use the same resolved email.

### OTS hook file

All overrides live in `apps/web/auth/config/hooks/omniauth.rb`. The module method `Auth::Config::Hooks::OmniAuth.configure(auth)` receives the rodauth auth instance and sets DSL blocks.

### Current database constraints

```sql
-- accounts table (migration 001)
citext :email, null: false
constraint :valid_email, email: /^[^,;@ \r\n]+@[^,@; \r\n]+\.[^,@; \r\n]+$/
index :email, unique: true, where: { status_id: [1, 2] }  -- partial on PG

-- account_identities table (migration 006) — already email-agnostic
(provider, uid) unique index
```

Phase 1 does not change the schema. Phase 2 will.

---

## 2. Security constraints: claim trust levels

This is the single most important design decision. Violations here create account-takeover vectors.

### Why this matters

rodauth-omniauth uses the email column for two things:
1. **Account linking** — `_account_from_omniauth` calls `_account_from_login(omniauth_email)`. If the resolved email matches an existing account, the SSO identity is linked to it.
2. **Auto-verification** — `omniauth_verify_account?` returns true when `account[login_column] == omniauth_email`. A match skips the verification flow entirely.

Writing an unverified claim into the email column means: if attacker controls a mutable claim (e.g., `preferred_username`) that matches victim's email, attacker's SSO identity links to victim's account and bypasses verification.

### Tier 1 — Verified mailbox (safe for `accounts.email`)

| Claim | Source | Why safe |
|-------|--------|----------|
| `info.email` | Standard OIDC `email` claim, mapped by the OmniAuth strategy | Verified by the IdP; most strategies only populate this from verified email claims |
| `extra.raw_info["mail"]` | Exchange mailbox attribute | Represents an actual deliverable mailbox; not user-editable |

### Tier 2 — Mutable identifier (NOT safe for `accounts.email`)

| Claim | Source | Why unsafe |
|-------|--------|------------|
| `extra.raw_info["upn"]` | User Principal Name (v1.0 token) | Mutable by tenant admin; may not represent a mailbox; B2B guest UPNs are email-shaped but undeliverable |
| `extra.raw_info["preferred_username"]` | v2.0 token claim | Microsoft explicitly warns: "Do not use this value to make authorization decisions." Mutable, reassignable. |

**Rule: Only Tier 1 claims may populate `accounts.email`. No exceptions in Phase 1.**

---

## 3. Step 0: Diagnostic triage

Before writing code, capture the actual auth hash from the failing EntraID login. Log or inspect `omniauth_extra` in the `before_omniauth_callback_route` hook.

Check:
- Is `extra.raw_info["mail"]` present? If yes, this may be solvable by enabling the `email` optional claim on the app registration (Azure Portal → App registrations → Token configuration → Add optional claim → ID → email). No code change needed.
- Is `mail` absent? The user genuinely has no Exchange mailbox. Phase 1's `mail` fallback won't help; Phase 2 is required.
- Is the app registration pre-June 2023? Microsoft changed default behavior for verified email claims. Check [Microsoft's migration guide](https://learn.microsoft.com/en-us/entra/identity-platform/migrate-off-email-claim-authorization).

---

## 4. Phase 1: Verified-mailbox fallback

### 4.1 New helper: `resolve_omniauth_email`

Added via `auth.auth_class_eval` so it's available to all hooks as an instance method on the rodauth auth class.

```ruby
auth.auth_class_eval do
  def resolve_omniauth_email
    # Tier 1, source 1: standard OIDC email claim
    email = omniauth_email.to_s.strip
    return OT::Utils.normalize_email(email) if email =~ login_email_regexp

    # Tier 1, source 2: Exchange mailbox attribute
    raw = omniauth_extra&.dig("raw_info") || {}
    mail = raw["mail"].to_s.strip
    return OT::Utils.normalize_email(mail) if mail =~ login_email_regexp

    # Tier 2 claims (upn, preferred_username) intentionally excluded.
    # See spec §2 for rationale.
    nil
  end
end
```

**Design notes:**
- `login_email_regexp` is rodauth's built-in email format check, reused here for consistency with the existing `valid_email` CHECK constraint.
- `OT::Utils.normalize_email` applies NFC + `:fold` for international addresses and lowercases. Already used in the existing `account_from_omniauth` hook.
- Returns `nil` when no Tier 1 claim is available. Callers must handle nil.

### 4.2 Override: `account_from_omniauth`

```ruby
auth.account_from_omniauth do
  resolved = resolve_omniauth_email
  _account_from_login(resolved) if resolved
end
```

**Why this changes:** The existing override normalizes `omniauth_email` directly. When `omniauth_email` is nil (the #3478 case), `OT::Utils.normalize_email(nil)` returns `""`, and `_account_from_login("")` finds nothing. If the user has a `mail` attribute that would match an existing account, the lookup misses it, and the creation path tries to INSERT a duplicate.

**Replaces:** Lines 27-30 of the current `hooks/omniauth.rb`.

### 4.3 Override: `omniauth_new_account`

```ruby
auth.omniauth_new_account do
  @account = _omniauth_new_account(resolve_omniauth_email)
end
```

**Why this hook and not `before_omniauth_create_account`:** `omniauth_new_account` (gem line 118) calls `_omniauth_new_account` (gem line 173), which builds the `{ login_column => login }` hash. Setting the login value at its origin is cleaner than mutating `account[login_column]` after the fact in a validation hook. The validation hook (`before_omniauth_create_account`) should validate, not transform.

**What happens when `resolve_omniauth_email` returns nil:** `_omniauth_new_account(nil)` builds `{ email: nil }`. The subsequent `before_omniauth_create_account` hook catches the nil/malformed email and redirects to `invalid_email`. This is the correct Phase 1 behavior — users with no Tier 1 claim cannot log in until Phase 2 lands.

### 4.4 Override: `before_omniauth_create_account`

```ruby
auth.before_omniauth_create_account do
  email = account[login_column].to_s
  email_parts = email.split('@')

  if email_parts.length != 2 || email_parts.first.to_s.empty? || email_parts.last.to_s.empty?
    Auth::Logging.log_auth_event(
      :omniauth_invalid_email,
      level: :warn,
      email: OT::Utils.obscure_email(email),
      provider: omniauth_provider,
    )
    redirect '/signin?auth_error=invalid_email'
  end

  # Domain validation continues unchanged from current implementation...
  display_domain = request.env['onetime.display_domain']
  unless Onetime::SignupValidation.valid_signup_email?(email, display_domain: display_domain)
    # ... existing domain_not_allowed redirect ...
  end
end
```

**Changes from current:** Reads `account[login_column]` (the resolved value from `omniauth_new_account`) instead of `omniauth_email.to_s.strip.downcase`. No other functional change — still validates format and domain policy.

---

## 5. Phase 2: Decouple login from email (future)

Phase 2 is not in scope for the initial PR but is documented here so Phase 1 decisions don't foreclose it.

### 5.1 Schema migration

```ruby
# Migration: add login column, make email nullable
Sequel.migration do
  up do
    # Add login column (same type as email for case-insensitive matching)
    add_column :accounts, :login, :citext

    # Backfill from email
    from(:accounts).update(login: :email)

    # Now make login NOT NULL
    alter_table(:accounts) do
      set_column_not_null :login
      add_unique_constraint :login, where: { status_id: [1, 2] }
    end

    # Make email nullable, update CHECK to allow NULL
    alter_table(:accounts) do
      set_column_allow_null :email
      # Drop and recreate valid_email to allow NULL
      drop_constraint :valid_email
      add_constraint(:valid_email) { Sequel.|({email: nil}, {email: /^[^,;@ \r\n]+@[^,@; \r\n]+\.[^,@; \r\n]+$/}) }
    end
  end

  down do
    # Reverse: copy login back to email where email is NULL, drop login
    from(:accounts).where(email: nil).update(email: :login)
    alter_table(:accounts) do
      set_column_not_null :email
      drop_constraint :valid_email
      add_constraint(:valid_email) { {email: /^[^,;@ \r\n]+@[^,@; \r\n]+\.[^,@; \r\n]+$/} }
      drop_column :login
    end
  end
end
```

### 5.2 Rodauth configuration changes

```ruby
auth.login_column :login
auth.require_email_address_logins? false
auth.email_to { account[:email] }
```

Per Jeremy Evans (Discussion #422) and `doc/guides/alternative_login.rdoc`: when `login_column` isn't email, any feature that sends email needs `email_to` configured explicitly.

### 5.3 SSO accounts with no email

For users with only Tier 2 claims (no verified mailbox):
- `login` = `"{provider}:{uid}"` (e.g., `"entra:abc-123-def"`)
- `email` = NULL
- Returning-user path works via `account_identities(provider, uid)` lookup — never touches the login column

### 5.4 Recipient delivery gating

Accounts with `email = NULL` must not trigger recipient email delivery:
- The sender's email appears in subject, body, and reply-to
- An email with no recognizable sender looks like phishing and loses a major trust signal
- Gate on `account[:email].present?` in both UI (hide the recipient email field) and API (reject with explanation)
- Users can still create secrets and share via link

---

## 6. Test requirements

### 6.1 Phase 1 tests

**New test: `mail` fallback resolves correctly**
```ruby
it 'falls back to raw_info mail when info.email is nil' do
  setup_entra_mock_auth(
    email: nil,
    raw_info: { mail: 'valid@fabrikam.onmicrosoft.com' },
  )
  post_sso_callback(:oidc)
  # Should NOT redirect to invalid_email — should proceed to account creation
  expect(last_response.location.to_s).not_to include('auth_error=invalid_email')
end
```

**New test: Account linking with `mail` fallback**
```ruby
it 'links to existing account when info.email is nil but mail matches' do
  # Pre-create account with known email
  # SSO callback with info.email=nil, raw_info.mail=same email
  # Verify identity linked to existing account, no duplicate created
end
```

**New test: Linking security (critical)**
```ruby
it 'does NOT link when only preferred_username matches an existing account' do
  # Pre-create account with email 'victim@example.com'
  # SSO callback with info.email=nil, raw_info.mail=nil,
  #   raw_info.preferred_username='victim@example.com'
  # Verify: redirect to invalid_email, NOT linked to existing account
end
```

**Tripwire test updates in `omniauth_missing_email_spec.rb`:**
- Line 292 (`preferred_username`): **KEEP** `invalid_email` expectation — Tier 2, intentionally excluded
- Line 306 (`upn`): **KEEP** `invalid_email` expectation — Tier 2, intentionally excluded
- Add new tripwire for `mail`: should **succeed** (not `invalid_email`)
- Update comment block at lines 286-289 to reflect the trust-level design rather than the blanket "no fallback" framing

### 6.2 Phase 2 tests

- Account with `email = NULL` can create a secret (share via link)
- Account with `email = NULL` cannot trigger recipient email delivery (UI and API)
- Login via `{provider}:{uid}` format works with `login_column :login`
- Returning SSO user with `email = NULL` is matched by identity, not by login

---

## 7. Implementation checklist

### Phase 1 PR

- [ ] Add `resolve_omniauth_email` via `auth.auth_class_eval`
- [ ] Override `account_from_omniauth` to use `resolve_omniauth_email`
- [ ] Override `omniauth_new_account` to use `resolve_omniauth_email`
- [ ] Update `before_omniauth_create_account` to read `account[login_column]`
- [ ] Add `mail` fallback test
- [ ] Add account-linking test for `mail` fallback
- [ ] Add linking security test (preferred_username must NOT link)
- [ ] Update tripwire test comments
- [ ] Update `before_omniauth_callback_route` logging to include `raw_info["mail"]` presence

### Step 0 (diagnostic, can happen before/alongside PR)

- [ ] Capture actual auth hash from failing EntraID login
- [ ] Check app registration for verified-email claim configuration
- [ ] Document whether the specific reporter's case is config-fix or code-fix

---

## 8. Files to modify

| File | Change |
|------|--------|
| `apps/web/auth/config/hooks/omniauth.rb` | Add `resolve_omniauth_email`, update three hooks |
| `apps/web/auth/spec/integration/full/omniauth_missing_email_spec.rb` | Add `mail` fallback tests, linking security test, update tripwire comments |
| `apps/web/auth/config/base.rb` | Phase 2 only: `login_column :login` |
| `apps/web/auth/migrations/NNN_add_login_column.rb` | Phase 2 only: new migration |

---

## 9. Decision log

| Decision | Rationale | Review round |
|----------|-----------|-------------|
| Only Tier 1 claims populate email | Account linker + auto-verifier use email for authorization; unverified claims create takeover vector | Review 2 |
| `resolve_omniauth_email` as instance method via `auth_class_eval` | Needs access to `omniauth_email`, `omniauth_extra`, `login_email_regexp` — all rodauth instance methods | Review 1 |
| Data transformation in `omniauth_new_account`, not `before_omniauth_create_account` | Hook purpose: `new_account` = data origin, `before_create` = validation. Mixing them is fragile. | Review 1 |
| Use `raw_info["mail"]` not `raw_info["userPrincipalName"]` | Token claim names differ from Graph API attribute names. v2.0 has `preferred_username`, v1.0 has `upn`. Neither is `userPrincipalName`. | Review 1 |
| Diagnose before coding | The reporter's case might be an app registration toggle, not missing code. Capture the auth hash first. | Review 2 |
| Disable recipient delivery for email-less accounts | Sender email is in subject, body, reply-to. Without it the email looks like phishing. | Design discussion |
| Phase 2 login column uses `citext` | Must match existing email column's case-insensitive behavior | Review 1 |
