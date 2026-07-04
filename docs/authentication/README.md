# Authentication

How Onetime Secret authenticates users, across both auth modes and the
single-sign-on integrations.

Background on the two modes and how strategies resolve lives in
[architecture/authentication-strategies.md](../architecture/authentication-strategies.md).

## Contents

- [switching-to-full-mode.md](./switching-to-full-mode.md) — Moving an install
  from simple (Redis session) mode to full (Rodauth + SQL) mode, and what full
  mode unlocks.
- [per-install-sso.md](./per-install-sso.md) — Configuring SSO for an entire
  install (no organization to join).
- [per-domain-sso.md](./per-domain-sso.md) — Configuring SSO scoped to a custom
  domain, including the organization-join flow.
- [webauthn-credential-types.md](./webauthn-credential-types.md) — Supported
  WebAuthn credential types and their handling.
- [omniauth-testing.md](./omniauth-testing.md) — Testing patterns for the
  OmniAuth SSO flows.
