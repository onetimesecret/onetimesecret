.. A new scriv changelog fragment.

Added
-----

- SSO can now be told to trust an identity provider's email claim for account
  linking, via a per-provider, opt-in, default-off flag:
  ``OIDC_TRUST_EMAIL_FOR_LINKING``, ``ENTRA_TRUST_EMAIL_FOR_LINKING``,
  ``GOOGLE_TRUST_EMAIL_FOR_LINKING``, ``GITHUB_TRUST_EMAIL_FOR_LINKING``, or the
  global fallback ``SSO_TRUST_EMAIL_FOR_LINKING`` (set to ``true`` to enable). When
  enabled for a provider, an SSO identity whose email matches an existing account
  is auto-linked to that account instead of being refused — restoring email-based
  SSO linking for self-hosted single-tenant operators who control both the app and
  the identity provider. It is off by default, applies only to the platform
  (environment-configured) SSO path, and is ignored on the multi-tenant (per-domain
  ``CustomDomain::SsoConfig``) surface by construction; a non-fatal boot-time warning
  fires if it is enabled while tenant SSO configs exist. Every auto-link is recorded
  as a ``warn``-level ``omniauth_email_linked_trusted_provider`` audit event. Enable
  it only where the same operator controls both the app and the IdP — trusting the
  email is equivalent to trusting the IdP never to mint a token bearing another
  user's address. (#3836, #3840)

Fixed
-----

- Restored a supported path for email-based SSO account linking on self-hosted
  single-tenant installs, which the H-3 security hardening in 0.26.0 removed. If you
  upgraded to 0.26.0 or 0.26.1 and SSO logins now bounce back to ``/signin`` with a
  generic "SSO authentication failed" message, the callback is refusing to auto-link
  an SSO identity to an existing account located only by email. This affects any
  account with no ``account_identities`` row for the exact ``(provider, uid)`` being
  presented: freshly created or seeded accounts, password-first users signing in with
  SSO for the first time, deployments that renamed a provider route (which changes the
  stored ``provider`` string and orphans every prior link at once), and IdP
  migrations. To resolve: on a single-tenant install where you control both the app
  and the IdP, enable the trusted-IdP linking flag described above; otherwise sign in
  with the account's existing method. The multi-tenant refusal is unchanged and
  intended. (#3836, #3840)
