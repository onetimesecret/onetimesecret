# Support SSO accounts when IdP omits the email claim

**Parent issue:** #3478 (Unable to login with SSO/EntraID when the user doesn't have email address)
**Related:** #3482 (regression tests for SSO missing-email error handling)

## Problem

When a user authenticates via SSO (e.g., Microsoft Entra ID), the IdP may not include an `email` claim in the token. This happens when:

- The user has no Exchange mailbox (no license, resource account, service account)
- The app registration doesn't have the `email` optional claim configured
- The tenant doesn't release email claims for guest/B2B users
- Older app registrations (pre-June 2023) may not have verified-email enabled by default

The current fix (#3482) catches this gracefully — redirecting to `/signin?auth_error=invalid_email` instead of 500ing on the Postgres `valid_email` CHECK constraint. But it means these users simply cannot log in. The behavioral tripwire tests in `omniauth_missing_email_spec.rb:286-289` document this as intentionally temporary.

## Root cause

`rodauth-omniauth` (v0.6.2) assumes the IdP always returns an email:

> "Currently, provider login is required to return the user's email address" — [README](https://github.com/janko/rodauth-omniauth)

The gem extracts `omniauth_info["email"]` and uses it for both account creation (`_omniauth_new_account(omniauth_email)`) and account lookup/linking (`_account_from_login(omniauth_email)`). When the email is nil, the account creation path INSERTs a nil login, which violates the `NOT NULL` constraint and `valid_email` CHECK on `accounts.email`.

OTS overrides `account_from_omniauth` and `before_omniauth_create_account` (in `hooks/omniauth.rb`) but currently passes through the nil, catching it only as a validation redirect.

## Security constraint: claim trust levels

Not all IdP claims are equally trustworthy. This is the central design constraint:

**Tier 1 — Verified mailbox** (safe for `accounts.email` and account linking):
- `info.email` — standard OIDC claim, verified by the IdP
- `extra.raw_info["mail"]` — Exchange mailbox attribute, represents a deliverable address

**Tier 2 — Mutable identifier** (NOT safe for `accounts.email`):
- `extra.raw_info["upn"]` — User Principal Name, mutable, not necessarily a mailbox
- `extra.raw_info["preferred_username"]` — mutable, Microsoft explicitly warns against using for authorization

The `accounts.email` column is used by rodauth-omniauth for account linking: if an SSO login resolves to an email that matches an existing account, the gem links the identity and logs in. Writing an unverified Tier 2 claim into this column could link an SSO identity to the wrong account — an account takeover vector.

## Phased resolution

### Step 0: Diagnose the actual failing token

Before writing code, capture the auth hash from a failing EntraID login:
- If `extra.raw_info["mail"]` is present, this may be an `omniauth-entra-id` configuration issue (verified-email claim not enabled on the app registration), not a code problem
- If `mail` is absent, the user genuinely has no mailbox and needs Phase 2

### Phase 1: Verified-mailbox fallback (no schema change)

Add `extra.raw_info["mail"]` as a fallback when `info.email` is nil. Only Tier 1 claims populate the email column. Three hooks change:

1. **New helper `resolve_omniauth_email`** — encapsulates the fallback chain: `info.email` → `raw_info["mail"]`. Returns nil if no verified email found.
2. **`account_from_omniauth`** — uses `resolve_omniauth_email` for account lookup (not raw `omniauth_email`), so an existing account with a matching email is found and linked correctly.
3. **`omniauth_new_account`** — uses `resolve_omniauth_email` to build the account hash. Resolution happens at the data-origin point, not in the validation hook.
4. **`before_omniauth_create_account`** — stays focused on validation (email format guard + domain policy). No data transformation.

If `resolve_omniauth_email` returns nil (no Tier 1 claim available), the `invalid_email` redirect fires as today. Phase 1 does not attempt to use Tier 2 claims.

### Phase 2: Decouple login from email (schema migration)

For users who genuinely have no verified mailbox, separate the login identifier from the email address:

1. Add `citext` `login` column to `accounts`, backfill from `email`
2. Make `email` nullable, relax `valid_email` CHECK to allow NULL
3. Set `login_column :login`, `require_email_address_logins? false`
4. Configure `email_to { account[:email] }` for email-sending features
5. For SSO accounts with no email, generate `{provider}:{uid}` as login, leave `email` NULL
6. Disable recipient delivery for accounts with no email (the sender's address is used in subject, body, and reply-to — an email with no recognizable sender looks like phishing)

The `account_identities` table already keys on `(provider, uid)` — returning SSO users are matched by identity, not by login column, so Phase 2's synthetic login values don't affect the returning-user path.

### New tests required

- **Linking security:** Verify that an SSO login with only a `preferred_username` matching an existing account does NOT auto-link to that account
- **Flip tripwire expectations** in `omniauth_missing_email_spec.rb:291-319` when Phase 1 lands (for `mail` fallback case only; `preferred_username` and `upn` cases should KEEP the `invalid_email` expectation)
- **Phase 2:** Accounts with `email = NULL` can create secrets and share via link, but cannot trigger recipient email delivery

## References

- [Rodauth: Use a non-email login](https://rodauth.jeremyevans.net/rdoc/files/doc/guides/alternative_login_rdoc.html) — `login_column` and `email_to` configuration
- [Rodauth Discussion #422](https://github.com/jeremyevans/rodauth/discussions/422) — Jeremy Evans on `login_uses_email? false` and custom `email_to`
- [rodauth-omniauth README](https://github.com/janko/rodauth-omniauth) — email requirement stated explicitly
- [Janko: Social Login in Rails with Rodauth](https://janko.io/social-login-in-rails-with-rodauth/) — acknowledges the missing-email case (Twitter example)
- [omniauth-entra-id Issue #33](https://github.com/pond/omniauth-entra-id/issues/33) — email claim absence documented
- [Microsoft: Migrate Off Email Claim Authorization](https://learn.microsoft.com/en-us/entra/identity-platform/migrate-off-email-claim-authorization)
- [Microsoft: preferred_username is mutable](https://github.com/microsoftdocs/azure-docs/issues/14498)
- [Microsoft: ID Token Claims Reference](https://learn.microsoft.com/en-us/entra/identity-platform/id-token-claims-reference) — `oid` as stable identifier
