# WebAuthn Credential Types

How discoverable vs non-discoverable credentials affect the login flow.

## The Two Credential Models

### Non-Discoverable (Server-Side, Current Default)

```
requireResidentKey: false
```

**Flow:**
1. User enters email
2. Server looks up account, retrieves registered credential IDs
3. Server sends `allowCredentials` list to browser
4. Browser prompts for passkey matching those IDs
5. Authenticator signs, server verifies

**Implication:** Email is required. Without it, server cannot build the `allowCredentials` list.

### Discoverable (Client-Side/Resident Keys)

```
requireResidentKey: true
residentKey: 'required'
```

**Flow:**
1. Server sends empty `allowCredentials`
2. Browser shows all passkeys stored for this origin
3. User picks one; authenticator returns credential + user handle
4. Server uses user handle to identify account

**Implication:** Email is optional. The credential itself identifies the user.

## Current Configuration

`apps/web/auth/config/features/webauthn.rb` uses Rodauth's default
`webauthn_authenticator_selection`:

```ruby
# From rodauth/lib/rodauth/features/webauthn.rb
def webauthn_authenticator_selection
  {'requireResidentKey' => false, 'userVerification' => webauthn_user_verification}
end
```

With `webauthn_user_verification 'preferred'` set in the same file, credential
creation options carry `requireResidentKey: false` and
`userVerification: 'preferred'`. `authenticatorAttachment` is not set at all,
which permits both platform (Face ID, Touch ID, Windows Hello) and
cross-platform (YubiKey) authenticators.

History: the config previously overrode the selection with
`{ authenticatorAttachment: nil }` to express the "both types" intent. Because
the override replaces the whole hash, that silently dropped
`requireResidentKey` and `userVerification` from creation options. The
override was removed; do not reintroduce one without carrying the default keys
forward.

The login route (`webauthn_login`) calls `account_from_login(login_param_value)` which requires the email to find the account before generating challenge options.

## Switching to Discoverable Credentials

The supported path is Rodauth's `webauthn_autofill` feature
(`AUTH_WEBAUTHN_AUTOFILL=true`, see `.env.reference`), which merges
`residentKey: 'required'` / `requireResidentKey: true` onto the default
selection hash (`super.merge`) and serves the conditional-UI autofill JS.

A manual override would look like:

```ruby
auth.webauthn_authenticator_selection do
  {
    'residentKey' => 'required',
    'requireResidentKey' => true,
    'userVerification' => 'preferred'
  }
end
```

Additional changes needed:
- Modify `webauthn_credentials_for_get` to allow empty `allowCredentials`
- Handle user identification from authenticator response user handle
- Existing non-discoverable credentials won't work; users must re-register

## Why This Matters

Non-discoverable is simpler (server controls credential lookup) but requires email-first UX like Stripe.

Discoverable enables true "just click and authenticate" but requires:
- Authenticators that support resident keys (most modern ones do)
- More complex server-side user identification logic
- Re-registration of existing credentials

## References

- [WebAuthn Spec: Resident Credentials](https://www.w3.org/TR/webauthn-2/#resident-credential)
- [Rodauth WebAuthn Feature](https://rodauth.jeremyevans.net/rdoc/files/doc/webauthn_rdoc.html)
- `apps/web/auth/config/features/webauthn.rb`
