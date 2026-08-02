.. A new scriv changelog fragment.

Fixed
-----

- The **Single Sign-On** controls on a domain's *Sign-in Settings* page
  (``/org/:orgid/domains/:extid/signin``) were gated on the wrong switch. They
  read the PLATFORM SSO flag (``AUTH_SSO_ENABLED``, resolved by the config
  serializer against the *current request's* domain — the canonical workspace
  host), while per-domain SSO is TENANT SSO, whose real authorities are
  ``ORGS_SSO_ENABLED`` plus the ``manage_sso`` entitlement. On any install with
  platform SSO off, the availability toggle and the "SSO" method radio rendered
  permanently locked even for an organization fully entitled to configure tenant
  SSO. This page was the only surface gating on that axis; the domains table and
  the organization SSO tab already used ``ORGS_SSO_ENABLED`` + ``manage_sso``,
  and it now matches them.

- **Data loss:** on a domain with no sign-in configuration, the form seeded its
  ``sso_enabled`` flag from that same platform SSO flag. Because the page
  auto-saves every change as a full-replacement ``PUT``, the first edit to *any*
  field — the mode switch, the email toggle — persisted ``sso_enabled: false``
  on installs with platform SSO off. That flips
  ``SigninConfig.sso_permitted_for?`` to false and takes the domain's working
  tenant SSO sign-in buttons down. The flag is now seeded from the backend
  authority for an unconfigured domain (``sso_permitted_for?``, which defers to
  the domain's SSO credentials), so materializing the seed leaves tenant SSO
  exactly as it was running. Structurally the same failure as the
  ``signin_enabled`` bug fixed in #3817. Domains already carrying a stored
  ``sso_enabled: false`` from this bug are **not** rewritten by this release.
  Recovering one in-app requires ``ORGS_SSO_ENABLED=true`` *and* the
  ``manage_sso`` entitlement — the conditions under which the toggle is
  operable; with tenant SSO disabled install-wide there is no in-app path, and
  the flag must be turned on first.

- The SSO availability toggle reported OFF whenever the org lacked ``manage_sso``
  or tenant SSO was disabled install-wide, even when the stored value was true
  and the domain's SSO was live. Those two are management gates — the runtime
  ladder (``SsoConfig.tenant_sso_unavailable_reason``) never consults them — so
  the toggle now reports the stored value and expresses the lock through its
  disabled state alone.

- In "One specific method" mode, a domain restricted to SSO rendered a method
  list with nothing selected whenever the SSO row was filtered out, hiding the
  domain's actual configuration. The SSO row now stays visible — locked, and
  still not re-selectable — when it is the current restriction.

.. note::

   Tenant SSO is off by default (``ORGS_SSO_ENABLED``, absent ⇒ ``false``).
   These controls are *correctly* locked on an install that has not set it;
   turning them on is an operator action, not a plan upgrade.
