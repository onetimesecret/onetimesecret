.. A new scriv changelog fragment.

Security
--------

- Single sign-on on a custom domain now creates an account only for an
  address whose domain the organization has proven it owns: the custom
  domain itself, a name below it, or another custom domain of the
  organization. A domain counts when a Colonel has overridden its
  verification, or when, under a validation strategy that checks the TXT
  record (``approximated``, ``caddy_on_demand``), it is verified and a TXT
  check has passed since (the verified flag alone does not count). Before this,
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
  sign-in creates no new accounts for such an entry. For Microsoft Entra ID
  tenants, a successful connection test now lists the two app registration
  settings to confirm by hand, ``removeUnverifiedEmailClaim`` and the
  ``xms_edov`` optional claim, and the documentation explains both. Operators can list, and on request
  unlink, tenant identities bound before this change to accounts outside
  the proven domains with ``bin/ots sso audit-email-domains``; its
  ``--issuer`` option reads the rows that
  ``bin/ots sso backfill-issuer --issuer`` stamped with an issuer other
  than the derived one, which the default scan does not reach, and the
  text report of a scan that finds no rows says so. (#4734)

- **Action required (passthrough installs with tenant SSO)**: under the
  ``passthrough`` validation strategy, the default, the verify call marks
  any registered domain verified without a DNS lookup, so a verified domain
  does not prove an email domain there. Only a Colonel override does.
  After upgrading, until a Colonel overrides a tenant domain's verification,
  tenant SSO on that domain creates no new accounts (new people are refused
  with ``domain_not_allowed``, including addresses at the tenant's own
  custom domain), and ``bin/ots sso audit-email-domains`` reports every
  identity under it as ``outside``. People whose identity is already bound
  to an account keep signing in, and each such sign-in is logged as
  ``omniauth_tenant_email_domain_unverified``. Serving custom domains does
  not change. For each organization that uses tenant SSO, confirm it owns
  the domains its people's addresses use, override each one's verification
  to true (on the admin domain page, Override Status, then "Accept ownership
  by override"; or ``POST /api/colonel/domains/:extid/override`` with
  ``verified: true``), then run the audit. The admin domain pages now offer
  that control for a domain that is verified but not by override, since
  ticking "Ownership verified" there found nothing to change. See ``docs/authentication/per-domain-sso.md``,
  "Passthrough installs". (#4734)

- **Action required (approximated and caddy_on_demand installs with tenant
  SSO)**: a verified domain proves an email domain only when a passing TXT
  check is on record for it (``verified_confirmed_at``, recorded since
  v0.26.14). A domain verified before that release and not checked since, or
  verified under ``passthrough`` before the install moved to a TXT strategy
  and not checked since, has the flag and no recorded pass, and does not
  count until a check records one (ADR-016, ADR-049). After upgrading, run
  ``bin/ots domains verify --all``, or enable the scheduled domain refresh
  job; otherwise tenant SSO creates no new accounts for addresses at such a
  domain (new people are refused with ``domain_not_allowed``). People whose
  identity is already bound to an account keep signing in.
  ``bin/ots sso audit-email-domains DOMAIN`` lists the organization's
  verified domains that have no recorded pass under ``No TXT pass:`` (JSON
  ``verified_without_txt_pass``), so it shows which domains count. Serving
  custom domains does not change. (#4734)
