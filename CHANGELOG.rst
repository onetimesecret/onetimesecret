CHANGELOG
=========

All notable changes to Onetime Secret are documented here.

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and
this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-0.26.0:

0.26.0 — 2026-07-20
======================

Added
-----

- The HTML head now emits a full favicon set: SVG favicon, Apple touch icon,
  PWA web manifest + icons, Safari pinned-tab mask icon, and Open Graph /
  Twitter ``og:image``. Per-custom-domain favicons still take precedence.
  (#3048, #3049)

- The favicon generator (``scripts/branding/``) is now a reusable, parameterized
  tool: glyph, palette, manifest name, sizing, and an optional license credit
  are all overridable via env vars or named presets (``--preset <name>`` /
  ``MARK_PRESET``), with a dependency-free test suite
  (``pnpm run gen:favicons:test``).

- Optional Onetime Secret company-brand favicon pack ships as the first preset
  (``pnpm run gen:favicons:maruhi``), rendering the "maruhi" (circled 秘) mark
  through the shared generator. Brand-neutral defaults in ``public/web/`` are
  untouched. (#3048, #3049)

- New ``BRAND_LOGO_ALT`` / ``brand.logo_alt`` setting for operator-supplied
  brand-logo alt text; falls back to an i18n string derived from the product
  name when unset. (#3612)

- Custom domains can now present the Incoming Secrets form as their public
  homepage, via a three-way Homepage selector — private landing page, secret
  creation form, or incoming secrets form (stored as ``secrets_mode`` on the
  per-domain HomepageConfig). The incoming option requires incoming secrets
  enabled with at least one recipient, and fails closed to the private landing
  page if that later lapses. Existing domains are unaffected.

- Access telemetry on the receipt: every fetch of a secret's link or status is
  recorded as an append-only event on the receipt's access timeline. Receipt
  details now expose ``view_count`` (previously always ``null``),
  ``first_access``, and ``last_access``, so creators can see whether and when a
  link was accessed even after the secret is consumed. (#3633)

- Organization audit trail: secret activity for receipts created in an
  organization's context (creation, link/status fetches, reveal, burn, expiry)
  is recorded to a per-organization audit stream, exposed via
  ``GET /api/organizations/:extid/audit-events`` (paginated, newest first).
  Requires the ``audit_logs`` entitlement, granted to admins and owners on
  qualifying plans. Events carry receipt/secret shortids only, never full
  identifiers. (#3633)

Changed
-------

- Updated the favicon/icon/social defaults to be brand-neutral. Regenerate with
  ``pnpm gen:favicons``.

- The custom email sender form now pre-fills ``no-reply@<domain>`` and the
  organization name for domains without a saved configuration.

- The custom email sender's address-field placeholder is now localizable.

- The neutral product name on unbranded installs is now "Secure Links" instead
  of "My App", across the UI and the PWA manifest. Installs that configure
  ``BRAND_PRODUCT_NAME`` or per-domain branding are unaffected.

- Viewing a secret link no longer resets the secret's expiration; secrets now
  always expire on their original schedule regardless of how often the link is
  viewed.

- The ``brand:`` config block is now the single authority for brand identity:
  ``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``, and ``BRAND_LOGO_ALT`` brand the
  masthead, outbound emails, page titles, and MFA labels. ``BRAND_LOGO_URL`` now
  drives the masthead operator logo too (previously email-only); emails emit
  only absolute http(s) logo URLs, degrading to a text-only header otherwise.
  (#3612)

- The header config is reduced to masthead layout knobs under
  ``site.interface.ui.header.logo`` — ``href`` (``LOGO_LINK``), ``show_name``
  (``LOGO_SHOW_NAME``), and ``prominent`` (``LOGO_PROMINENT``). ``show_name``
  unset now means "show the wordmark unless a custom brand logo is configured".
  (#3612)

- Unconfigured installs now present a fully neutral identity — the "Secure
  Links" name and keyhole mark — instead of the old "One-Time Secret" defaults.
  (#3612)

- TOTP/MFA entries now use the configured product name as the issuer label when
  ``BRAND_TOTP_ISSUER`` is unset. (#3612)

- Custom-domain screens no longer show Approximated-based DNS status badges on
  installs that don't use the ``approximated`` validation strategy. Adding a
  domain on such installs now opens a simple DNS-setup screen showing the CNAME
  record to point at the canonical domain.

- Secret-link and incoming-secret emails render the secret's custom domain in
  the shared layout's header wordmark and footer link. Account and system
  emails still use the canonical host.

- Custom-domain homepages no longer show the **Create Account** and **Sign In**
  nav links by default; the per-domain ``signup_enabled`` / ``signin_enabled``
  toggles now default to *off*. Operators re-enable the links per domain via
  ``PUT /homepage-config``. The authentication kill switch is unchanged — this
  only narrows what is displayed, never widens capability. (#3618)

- **Action Required**: existing custom domains have these flags persisted as
  ``true``, so a code-only default change cannot reach them. A data migration
  resets the stored values; run it during deployment::

      bin/ots migrate --run 20260703_01_disable_homepage_auth_links

  The migration is idempotent and preserves each domain's homepage ``enabled``
  setting. (#3618)

- ``GET /api/incoming/config`` on custom domains now reports ``enabled: false``
  when the domain's incoming config has no recipients, so the /incoming page
  shows its disabled state instead of an unsubmittable form.

- Reading a secret no longer changes it: ``GET /secret/:identifier`` and
  ``/status`` (v2 and v3) no longer advance the secret from ``new`` to
  ``previewed`` as a side effect. Lifecycle state now advances only on a genuine
  reveal or burn. (#3633)

- ``previewed`` is retired as a receipt lifecycle *state* — new receipts move
  ``new -> revealed/burned/expired/orphaned`` only. The creator's own
  secret-link open is now surfaced from the access timeline (``view_count`` /
  ``first_access``) rather than a mutated field. The ``is_previewed`` attribute
  now means "the link has been accessed at least once", keeping the receipt page
  and dashboard working unchanged. Legacy ``previewed``/``viewed`` records still
  report ``true``. (#3633)

- The legacy v1 secret and receipt read endpoints no longer advance state on a
  GET, matching v2. (#3633)

- The V1 API receipt endpoint no longer reveals a concealed (user-supplied)
  secret's plaintext to the creator, aligning V1 with V2/V3: only generated
  values are shown, only on first view, and only within the display TTL.

Deprecated
----------

- ``SITE_NAME``, ``LOGO_URL``, and ``LOGO_ALT`` (the
  ``site.interface.ui.header.branding`` path) are deprecated in favor of
  ``BRAND_PRODUCT_NAME``, ``BRAND_LOGO_URL``, and ``BRAND_LOGO_ALT``. Legacy
  values are still honored as fallbacks; boot logs a warning but never refuses
  to start. (#3612)

Removed
-------

- The legacy v1 API is now strictly JSON-only. Its hand-rolled
  Content-Security-Policy, per-request nonce, and unused HTML-response
  capability are removed; CSP is owned solely by Otto's response layer.

- The 32 tuning/toggle ``JOBS_*`` environment variables (per-job ``enabled``,
  ``interval``, ``batch_size``, ``cron``, ``*_hours``, ``sample_size``,
  ``rate_limit``, ``auto_repair``, …) no longer take effect; their defaults are
  now inlined in ``etc/defaults/config.defaults.yaml``. Tune these jobs via the
  ``jobs:`` block of your ``etc/config.yaml`` override instead. The three
  deploy-time switches — ``JOBS_ENABLED``, ``JOBS_FALLBACK_SYNC``, and
  ``JOBS_SCHEDULER_ENABLED`` — remain env-overridable. (#3775)

Fixed
-----

- The global authentication kill switch (``AUTH_ENABLED`` / ``AUTH_SIGNIN`` /
  ``AUTH_SIGNUP``) is now authoritative over per-domain sign-in and sign-up
  configuration. Previously an enabled per-domain ``SigninConfig`` /
  ``SignupConfig`` could re-enable sign-in or sign-up on a custom domain even
  while the operator had disabled it globally; a domain config may now only
  narrow, never widen, the install-level setting. (#3453)

- Schema validation failures now name the field that failed — in the log message
  and a searchable ``schemaField`` Sentry tag (paths and codes only, never
  values). (#3424)

- A transient or schema failure on the secret reveal page is no longer shown as
  "this secret has been viewed or expired"; only a genuine 404 shows that, while
  load errors get a distinct, retryable message. (#3424)

- Receipts no longer fail to load when a numeric or timestamp field is
  string-typed at rest; ``ShowReceipt`` coerces the affected fields at the
  boundary, and ``expiration`` may now be null for a consumed or expired secret.
  (#3424)

- Czech and Dutch UI copy that had drifted out of each locale's informal
  register is corrected (13 Czech strings to informal ``ty``; 34 Dutch strings
  to informal ``je``/``jouw``). (#3530)

- A ``fallback: :sync`` email delivery failure (e.g. an unreachable SMTP host
  while background jobs are disabled) no longer returns HTTP 500 after the record
  was already persisted. Synchronous fallback now blocks and delivers, logging a
  failure instead of raising, so organization invitations, email-change requests,
  password resets, and Rodauth auth emails degrade gracefully and stay
  resendable. (#3486)

- The default logo and the unbranded disabled-homepage fallback now use the
  neutral keyhole mark instead of OneTimeSecret's "maruhi" (秘) branding, so
  private-label and custom-domain deployments no longer leak OTS branding.
  (#3048, #3049)

- Replaced several hardcoded OneTimeSecret brand colors (the disabled-homepage
  accent dot, decorative gradients, and a button shadow) with brand design
  tokens, so they follow per-domain branding.

- Unbranded domains now default to light button text instead of dark, matching
  the neutral brand contract. Clearing the primary color in the branding
  live-preview also resets the button-text contrast.

- Branded logo accessibility: the custom-domain masthead logo now has a
  meaningful ``alt`` (the brand name), and the default logo no longer announces
  its label twice to screen readers.

- The custom-sender API no longer rejects a blank ``from_address``; it now
  defaults to ``noreply@<domain>``, matching the frontend default.

- The disabled-homepage page no longer renders a stray rectangular surface
  behind its centered content in light mode.

- A password-reset request for a pending (unverified) account no longer returns
  a 500; ``send_verification_email`` now accepts the recipient explicitly, so
  the resend succeeds and returns the same generic success as every other case.
  (#3486)

- Custom domains with no uploaded logo no longer show the platform's site name
  beside the fallback logo; page titles and social-share meta tags fall back to
  the configured brand name instead of a hardcoded "Onetime Secret". (#3566)

- ``scripts/branding/mark.mjs``'s ``MARK_PATH`` glyph override no longer
  mis-scales glyphs whose native size isn't the keyhole's 512x1024; native
  bounds are now configurable via ``MARK_NATIVE_WIDTH`` / ``MARK_NATIVE_HEIGHT``.

- The Content-Security-Policy header is now emitted on web (HTML) responses by
  default. It was previously gated behind ``CSP_ENABLED=true`` and so not output
  as intended. Set ``CSP_ENABLED=false`` to opt out.

- The operator/install logo no longer leaks onto tenant custom domains: they
  show their own uploaded logo or the neutral mark. (#3612)

- Incoming secrets (``/incoming``) submitted on a custom domain are now bound to
  that domain: the notification email links to the secret on the custom domain
  and is delivered via that domain's sender config.

- ``Receipt#expired!`` now has a state guard, so a later view of an
  already-expired receipt no longer re-runs the transition (redundant writes,
  duplicate log and audit entries). (#3633)

- Viewing a secret's receipt/metadata page no longer mutates the secret's
  lifecycle state. The receipt-page GET previously flipped the receipt to
  ``previewed``; it now records a one-time ``receipt_viewed`` audit event
  instead, claimed atomically so simultaneous first-loads record exactly one.
  (#3633)

- A generated secret's plaintext is now shown to its creator on the receipt page
  *exactly once*. Retiring the ``previewed`` state mutation had left the value
  re-displayable on every reload; both v1 and v2 paths now claim the display
  atomically, so a repeated or concurrent load never re-reveals the value.
  (#3633)

- Checkout session creation now sends a fresh UUID idempotency key on every
  attempt instead of a deterministic time-bucketed key. Customers who retried
  checkout within the same window previously received Stripe's cached (possibly
  already-completed) session, and changed parameters raised
  ``Stripe::IdempotencyError``. Duplicate *completions* remain deduplicated by
  the ``checkout.session.completed`` webhook handler; mutation calls such as
  plan changes keep their deterministic keys. (#2605)

- Checkout now blocks an organization that already owns a genuinely active,
  non-canceling subscription from starting a second checkout session (API and
  plan-redirect paths), and the ``checkout.session.completed`` handler loudly
  logs a completed checkout that would overwrite a different, still-active
  subscription. This closes a duplicate-subscription hazard (double charge plus
  an orphaned, still-charging subscription). Currency-migration and
  resubscribe-after-cancel flows remain exempt. (#2605)

- The notifications worker's prefetch default in
  ``etc/defaults/config.defaults.yaml`` now reads ``5`` instead of ``10``,
  matching the value the worker actually runs with. No runtime behaviour change
  for a default deployment. (#3777)

Security
--------

- Password-reset requests no longer reveal whether an email address has an
  account (CWE-204). A well-formed but unregistered address now gets the same
  generic success response, with no reset secret created and no email sent.
  (#3486)

- The hardened config and logger YAML loaders now permit ``Date`` and ``Time``
  in addition to ``Symbol``. Previously an unquoted date or time in a
  deployment's ``config`` or ``logging`` YAML (e.g. ``expires: 2026-01-02``)
  raised ``Psych::DisallowedClass`` and prevented boot; arbitrary Ruby objects
  (``!ruby/object``) remain rejected. (#3498)

- Fixed a double-reveal race on burn-after-reading secrets (CWE-362). Two
  concurrent requests to the same secret link could both decrypt and return the
  plaintext before either destroyed the record, disclosing a "view once" secret
  to more than one recipient. Revealing or burning now claims the secret with an
  atomic compare-and-set, so exactly one caller may consume it.

- A burn request that loses the race no longer counts toward burn metrics nor
  reports success to the caller.

- Closed a related re-exposure window: recording that a secret link had been
  viewed wrote the secret's state unconditionally, which could momentarily
  revert a just-revealed secret to a viewable state or recreate one a concurrent
  reveal or burn had destroyed. The transition is now atomic.

- Federated subscription benefits are no longer claimed before an account's
  email is verified. Previously a pending cross-region subscription (matched by
  email hash) was claimed during standard signup, before the verification email
  was even sent — letting someone who knew a subscriber's email register it in
  another region and claim the benefit. The claim is now deferred to
  ``after_verify_account`` when email verification is enabled. SSO, invite, and
  post-payment flows are unaffected.

- Federated subscription claims made without email verification (deployments
  with ``verify_account`` disabled, an unavoidable residual of that
  configuration) are now surfaced by a loud, structured security-audit log
  recording the org, email-hash prefix, and plan. Happy-path behavior is
  unchanged.

.. _changelog-v0.25.11:

v0.25.11 — 2026-06-20
=====================

Fixed
-----

- Secrets and Receipts now guarantee a non-null integer ``lifespan``/TTL
  end-to-end, closing the null half of #3424. ``Receipt.spawn_pair`` coerces
  ``lifespan`` to an Integer (also fixing a latent ``lifespan * 2``
  string-multiply bug), and config normalization coerces
  ``features.incoming.default_ttl`` and hardens
  ``site.secret_options.default_ttl`` against any non-Integer. (#3424, #3299)

- **SSO sign-in no longer freezes when the IdP returns no usable email.** The
  OmniAuth callback now redirects to ``/signin?auth_error=invalid_email`` and
  the sign-in page renders a localized error (unrecognized codes fall back to a
  generic SSO-failure message) instead of a blank/"frozen" screen; the callback
  guard also rejects an empty local part (``@example.com``) so it can no longer
  fall through to account creation and 500. A stable identifier fallback for
  emailless SSO users is tracked separately. (#3478)

.. _changelog-v0.25.10:

v0.25.10 — 2026-06-13
=====================

Added
-----

- ``scripts/diagnostics/detect_string_typed_numerics.rb``, a read-only scan that
  finds Secret/Receipt records whose numeric fields are stored as JSON strings
  at rest (the corruption behind #3424). (#3424)

- One-click SSO on the disabled-homepage variants (``minimal`` and ``v1``): when
  SSO is the sole login method and a single provider is configured, the homepage
  shows a direct SSO sign-in button instead of a ``/signin`` link. (#3433)

- ``scripts/ip_privacy_trusted_proxy_repro.rb``, a standalone diagnostic for the
  trusted-proxy harmonization follow-up. (#3427)

Changed
-------

- The disabled-homepage ``legacy`` variant is renamed to ``closed`` and is now
  the default. Self-hosters who pinned ``minimal`` or relied on the ``legacy``
  name should update their disabled homepage configuration. (#3433)

- Corrected the MFA recovery-code generation comment (codes are a CSPRNG-backed
  64-bit base36 token, ~13 chars, not 8-character ``36^8``). No change to the
  generated codes. (#3455)

Fixed
-----

- Secret and Receipt API responses now coerce their numeric fields at the
  ``safe_dump`` boundary: TTL/lifespan fields cast to integers,
  ``created``/``updated`` timestamps cast to floats (preserving the sub-second
  precision used as sorted-set scores). Records whose numeric fields were ever
  written as strings previously failed the strict ``z.number()`` V3 schema, so
  recipients saw "That information is no longer available" and senders'
  dashboards stuck on "Previewed". (#3424, #3268)

- MFA enrollment QR codes now encode the secret the server actually validates.
  With HMAC mode the frontend was reconstructing the ``otpauth://`` URI from
  ``otp_raw_secret`` instead of ``otp_setup``, so scanned codes never matched;
  the backend now emits Rodauth's authoritative ``provisioning_uri``. (#3431)

- Behind a trusted proxy, the IP-privacy middleware now masks the real client IP
  instead of the proxy's. It previously resolved ``REMOTE_ADDR`` and overwrote
  the forwarded headers before any later strategy could read the client IP; it
  now trusts private proxy ranges when ``site.network.trusted_proxy.enabled`` is
  true. Public-egress CDN ranges still need CIDR matching, which the
  prefix-based list does not do. (#3427)

- The burn endpoints (v1 and v2) now honour ``continue=false``. Both parsed the
  flag into a boolean but computed ``greenlighted`` from the raw
  ``params['continue']``, so the string ``"false"`` (truthy in Ruby) burned the
  secret anyway. The greenlight check now uses the parsed boolean.

- The "Receipt state transition" audit log lines now record the actual secret
  identifier. ``revealed!``/``burned!``/``expired!`` cleared
  ``secret_identifier`` before building the log payload, so every event logged
  ``secret_id: ""``; the identifier is now captured before it is cleared.

- ``Onetime::Utils.strand`` now draws every character of a generated secret from
  ``SecureRandom``. The complexity branch previously used ``Array#sample`` and
  ``Array#shuffle`` (non-cryptographic Mersenne Twister). No change to length,
  character sets, or the one-char-per-set guarantee. (#3452)

- MFA OTP setup now fails visibly instead of advancing to a blank QR scan step
  when a setup response omits ``provisioning_uri`` (the non-HMAC path previously
  did this silently). (#3455)

.. _changelog-v0.25.9:

v0.25.9 — 2026-06-09
====================

Added
-----

- **On-demand heap dumps**: opt-in ``SIGUSR2``-triggered heap dumps (via
  ``HEAP_DUMP_ENABLED``) for diagnosing process memory growth, with a
  ``scripts/analyze-heapdump`` analysis utility. (#3366)

Security
--------

- **Heap dump safety**: dumps are disabled by default, written owner-only
  (``0600``) via ``O_EXCL``, and may contain plaintext secrets. Treat dump files
  as sensitive credentials. (#3366)

AI Assistance
-------------

- Heap dump boot initializer, analysis script, and tests drafted with AI
  assistance. (#3366)

.. _changelog-v0.25.8:

v0.25.8 — 2026-06-06
====================

Added
-----

- **SSO self-heal**: Legacy users signing in via domain SSO now automatically
  adopt their domain organization as their default workspace. (#3336)
- **Organization soft-archival**: Added ``Organization#archive!``, ``archived?``,
  and ``unarchive!`` methods. (#3336)
- **Familia storage migration**: Added migration
  ``20260606_01_unique_index_json_to_raw`` to rewrite legacy JSON-encoded
  indexes to the raw format required by Familia 2.10, restoring broken
  custom-domain SSO lookups. (#3347)
- **Index validation**: Added a boot-time warning if any legacy JSON-encoded
  indexes remain, including the exact remediation command. (#3347)

Changed
-------

- Upgraded Familia to v2.10.1. Unique index keys are now stored as raw strings
  rather than JSON-encoded strings. (#3336, #3347)

Fixed
-----

- Tryouts calling writes on unsaved parent objects now save first, satisfying
  Familia v2.10's strict validation rules. (#3336)

.. _changelog-v0.25.6:

v0.25.6 — 2026-06-01
====================

Changed
-------

- **Config split enforcement**: ``CustomDomain#allow_public_homepage?`` and
  ``allow_public_api?`` now fail closed (returning ``false``) if their config
  records are missing, migrating away from the retired ``BrandSettings``
  fallbacks. (#3026)
- **Auto-bootstrapping configs**: ``CustomDomain.create!`` now automatically
  boots default-disabled ``HomepageConfig`` and ``ApiConfig`` records. (#3026)
- **Recipient configuration consolidation**: Removed legacy domain recipient
  endpoints and the ``IncomingSecretsConfig`` model; consolidated all recipient
  storage into ``CustomDomain::IncomingConfig``. (#3095)
- **Structured logger cleanup**: Narrowed ``Billing`` logs to payments, routing
  subscription entitlements to ``Ents`` logs (filterable via ``DEBUG_ENTS=1``).
  Unified database logging under ``DEBUG_DATABASE``. (#3257, #3274)

Removed
-------

- **Retired brand configurations**: Fully removed the legacy
  ``allow_public_homepage`` and ``allow_public_api`` fields from
  ``BrandSettings``, their API endpoints, frontend schemas, and admin views.
  (#3026)

Fixed
-----

- **Recipient management**: Fixed a bug where saving domain recipients
  overwrote existing entries, by moving to a merged PUT payload model. (#3095)

Deployment
----------

- **Action Required**: Operators must run the
  ``migrate_incoming_secrets_to_config`` housekeeping chore during deployment to
  migrate legacy recipient records before traffic resumes::

      bin/ots housekeeping run Onetime::CustomDomain migrate_incoming_secrets_to_config

  (#3095)

.. _changelog-v0.25.0:

v0.25.0 — 2026-04-29
====================

Changed
-------

- **Atomic invite acceptance**: Consolidated the invitation login flow to accept
  invitations atomically during login, eliminating race conditions and reducing
  API roundtrips. (#2897)
- **Atomic domain configuration**: Added ``find_or_create_for_domain`` to
  ``HomepageConfig`` and ``ApiConfig`` using Familia's atomic transaction
  primitives to avoid concurrent write clobbering. (#3023)

Removed
-------

- Removed the unused ``ots:migration_needed:db_0`` Redis write on application
  boot, saving one round-trip per startup. (#3027)

Fixed
-----

- **Homepage configuration backfill**: Added a migration to preserve public
  homepage settings for existing custom domains under the new split
  configuration architecture. (#3023)
- **Cascading domain deletion**: ``CustomDomain#destroy!`` now reliably cleans up
  companion configuration records, preventing orphan Redis keys. (#3023)
- **Organization lookup restoration**: Restored organization email indexes
  destroyed by automated cleanup logic during membership activation. (#3023)
- **Thread-safe unique index validation**: Refactored domain claiming to run
  unique-index validations outside of MULTI blocks, resolving intermittent
  concurrent verification failures. (#3025)

.. _changelog-v0.24.2:

v0.24.2 — 2026-03-14
====================

Added
-----

- ``Middleware::LocaleFallback`` Rack middleware applies the ``fallback_locale``
  config chains after Otto's initial locale detection, walking the configured
  chain to find the best available match (e.g. ``fr-CA`` falls back to
  ``fr_FR`` when ``fr_CA`` is unavailable).

Changed
-------

- Promoted 10 locales from ``incomplete`` to fully supported: ar, ca_ES, cs, he,
  hu, pt_PT, ru, sl_SI, vi, zh. Added eo (Esperanto). All 30 locales are at
  92-94% translation coverage; the ``incomplete`` config section is removed.

- Expanded ``fallback_locale`` chains to cover all regional variants (ca, da,
  el, mi, pt-BR, pt-PT, sl, sv) so related locales degrade gracefully.

Fixed
-----

- Browser language detection now works for regional locale variants (e.g.
  ``it-IT``, ``fr-FR``, ``pt-BR``). Previously 13 of 19 production locales
  failed Accept-Language auto-detection, showing English instead. (#2668)

- Frontend ``navigator.language`` is now read during store initialization, so
  anonymous users on public pages (e.g. secret reveal) get the correct language
  instead of always falling back to English. (#2668)

AI Assistance
-------------

- Claude assisted with the locale fallback middleware, the ``navigator.language``
  store wiring, and test coverage for server and frontend locale detection.

.. _changelog-v0.24.1:

v0.24.1 — 2026-03-12
====================

Added
-----

- V1 API validation tooling in ``scripts/api-validation/bin/``:
  ``v1-capture.sh`` records request/response pairs from a running instance;
  ``v1-diff.sh`` compares two captures and flags field, type, status code, and
  header changes. (#2615)

Changed
-------

- V1 API is now frozen. No new fields or endpoints; new functionality targets
  V2/V3. All V1 responses emit v0.23.x field names and state values for backward
  compatibility. (#2615, PR #2626)

Fixed
-----

- V1 receipt and secret decryption for Familia v2 compatibility (P0).
- ``NoMethodError`` in ``show_receipt_recent`` — now returns Receipt objects (P0).
- Field name mapping (e.g. ``identifier`` → ``metadata_key``,
  ``secret_identifier`` → ``secret_key``, ``receipt_ttl`` → ``metadata_ttl``,
  ``secret_value`` → ``value``) and state value translation (``previewed`` →
  ``viewed``, ``revealed`` → ``received``, ``shared`` → ``new``) restored to the
  v0.23.x contract.
- ``custid`` emits customer email address (not internal UUID); ``share_domain``
  returns empty string instead of null; ``received`` timestamp falls back to
  ``revealed`` when empty.

AI Assistance
-------------

- Claude assisted with debugging V1 compatibility regressions, the
  ``receipt_hsh`` field mapping, and validation tooling and test coverage.

.. _changelog-v0.24.0:

v0.24.0 — 2026-03-05
====================

Added
-----

- UUIDv7 refinements for SecureRandom, String, and Time.

- New unified session and authentication architecture: a standard
  ``Onetime::Session`` store, an authentication adapter supporting both
  Redis-backed auth and Rodauth, identity-resolution middleware across all
  applications (API v1/v2, Web Core), dual auth-mode detection, and Otto↔Rodauth
  identity bridging (external IDs, ``RodauthUser``, account-closure cleanup).
  Includes a YAML-based auth configuration system, migration/rollback tooling,
  and a migration guide. (#1619, #1673)

- CSRF protection via shrimp tokens integrated with Rack sessions.

- Git JSON merge driver (with ``.gitattributes`` wiring) for automatic 3-way
  merging of ``src/locales/**/*.json`` conflicts.

- Secret reveal notifications: users can opt in to email when their secrets are
  viewed, via a new Notifications settings page
  (``/account/settings/profile/notifications``) and a ``notify_on_reveal``
  Customer field.

- Dashboard experience variants adapting to user capabilities and team count,
  with a no-teams onboarding flow. Self-hosted installs get full capabilities
  when billing is disabled.

- Development process manager (``bin/dev`` + ``Procfile.dev``) for single-command
  startup of backend (Puma, port 7143), Vite frontend, and worker via Overmind,
  plus an ``install-dev.sh`` setup script for multi-worktree development.

- New ``DlqEmailConsumerJob`` replays auth-critical emails from the dead-letter
  queue on a 5-minute cycle (raw Rodauth emails always; templated auth emails
  only while their key is valid; non-auth emails discarded). Enabled by default;
  set ``JOBS_DLQ_CONSUMER_ENABLED=false`` to disable. (PR #2530)

Changed
-------

- Migrated all models to the new SafeDump DSL (``safe_dump_field``), replacing
  the ``@safe_dump_fields`` class-instance-variable pattern.

- Session management unified on Redis-backed ``Onetime::Session`` (via
  ``env['onetime.session']``) instead of custom or Roda sessions, with unified
  cookie naming (``onetime.session``, ``onetime.remembers``) and Otto-integrated
  validation. Colonel stats no longer count sessions (handled by middleware).

- Refactored API v2 authentication strategies to Otto 1.5+ class-based
  architecture and adopted Otto ``RequestContext`` for request state management.
  (#1619)

- Customer migration now uses deterministic external IDs derived from the UUID
  hash instead of random values.

- Publisher supports configurable RabbitMQ fallback strategies — ``:async_thread``
  (default, non-blocking), ``:sync``, ``:raise``, or ``:none`` — replacing the
  previous blocking 3-second retry. Critical auth flows use ``:sync``;
  non-critical paths use ``:none``. (PR #2064)

- **Frontend architecture**: restructured the Vue app from flat
  ``views/``/``components/`` to a domain-driven ``apps/`` structure with five
  modes: Secret, Workspace, Session, Kernel, and Billing. (PR #2114)

- Replaced WindowService with a Pinia ``bootstrapStore`` as the single source of
  truth for server-injected state (window var renamed ``__ONETIME_STATE__`` →
  ``__BOOTSTRAP_ME__``, deleted after consumption).

- Renamed TeamDashboard to TeamView; standardized API params from symbol to
  string keys; team updates use PUT instead of PATCH.

- DLQ message TTL is now managed via a RabbitMQ policy (``dlq-ttl``) rather than
  immutable queue arguments (which caused ``PRECONDITION_FAILED`` on TTL
  changes). ``bin/ots queue init`` applies the policy; ``bin/ots queue status``
  reports it. (PR #2529)

- Simplified ``.env.example`` (removed shell export directives, added explicit
  ``NODE_ENV=production``) and added an ``.env.sh`` symlink convention.

**Upgrading existing installs** with DLQ queues declared before this release:
stop workers, then ``bin/ots queue reset --force`` (this destroys DLQ messages —
drain them first if they must be preserved) and ``bin/ots queue init`` to
recreate infrastructure and apply the ``dlq-ttl`` policy.

Removed
-------

- Removed the ``V2::Session`` model, ``SessionMessages`` mixin,
  ``ClearSessionMessages`` middleware, and other deprecated custom
  session-management code (superseded by ``Rack::Session``).

- Removed the NewRelic dependency from the auth service Gemfile (moved to
  application-level configuration).

Fixed
-----

- Fixed a ``NameError`` in ``ShowSecretStatus`` (``current_expiration`` →
  ``@realttl``) and syntax errors (double-dot ``to_s``) in the Team and
  Organization models.

- Auth service now loads Vite assets correctly in both development and
  production, eliminating the style flash and Vue init errors; added critical
  CSS to prevent flash of unstyled content and removed a duplicate
  ``window.__ONETIME_STATE__`` initialization.

- Various session/auth fixes: Redis session key reference in identity-resolution
  middleware (#1679), a missing ``Singleton`` require, configurable session-expiry
  values, and correct auth-mode detection.

Documentation
-------------

- Added ``AUTHENTICATION_MIGRATION.md`` (migration procedures, rollback,
  troubleshooting) and an authentication configuration reference. Added Git JSON
  merge driver setup instructions to the README.

AI Assistance
-------------

- Claude assisted with the SafeDump DSL migration, the Otto/Rodauth session and
  authentication refactor, the frontend ``apps/`` migration, the RabbitMQ
  fallback API, secret-reveal notifications, dashboard variants, and the
  ``DlqEmailConsumerJob``.
