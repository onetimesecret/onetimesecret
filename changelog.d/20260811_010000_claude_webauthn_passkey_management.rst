.. A new scriv changelog fragment.

Added
-----

- **Passkeys (WebAuthn) are now fully functional.** The feature had been
  enable-ready behind ``AUTH_WEBAUTHN_ENABLED`` but unusable end to end: the
  sign-in ceremony posted parameter names the server never read, the settings
  page could not list or remove credentials, and no flow offered a passkey as
  a second factor. This release completes the surface:

  - *Account settings → Passkeys* lists registered credentials (new
    ``GET /auth/webauthn-credentials`` endpoint) and the Remove button works,
    with password confirmation for accounts that have a password.
  - Accounts **without** a local password — SSO-only sign-ins — can now
    register and remove passkeys. The previous configuration demanded a
    password confirmation such accounts could never satisfy; the requirement
    now applies exactly to accounts that can meet it (including legacy
    accounts whose password predates the current auth database).
  - Registering a passkey enrolls it as a **second factor**: password logins
    on such accounts route through the MFA challenge, which now offers
    "Verify with passkey" alongside TOTP and recovery codes. Signing in
    *with* a passkey never demands a second passkey ceremony. The SSO
    account-linking flow applies the same pending-second-factor rules to
    passkey-only accounts that it applies to TOTP accounts.
  - ``GET /auth/account`` reports ``passkeys_count``; ``GET /auth/mfa-status``
    reports ``otp_enabled`` and ``webauthn_enabled``.

Changed
-------

- The optional WebAuthn sub-feature flags are renamed to match the
  ``AUTH_*`` family: ``WEBAUTHN_VERIFY_ACCOUNT`` →
  ``AUTH_WEBAUTHN_VERIFY_ACCOUNT`` and ``WEBAUTHN_AUTOFILL`` →
  ``AUTH_WEBAUTHN_AUTOFILL``. Semantics are now strict: only the literal
  string ``true`` enables them (previously *any* value enabled them, so
  ``WEBAUTHN_AUTOFILL=false`` turned the feature ON). There is no compat
  shim — the parent feature was never functional, so no working install can
  be relying on the old names — but boot logs a deprecation warning if an
  old name is set.

- Custom domains can no longer be restricted to passkeys as their single
  sign-in method. Passkey credentials are scoped to the host that registered
  them (the canonical workspace), so a passkey-only custom domain could
  never complete a sign-in. The domain sign-in form no longer offers the
  option, the API rejects new writes of it, and a previously stored value
  resolves to the standard sign-in page instead of a dead passkey-only one.

Fixed
-----

- The passkey tab on the sign-in page could never complete: the browser
  ceremony posted ``webauthn_login_*`` parameters while the server reads the
  ``webauthn_auth_*`` family, and the challenge itself arrives in a ``422``
  response body that the client treated as a hard failure.

- WebAuthn credential creation options had silently dropped the
  ``userVerification`` preference (an old config translation replaced the
  whole ``authenticatorSelection`` hash instead of one key); Rodauth's
  default is restored.
