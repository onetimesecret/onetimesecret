CHANGELOG
=========

All notable changes to Onetime Secret are documented here.

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and
this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-0.26.5:

0.26.5 — 2026-08-13
====================

Added
-----

- Added configurable link-domain selection through ``LINK_DOMAINS``. (#4063)
- Added passkey authentication and credential management behind
  ``AUTH_WEBAUTHN_ENABLED``.
- Added ``ADMIN_ALLOWED_HOSTS`` to restrict Colonel access by host. (#4062, #4127)

Changed
-------

- Hardened trusted-proxy and forwarded-host handling. (#4024, #4040)
- Admin surfaces now default to the canonical host. Configure
  ``ADMIN_ALLOWED_HOSTS`` before upgrading when Colonel uses another host;
  ``*`` disables this restriction. (#4062, #4127)
- ``GEO_HEADER`` is now used only with ``TRUSTED_PROXY_MODE=filter``. Depth-mode
  deployments should use ``GEO_DB_PATH``. (#4024, #4068)
- Renamed ``WEBAUTHN_VERIFY_ACCOUNT`` and ``WEBAUTHN_AUTOFILL`` to
  ``AUTH_WEBAUTHN_VERIFY_ACCOUNT`` and ``AUTH_WEBAUTHN_AUTOFILL``. The old names
  are deprecated.
- ``TRUSTED_PROXY_MODE`` is validated at boot; invalid values use safer
  ``filter`` mode with a warning. (#4087)

Fixed
-----

- Corrected client-IP selection in ``TRUSTED_PROXY_MODE=depth``. Deployments
  that worked around this issue should restore their actual
  ``TRUSTED_PROXY_DEPTH``. (#4024)
- Fixed forwarded-host parsing and link-domain validation. (#4040, #4063)

.. _changelog-0.26.4:

0.26.4 — 2026-08-05
====================

Added
-----

- Added organization Secret Activity, including retention controls and an audit
  events interface. (#3642, #3975, #3976, #3985, #3992)

Fixed
-----

- Improved domain configuration validation. (#3998)
- Improved sidebar text contrast. (#3994)

Security
--------

- Updated PostCSS. (#4004)

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
- Improved domain, customer, and operator-email management.

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
  controls the masthead logo. (#3612)
- Secret reads no longer change lifecycle state or extend expiration. Receipt
  access is reported through access telemetry instead. (#3633)
- Custom-domain authentication links are hidden by default. Existing domains
  require the following migration to adopt the new setting::

      bin/ots migrate --run 20260703_01_disable_homepage_auth_links

  (#3618)
- Job configuration is now managed through the ``jobs:`` block in
  ``etc/config.yaml``. Per-job ``JOBS_*`` environment variables no longer take
  effect; deployment-wide job switches remain supported. (#3775)

Deprecated
----------

- ``SITE_NAME``, ``LOGO_URL``, and ``LOGO_ALT`` are deprecated in favor of
  ``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``, and ``BRAND_LOGO_ALT``. (#3612)

Removed
-------

- Legacy API v1 responses are JSON-only.

Fixed
-----

- Global authentication settings can no longer be bypassed by per-domain
  configuration. (#3453)
- Improved resilience for secret reveal, receipt display, email delivery, and
  custom-domain branding.
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

- Added opt-in, signal-triggered heap dumps for diagnosing memory growth.
  Dumps can contain plaintext secrets and must be handled as sensitive data.
  (#3366)

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
  should run the remediation command reported at boot. (#3336, #3347)

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

- Added configurable locale fallback support.

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
- Added dead-letter email replay for authentication-critical messages. (#2530)

Changed
-------

- Unified session management on Redis-backed sessions and modernized API v2
  authentication. (#1619)
- Updated RabbitMQ fallback and dead-letter queue handling.

  Existing installs with pre-existing dead-letter queues must stop workers,
  drain any messages that must be preserved, then run::

      bin/ots queue reset --force
      bin/ots queue init

- Reorganized the frontend around domain-focused applications.

Removed
-------

- Removed deprecated custom session-management code.

Documentation
-------------

- Added authentication migration and configuration guidance.
