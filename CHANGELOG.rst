CHANGELOG
=========

All notable changes to Onetime Secret are documented here.

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and
this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-0.0.0-rc0:

0.26.6 — 2026-08-20
======================

Added
-----

- Added an opt-in nightly entitlement re-materialization job. Enable
  ``jobs.maintenance.enabled`` and
  ``jobs.maintenance.entitlement_materialize.enabled`` to repair entitlement
  drift from verified Stripe plan data. See
  ``docs/runbooks/entitlement-rematerialization.md``. (#4203)

- Added operator organization deletion through ``bin/ots org delete ORG`` and
  Colonel, with a deletion preview and safeguards for domains, default
  workspaces, subscriptions, and sole-owner organizations.

- Added organization unique-index diagnostics and safe repairs to
  ``bin/ots org doctor``. Use ``--repair`` for missing and stale entries;
  duplicate live values are reported for operator resolution.

- ``SENTRY_FRONTEND_PROJECT`` is an optional repository secret for selecting
  the Sentry project that receives frontend source maps. Set it when that
  project is not ``frontend``; its value must also be included in
  ``SENTRY_PROJECTS``.

- Added the Colonel proxy-header diagnostic at
  ``/api/colonel/system/proxy-headers``. Configure explicit
  ``ADMIN_ALLOWED_HOSTS`` and ``ADMIN_ALLOWED_CIDRS`` before use; see
  ``docs/operations/proxy-header-diagnostic.md``. (#4233)

Changed
-------

- Customer organization deletion now requires cancellation of subscriptions
  that can still bill.

- ``SSO_FORM_ACTION_ORIGINS`` is now only needed for split-endpoint OIDC
  configurations; tenant IdP origins on custom domains are allowed
  automatically.

- Billing-enabled deployments must grant ``audit_logs`` to plans that need
  shared receipt listings, then run ``bin/ots billing catalog sync``.

Fixed
-----

- Organization-doctor output now redacts indexed email addresses.

- Fixed tenant SSO on custom domains being blocked by Content-Security-Policy
  in Chromium.

- Organization deletion now detects custom-domain drift before teardown and
  refuses deletion until attached domains are removed. Repair unrecoverable
  drift with ``bin/ots domains doctor --all --repair``.

- Fixed stale custom-domain ownership after organization transfers. Use
  ``bin/ots domains doctor --all --repair`` to repair existing drift.

- Fixed domain-scoped receipt listings being unavailable to authorized users.

- Fixed Stripe checkout webhooks failing when they race organization creation.

- Fixed Colonel organization-deletion previews reporting domain drift.

- Fixed tenant SSO on custom domains behind proxies that rewrite ``Host``.

- Magic-link, password-reset, account-verification and SSO link-confirmation
  emails now point at the domain the recipient signed in from, instead of the
  canonical host, on deployments behind a proxy that rewrites ``Host``.

- WebAuthn assertions on custom domains are now verified against the domain the
  browser is on.

- CI now extracts frontend build assets from the published image and uploads
  their source maps to Sentry, with preflight and post-upload delivery checks.

- Fixed federated deployments where newly created Stripe subscriptions could
  leave organizations in another region on the free tier until a later
  subscription event. (#4231)

Security
--------

- Customer organization deletion now refuses to delete a default workspace.

- The example Caddyfile now strips client-supplied ``X-Forwarded-Host`` before
  proxying requests.

- ``/api/v2/version`` and ``/api/v3/version`` now require session or Basic Auth.
  Update unauthenticated version probes; anonymous pages and API responses no
  longer expose application or Ruby version details. (#4195)

Documentation
-------------

- Corrected Entra sovereign-cloud SSO guidance. Use an ``oidc`` provider with
  the sovereign v2.0 issuer.

- Documented host handling for deployments with a Host-rewriting proxy in the
  example Caddyfile.

AI Assistance
-------------

- Claude assisted with entitlement re-materialization, configuration, tests,
  and its operator runbook.

- Claude assisted with organization-deletion tooling and coverage.

- Claude assisted with organization-index diagnostics, repair support, and
  coverage.

- Claude assisted with tenant SSO CSP handling and coverage.

- Claude assisted with organization-deletion drift handling and coverage.

- Claude assisted with domain-drift and entitlement fixes.

- Claude assisted with tenant SSO host handling and coverage.

- Claude assisted with public-host resolution for Rodauth-generated URLs and
  regression coverage.

.. _changelog-0.26.5:

0.26.5 — 2026-08-17
====================

Added
-----

- Added configurable link-domain selection through ``LINK_DOMAINS``
  (``features.domains.link_domains``). (#4063)
- Added passkey authentication and credential management behind
  ``AUTH_WEBAUTHN_ENABLED``.
- Social cards can now be disabled with ``BRAND_OG_IMAGE_URL=none``. (#4150)
- Sign-in surfaces can show the country a session came from. Country display on
  the Secret Activity trail is opt-in through
  ``SECRET_ACTIVITY_GEO_COUNTRY_ENABLED``. (#3989)
- Added ``bin/ots customers role reconcile`` to repair customer role-index
  drift. It runs as a dry-run by default; use ``--apply`` to write repairs.
  (#3974)
- Added SMTP2GO as a mail provider (``MAIL_PROVIDER=smtp2go``), including
  sender-domain verification.

Changed
-------

- ``TRUSTED_PROXY_MODE=depth`` now requires an explicit trust-at-edge decision.
  Ensure the origin is reachable only through the proxy tier. (#4024, #4040)
- Colonel now defaults to the canonical ``DEFAULT_DOMAIN``/``HOST``. Configure
  ``ADMIN_ALLOWED_HOSTS`` before upgrading when Colonel uses another host; ``*``
  disables this restriction. (#4062, #4127)
- ``ADMIN_ALLOWED_CIDRS`` allowlists with no valid entries now fail closed.
  (#4062)
- ``GEO_HEADER`` is used only with ``TRUSTED_PROXY_MODE=filter``. Depth-mode
  deployments should use ``GEO_DB_PATH``. (#4024, #4068)
- Renamed ``WEBAUTHN_VERIFY_ACCOUNT`` and ``WEBAUTHN_AUTOFILL`` to
  ``AUTH_WEBAUTHN_VERIFY_ACCOUNT`` and ``AUTH_WEBAUTHN_AUTOFILL``. Update these
  settings before upgrading; the old names are deprecated.
- Custom domains cannot be restricted to passkey-only sign-in.
- Invalid ``TRUSTED_PROXY_MODE`` values now use ``filter`` mode with a warning.
  (#4087)
- Session country API values now contain an ISO 3166-1 alpha-2 code or null.
- Custom-domain sign-in and sign-up are now served only when enabled for that
  domain. Platform SSO is withheld from non-operator hosts when
  ``allow_platform_fallback_for_tenants`` is off. (#4157)
- ``BILLING_ENABLED``, ``STRIPE_AUTOMATIC_TAX`` and ``RABBITMQ_VERIFY_PEER`` now
  accept ``1/true/yes/on/y/t`` and ``0/false/no/off/n/f`` (case-insensitive).
  Invalid values prevent boot; other ``*_ENABLED`` variables are unchanged.

Fixed
-----

- Corrected client-IP selection in ``TRUSTED_PROXY_MODE=depth``. Deployments
  that worked around this issue should restore their actual
  ``TRUSTED_PROXY_DEPTH``. (#4024)
- Fixed forwarded-host parsing and link-domain validation. (#4040, #4063)
- Social cards now use available brand assets, and custom domains no longer
  inherit the install's social image. (#4150)
- Fixed custom-domain ``HttpOrigin`` 403s. (#4170, #4181)
- Fixed full-mode custom-domain sign-in and sign-up routes ignoring per-domain
  opt-in settings; unavailable policy data now returns ``503``. (#4169, #4184,
  #4157)
- Fixed SSO routes returning ``404`` when tenant SSO is available but platform
  SSO prerequisites are unmet. (#4165)
- Fixed SSO-only hosts accepting password and email sign-in requests when their
  per-domain configuration expressed no sign-in preference. (#4167)
- Customers provisioned through SSO are now verified at creation. Use
  ``bin/ots customers doctor --repair`` to repair existing unverified records.
  (#3973)
- The account active-sessions list now shows IP address, browser, and country.
  Existing sessions populate as users re-authenticate. (#3989)
- Fixed custom-domain verification status in workspace and Colonel UIs.
- Improved session-list loading performance in Colonel and customer views.

Security
--------

- V1 API secret creation now enforces the configured anonymous TTL ceiling
  (default 7 days), matching V2. (#4172)
- ``RABBITMQ_VERIFY_PEER`` no longer fails open for values such as ``1``,
  ``yes``, or ``TRUE``. Invalid values now prevent boot.

.. _changelog-0.26.4:

0.26.4 — 2026-08-05
====================

Added
-----

- Added organization Secret Activity, including retention controls and an audit
  events interface. Enable or disable with ``ORGS_AUDIT_LOGS_ENABLED``.
  (#3642, #3975, #3976, #3985, #3992)

Fixed
-----

- Domain configuration is now sanitized and constrained. (#3998)
- Improved sidebar text contrast. (#3994)

Security
--------

- Updated PostCSS to 8.5.23. (#4004)

.. _changelog-0.26.3:

0.26.3 — 2026-08-01
====================

Added
-----

- Added account diagnostics for support and operator tools.

Changed
-------

- Renamed ``PLAN_TTL_ANONYMOUS`` to ``TTL_MAX_ANONYMOUS``; the former remains an
  alias.
- API v3 receipts now return ``recipients`` as ``null`` or an array, and no
  longer include ``custid``.

Fixed
-----

- Restored support for Free plans without a configured price.
- Corrected tenant SSO settings and secret-duration selection.

Security
--------

- Added password-reset rate limits and hardened password reset, invite signup,
  API v2 Basic authentication, and anonymous secret TTL handling. (#3856, #3872)

.. _changelog-0.26.2:

0.26.2 — 2026-07-26
====================

Added
-----

- Added opt-in trusted-email SSO linking for single-tenant deployments.
  (#3836, #3840)
- Expanded operator tools for domains, customers, organizations, and
  entitlements.

Changed
-------

- ``AUTH_ENABLED`` now applies to tenant SSO. (#3672)
- Improved domain repair, organization reconciliation, and email-change
  operations.

Removed
-------

- Removed ``bin/ots domains bulk-repair``; use
  ``domains doctor --all --repair`` instead.

Fixed
-----

- Restored SSO user linking and Chromium SSO redirects. (#3836, #3840, #3848)
- Hardened admin email changes and entitlement-override validation.
  (#3907, #3916)

Security
--------

- Made password-reset requests enumeration-safe and prevented verification
  updates to closed accounts. (#3857, #3916)

.. _changelog-0.26.1:

0.26.1 — 2026-07-21
====================

Added
-----

- Added configurable checkout-host allowlisting for custom domains. (#3821)
- Added brand-pack diagnostics and receipt access telemetry. (#3822, #3825,
  #3829, #3832)

Fixed
-----

- Password changes now invalidate stale sessions. (#3810, #3830)
- Corrected current-plan indicators on the pricing page. (#3824, #3827)

.. _changelog-0.26.0:

0.26.0 — 2026-07-20
====================

Added
-----

- Added a complete favicon and social-sharing icon set, with custom-domain
  overrides and reusable branding presets. (#3048, #3049)
- Added ``BRAND_LOGO_ALT`` for accessible operator-supplied logo text. (#3612)
- Custom domains can use the Incoming Secrets form as their homepage.
- Added receipt access telemetry and organization audit events for secret
  activity. (#3633)

Changed
-------

- Unbranded installs now use the neutral ``Secure Links`` identity and keyhole
  mark; configured branding is unchanged. (#3048, #3049, #3612)
- Brand settings are now centralized under ``brand:``. ``BRAND_LOGO_URL`` also
  controls the masthead logo, and ``BRAND_TOTP_ISSUER`` (defaulting to the
  product name) labels TOTP/MFA entries. Masthead layout knobs live under
  ``site.interface.ui.header.logo`` (``LOGO_LINK``, ``LOGO_SHOW_NAME``,
  ``LOGO_PROMINENT``). (#3612)
- Secret reads no longer change lifecycle state or extend expiration. Receipt
  access is reported through access telemetry instead. (#3633)
- Custom-domain authentication links are hidden by default. Existing domains
  require the following migration to adopt the new setting::

      bin/ots migrate --run 20260703_01_disable_homepage_auth_links

  (#3618)
- Job configuration is now managed through the ``jobs:`` block in
  ``etc/config.yaml``. Per-job ``JOBS_*`` environment variables no longer take
  effect; the deployment-wide switches ``JOBS_ENABLED``, ``JOBS_FALLBACK_SYNC``,
  and ``JOBS_SCHEDULER_ENABLED`` remain env-overridable. (#3775)

Deprecated
----------

- ``SITE_NAME``, ``LOGO_URL``, and ``LOGO_ALT`` (the
  ``site.interface.ui.header.branding`` path) are deprecated in favor of
  ``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``, and ``BRAND_LOGO_ALT``. (#3612)

Removed
-------

- Legacy API v1 responses are JSON-only.

Fixed
-----

- The global authentication kill switch (``AUTH_ENABLED`` / ``AUTH_SIGNIN`` /
  ``AUTH_SIGNUP``) can no longer be bypassed by per-domain configuration.
  (#3453)
- The Content-Security-Policy header is now emitted on web responses by
  default; it was previously gated behind ``CSP_ENABLED=true`` and not sent.
  Set ``CSP_ENABLED=false`` to opt out.
- The API v1 receipt endpoint no longer reveals a concealed (user-supplied)
  secret's plaintext to the creator, matching v2/v3.
- Email delivery failures during synchronous fallback no longer return
  HTTP 500 after the record was persisted; auth and invitation emails stay
  resendable. (#3486)
- Incoming secrets submitted on a custom domain now use that domain for links
  and email delivery.
- Prevented duplicate checkout sessions and subscriptions. (#2605)

Security
--------

- Password-reset responses no longer disclose whether an account exists.
  (#3486)
- Prevented concurrent requests from revealing a burn-after-reading secret more
  than once. (CWE-362)
- Federated subscription benefits are now claimed only after email verification.

.. _changelog-v0.25.11:

v0.25.11 — 2026-06-20
=====================

Fixed
-----

- Normalized secret and receipt lifespans to prevent failures caused by invalid
  stored numeric values. (#3424, #3299)
- SSO sign-in now shows an error when the identity provider does not supply a
  usable email address. (#3478)

.. _changelog-v0.25.10:

v0.25.10 — 2026-06-13
=====================

Added
-----

- Added one-click SSO from disabled homepages when a single SSO provider is the
  only sign-in method. (#3433)

Changed
-------

- Renamed the disabled-homepage ``legacy`` variant to ``closed``. The new name
  is the default; update pinned configuration accordingly. (#3433)

Fixed
-----

- Restored API and dashboard access for records with string-typed numeric
  fields. (#3424, #3268)
- Fixed MFA enrollment QR codes and setup errors. (#3431, #3455)
- Corrected client-IP masking behind trusted proxies. (#3427)
- Burn endpoints now honor ``continue=false``.

Security
--------

- Secret generation now uses cryptographically secure randomness throughout.
  (#3452)

.. _changelog-v0.25.9:

v0.25.9 — 2026-06-09
====================

Added
-----

- Added opt-in ``SIGUSR2``-triggered heap dumps (``HEAP_DUMP_ENABLED``) for
  diagnosing memory growth. Dumps can contain plaintext secrets and must be
  handled as sensitive data. (#3366)

.. _changelog-v0.25.8:

v0.25.8 — 2026-06-06
====================

Added
-----

- Legacy domain-SSO users now automatically adopt their domain organization as
  their default workspace. (#3336)
- Added organization archival and recovery support. (#3336)

Changed
-------

- Updated Familia storage indexes. Existing deployments with legacy indexes
  should run migration ``20260606_01_unique_index_json_to_raw``; boot logs a
  warning with the exact command while any remain. (#3336, #3347)

.. _changelog-v0.25.6:

v0.25.6 — 2026-06-01
====================

Changed
-------

- Consolidated custom-domain incoming-recipient configuration. Missing public
  homepage or API configuration now fails closed. (#3026, #3095)

Removed
-------

- Removed legacy custom-domain recipient endpoints and branding-based public
  homepage/API settings. (#3026, #3095)

Fixed
-----

- Saving domain recipients no longer overwrites existing entries. (#3095)

Deployment
----------

- **Action Required**: migrate existing recipient configuration before resuming
  traffic::

      bin/ots housekeeping run Onetime::CustomDomain migrate_incoming_secrets_to_config

  (#3095)

.. _changelog-v0.25.0:

v0.25.0 — 2026-04-29
====================

Changed
-------

- Invitation acceptance and custom-domain configuration are now atomic,
  improving reliability under concurrent requests. (#2897, #3023)

Fixed
-----

- Added a migration to preserve public homepage settings for existing custom
  domains. (#3023)
- Improved custom-domain deletion, organization lookup, and concurrent domain
  verification. (#3023, #3025)

.. _changelog-v0.24.2:

v0.24.2 — 2026-03-14
====================

Added
-----

- Added configurable locale fallback support via ``fallback_locale`` chains.

Changed
-------

- Expanded locale coverage and promoted all bundled locales to supported status.

Fixed
-----

- Browser language detection now recognizes regional locales. (#2668)

.. _changelog-v0.24.1:

v0.24.1 — 2026-03-12
====================

Changed
-------

- API v1 is frozen for backward compatibility. New functionality targets API
  v2 and v3. (#2615)

Fixed
-----

- Restored API v1 secret and receipt compatibility after the Familia v2 update.

.. _changelog-v0.24.0:

v0.24.0 — 2026-03-05
====================

Added
-----

- Added a unified session and authentication architecture, including migration,
  rollback, and configuration guidance. (#1619, #1673)
- Added CSRF protection, secret-reveal notifications, and dashboard onboarding
  improvements.
- Added dead-letter email replay for authentication-critical messages. Enabled
  by default; set ``JOBS_DLQ_CONSUMER_ENABLED=false`` to disable. (#2530)

Changed
-------

- Unified session management on Redis-backed sessions and modernized API v2
  authentication. (#1619)
- Updated RabbitMQ fallback and dead-letter queue handling.

  Existing installs with pre-existing dead-letter queues must stop workers,
  drain any messages that must be preserved, then run::

      bin/ots queue reset --force
      bin/ots queue init


Removed
-------

- Removed deprecated custom session-management code.

Documentation
-------------

- Added authentication migration and configuration guidance.
