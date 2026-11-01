.. A new scriv changelog fragment.

Security
--------

- Single sign-on on a custom domain now creates an account only for an
  address whose domain the organization has proven it owns: the custom
  domain itself, a name below it, or another custom domain of the
  organization. A domain counts when a Colonel has overridden its
  verification, or when it is verified under a validation strategy that
  checks the TXT record (``approximated``, ``caddy_on_demand``). Before this,
  a tenant's identity provider could create a verified account for any
  address that had no account yet, and the address owner's later password
  reset or magic link would then share that account with the tenant
  identity. The email-domain allowlist now selects among proven domains; an
  empty allowlist admits every proven domain. People who already signed in
  through a tenant identity keep signing in, and such sign-ins from an
  address outside the proven domains are logged as
  ``omniauth_tenant_email_domain_unverified`` so operators can review those
  accounts. Organizations whose people use addresses at a domain other than
  their custom domain (for example ``@acme.example`` with the custom domain
  ``secrets.acme.example``) need to add that domain as a custom domain and
  complete its TXT check before new people can sign in; the domain does not
  have to point at Onetime Secret. The allowed-domains list in the SSO
  settings is shown again and marks entries outside a proven domain, since
  such an entry admits no one. For Microsoft Entra ID tenants, a successful
  connection test now lists the two app registration settings to confirm by
  hand, ``removeUnverifiedEmailClaim`` and the ``xms_edov`` optional claim,
  and the documentation explains both. Operators can list, and on request
  unlink, tenant identities bound before this change to accounts outside
  the proven domains with ``bin/ots sso audit-email-domains``. (#4734)

- **Action required (passthrough installs with tenant SSO)**: under the
  ``passthrough`` validation strategy, the default, the verify call marks
  any registered domain verified without a DNS lookup, so a verified domain
  no longer proves an email domain there. Only a Colonel override does.
  After upgrading, until a Colonel overrides a tenant domain's verification,
  tenant SSO on that domain creates no new accounts (new people are refused
  with ``domain_not_allowed``, including addresses at the tenant's own
  custom domain), and ``bin/ots sso audit-email-domains`` reports every
  identity under it as ``outside``. People whose identity is already bound
  to an account keep signing in, and each such sign-in is logged as
  ``omniauth_tenant_email_domain_unverified``. Serving custom domains does
  not change. For each organization that uses tenant SSO, confirm it owns
  the domains its people's addresses use, override each one's verification
  to true from the admin domain page (or
  ``POST /api/colonel/domains/:extid/override`` with ``verified: true``),
  then run the audit. See ``docs/authentication/per-domain-sso.md``,
  "Passthrough installs". (#4734)
