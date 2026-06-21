CHANGELOG
=========

All notable changes to Onetime Secret are documented here.

The format is based on `Keep a Changelog <https://keepachangelog.com/en/1.1.0/>`__, and
this project adheres to `Semantic Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-v0.25.11:

v0.25.11 — 2026-06-20
=====================

Fixed
-----

- Secrets and Receipts now guarantee a non-null integer ``lifespan``/TTL end-to-end, closing the null half of #3424. ``Receipt.spawn_pair`` — the single creation choke point — coerces ``lifespan`` to an Integer, which both stores the correct type (Familia v2 is type-preserving, so a ``String`` would persist as a ``String``) and fixes a latent bug where ``lifespan * 2`` string-multiplied the receipt's expiration. Config normalization now also coerces the confirmed leak path ``features.incoming.default_ttl`` (set from an env var via ERB, so a set ``INCOMING_DEFAULT_TTL`` yielded a ``String``) and hardens ``site.secret_options.default_ttl`` against any non-Integer, not just ``String``. The ``safe_dump`` lambdas emit a plain integer with no ``nil``/``-1`` sentinel, and the V3 ``secret``/``receipt`` contracts keep ``secret_ttl``/``receipt_ttl``/``lifespan`` as strict, non-nullable ``z.number()`` — the read-time enforcement of that invariant. An earlier patch widened those fields to ``z.number().nullable()``; it was reverted because a real record can never have an ambiguous expiration. (#3424, #3299)

- **SSO sign-in no longer freezes when the IdP returns no usable email.** When an identity provider (Entra ID, OIDC, …) authenticates a user but supplies no usable email claim, the OmniAuth callback redirects to ``/signin?auth_error=invalid_email`` and the sign-in page now reliably renders a localized error instead of a blank/"frozen" loading screen. The frontend now shows a message for *any* ``auth_error`` code — unrecognized codes (e.g. from a backend newer than the deployed bundle) fall back to a generic SSO-failure message rather than rendering nothing — and the backend callback guard now also rejects an empty local part (``@example.com``) so it can no longer fall through to account creation and 500. This is a stopgap for the frozen-screen symptom; supplying a stable identifier fallback (UPN/``oid``) for emailless SSO users is tracked separately. (#3478)

.. _changelog-v0.25.10:

v0.25.10 — 2026-06-13
=====================

Added
-----

- ``scripts/diagnostics/detect_string_typed_numerics.rb``, a read-only scan that finds Secret/Receipt records whose numeric fields are stored as JSON strings at rest (the corruption behind #3424, distinct from the non-JSON bytes that ``check_raw_email_fields.rb`` finds for #3016). The ``safe_dump`` cast keeps the API correct, but the bytes stay corrupt; this locates them and reports a per-record signature to help trace the writer. (#3424)

- One-click SSO on the disabled-homepage variants (``minimal`` and ``v1``).
  When SSO is the sole login method and a single provider is configured, the
  homepage shows a direct SSO sign-in button instead of a ``/signin`` link,
  mirroring the activation logic of the auth-method selector (global
  ``restrict_to: sso`` or a custom domain with ``enforce_sso_only``). (#3433)

- ``scripts/ip_privacy_trusted_proxy_repro.rb``, a standalone diagnostic that
  models the chained ``IPPrivacyMiddleware`` instances and prints the broken
  vs. fixed behaviour, kept for the trusted-proxy harmonization follow-up.
  (#3427)

Changed
-------

- The disabled-homepage ``legacy`` variant is renamed to ``closed`` and is now
  the default. It remains a quiet, no-CTA placeholder; self-hosters who pinned
  ``minimal`` or relied on the ``legacy`` name should update their disabled
  homepage configuration. (#3433)

- Corrected the MFA recovery-code generation comment, which inaccurately described the codes as 8-character / ``36^8``. ``new_recovery_code`` emits a CSPRNG-backed 64-bit base36 token (~13 chars, ~1.8e19 possibilities); the comment now documents the real format and entropy. No change to the generated codes. (#3455)

Fixed
-----

- Secret and Receipt API responses now coerce their numeric fields to numbers at the ``safe_dump`` serialization boundary: TTL/lifespan fields (``lifespan``, ``secret_ttl``, ``metadata_ttl``, ``receipt_ttl``) cast to integers, and the ``created``/``updated`` timestamps cast to floats so their sub-second precision (used as sorted-set scores) is preserved. Familia v2 storage is type-preserving, so a record whose numeric fields were ever written as strings (unconverted params, console writes, raw ``HSET``) hydrated them as strings and failed the strict ``z.number()`` V3 schema — recipients saw "That information is no longer available" for secrets that were never consumed, with the sender's dashboard stuck on "Previewed". The cast is a no-op for healthy records and neutralizes affected ones; it emits a plain integer with no ``null``/``-1`` sentinel, since a real record always has a lifespan (see #3299 for the write-time guarantee). (#3424, #3268)

- MFA enrollment QR codes now encode the secret the server actually
  validates. With HMAC mode enabled the frontend was reconstructing the
  ``otpauth://`` URI from ``otp_raw_secret`` (the setup-handshake key) instead
  of ``otp_setup`` (the HMAC'd key the authenticator must use), so scanned
  codes never matched and setup could not complete. The backend now emits
  Rodauth's authoritative ``provisioning_uri`` and the frontend renders it
  directly without reconstruction. (#3431)

- Behind a trusted proxy, the IP-privacy middleware now masks the real client
  IP instead of the proxy's. The middleware was mounted first in the common
  stack with no security config, so it resolved ``REMOTE_ADDR`` (ignoring
  ``X-Forwarded-For``) and overwrote the forwarded headers with a masked proxy
  address before any later strategy could read the client IP — the
  ``site.network.trusted_proxy`` setting from #3116 ran too late to help. The
  middleware stack now passes it an Otto security config that trusts the
  private proxy ranges (RFC1918, loopback, link-local, IPv6 ULA/loopback) when
  ``site.network.trusted_proxy.enabled`` is true. Direct-connection
  deployments are unaffected; the stored IP is still masked to a /24, just the
  correct one. Public-egress CDN ranges still need CIDR matching, which Otto's
  prefix-based trusted-proxy list does not do. (#3427)

- The burn endpoints (v1 and v2) now honour ``continue=false``. Both parsed
  the flag into a proper boolean in ``process_params`` but then computed
  ``greenlighted`` from the raw ``params['continue']`` instead. Because every
  non-empty string is truthy in Ruby, a request carrying the string
  ``"false"`` (the common shape for form/query submissions) burned the secret
  anyway, destroying it against the caller's explicit intent. The greenlight
  check now uses the parsed ``continue`` boolean, so only a genuine truthy
  confirmation burns the secret.

- The "Receipt state transition" audit log lines now record the actual secret
  identifier. ``Receipt#revealed!``, ``Receipt#burned!`` and ``Receipt#expired!``
  cleared ``secret_identifier`` to an empty string before building the log
  payload, so every reveal/burn/expire event was logged with ``secret_id: ""``
  — defeating the trail for incident review. The identifier is now captured
  before it is cleared (matching ``orphaned!``), so the log reflects which
  secret the event refers to.

- ``Onetime::Utils.strand`` now draws every character of a generated secret from ``SecureRandom``. The complexity branch (used by default when more than one character set is enabled) previously seeded the guaranteed one-per-set characters with ``Array#sample`` and produced the final ordering with ``Array#shuffle``, both of which fall back to Ruby's non-cryptographic Mersenne Twister PRNG. Generated passwords are now fully CSPRNG-backed; there is no change to length, character sets, or the one-char-per-set guarantee. (#3452)

- MFA OTP setup now fails visibly instead of advancing to a blank QR scan step when a setup response omits ``provisioning_uri``. The 422 (HMAC) path already failed loudly on this; the 200 (non-HMAC) path silently set an undefined ``qr_code``. Both paths now share a ``renderSetupQr`` helper. (#3455)

.. _changelog-v0.25.9:

v0.25.9 — 2026-06-09
====================

Added
-----

- **On-demand heap dumps**: Added opt-in ``SIGUSR2``-triggered heap dumps (via ``HEAP_DUMP_ENABLED``) for diagnosing process memory growth. Includes a ``scripts/analyze-heapdump`` analysis utility. (#3366)

Security
--------

- **Heap dump safety**: Dumps are disabled by default, written owner-only (``0600``) via ``O_EXCL``, and may contain plaintext secrets. Operators should treat dump files as sensitive credentials. (#3366)

AI Assistance
-------------

- Heap dump boot initializer, analysis script, and tests drafted with AI assistance. (#3366)

.. _changelog-v0.25.8:

v0.25.8 — 2026-06-06
====================

Added
-----

- **SSO self-heal**: Legacy users signing in via domain SSO now automatically adopt their domain organization as their default workspace. (#3336)
- **Organization soft-archival**: Added ``Organization#archive!``, ``archived?``, and ``unarchive!`` methods. (#3336)
- **Familia storage migration**: Added migration ``20260606_01_unique_index_json_to_raw`` to rewrite legacy JSON-encoded indexes to the raw format required by Familia 2.10, restoring broken custom-domain SSO lookups. (#3347)
- **Index validation**: Added a boot-time warning if any legacy JSON-encoded indexes remain, including the exact remediation command. (#3347)

Changed
-------

- Upgraded Familia to v2.10.1. Unique index keys are now stored as raw strings rather than JSON-encoded strings. (#3336, #3347)

Fixed
-----

- Tryouts calling writes on unsaved parent objects now save first, satisfying Familia v2.10's strict validation rules. (#3336)

.. _changelog-v0.25.6:

v0.25.6 — 2026-06-01
====================

Changed
-------

- **Config split enforcement**: ``CustomDomain#allow_public_homepage?`` and ``allow_public_api?`` now fail closed (returning ``false``) if their corresponding config records are missing, migrating completely away from the retired ``BrandSettings`` fallbacks. (#3026)
- **Auto-bootstrapping configs**: ``CustomDomain.create!`` now automatically boots default-disabled ``HomepageConfig`` and ``ApiConfig`` records, keeping configuration structures in sync. (#3026)
- **Recipient configuration consolidation**: Removed legacy domain recipient endpoints and the ``IncomingSecretsConfig`` model. Consolidated all recipient storage into the ``CustomDomain::IncomingConfig`` model. (#3095)
- **Structured logger cleanup**: Narrowed ``Billing`` logs to payments, routing subscription entitlements to ``Ents`` logs (filterable via ``DEBUG_ENTS=1``). Unified database logging under the ``DEBUG_DATABASE`` environment variable. (#3257, #3274)

Removed
-------

- **Retired brand configurations**: Fully removed the legacy ``allow_public_homepage`` and ``allow_public_api`` fields from ``BrandSettings``, their API endpoints, frontend schemas, and administrative views. (#3026)

Fixed
-----

- **Recipient management**: Fixed a bug where saving domain recipients would overwrite existing entries by moving to a merged PUT payload model on plaintext recipients. (#3095)

Deployment
----------

- **Action Required**: Operators must run the ``migrate_incoming_secrets_to_config`` housekeeping chore during deployment to migrate legacy recipient records before traffic resumes::

      bin/ots housekeeping run Onetime::CustomDomain migrate_incoming_secrets_to_config

  (#3095)

.. _changelog-v0.25.0:

v0.25.0 — 2026-04-29
====================

Changed
-------

- **Atomic invite acceptance**: Consolidated the invitation login flow to accept invitations atomically during login, eliminating race conditions and reducing API roundtrips. (#2897)
- **Atomic domain configuration**: Added ``find_or_create_for_domain`` to ``HomepageConfig`` and ``ApiConfig`` using Familia's atomic transaction primitives to avoid concurrent write clobbering. (#3023)

Removed
-------

- Removed the unused ``ots:migration_needed:db_0`` Redis write on application boot, saving one round-trip per startup. (#3027)

Fixed
-----

- **Homepage configuration backfill**: Added a migration to preserve public homepage settings for existing custom domains using the new split configuration architecture. (#3023)
- **Cascading domain deletion**: Updated ``CustomDomain#destroy!`` to reliably clean up companion configuration records, preventing orphan Redis keys. (#3023)
- **Organization lookup restoration**: Restored organization email indexes destroyed by automated cleanup logic during membership activation. (#3023)
- **Thread-safe unique index validation**: Refactored domain claiming to run unique-index validations outside of MULTI blocks, resolving intermittent concurrent verification failures. (#3025)

.. _changelog-v0.24.2:

v0.24.2 — 2026-03-14
====================

Added
-----

- ``Middleware::LocaleFallback`` Rack middleware applies the ``fallback_locale``
  config chains after Otto's initial locale detection. When a user's exact
  regional variant is unavailable, the middleware walks the configured chain to
  find the best available match (e.g. ``fr-CA`` falls back to ``fr_FR`` when
  ``fr_CA`` is not available).

- Regression tests: 29 Vitest tests for frontend locale detection, 79 RSpec
  examples for server-side locale mapping and fallback chain resolution.

Changed
-------

- Promoted 10 locales from ``incomplete`` to fully supported: ar, ca_ES, cs,
  he, hu, pt_PT, ru, sl_SI, vi, zh. Added eo (Esperanto). All 30 locales are
  at 92-94% translation coverage. The ``incomplete`` config section has been
  removed.

- Expanded ``fallback_locale`` chains to cover all regional variants (ca, da,
  el, mi, pt-BR, pt-PT, sl, sv) so related locales degrade gracefully.

Fixed
-----

- Browser language detection now works for regional locale variants (e.g.
  ``it-IT``, ``fr-FR``, ``pt-BR``). Previously, 13 of 19 production locales
  failed Accept-Language auto-detection, causing users to see English instead
  of their language. Issue #2668

- Frontend ``navigator.language`` is now read during store initialization, so
  anonymous users on public pages (e.g. secret reveal) get the correct language
  instead of always falling back to English. Issue #2668

AI Assistance
-------------

- Claude assisted with implementing the locale fallback middleware, wiring
  ``navigator.language`` into the frontend store initialization, and writing
  test coverage for both server and frontend locale detection.

.. _changelog-v0.24.1:

v0.24.1 — 2026-03-12
====================

Added
-----

- V1 API validation tooling: ``v1-capture.sh`` records request/response pairs
  from a running instance; ``v1-diff.sh`` compares two captures and flags field,
  type, status code, and header changes. Located in
  ``scripts/api-validation/bin/``. Issue #2615

Changed
-------

- V1 API is now frozen. No new fields or endpoints; new functionality targets
  V2/V3. All V1 responses emit v0.23.x field names and state values for
  backward compatibility with existing integrations. Issue #2615, PR #2626

Fixed
-----

- V1 receipt and secret decryption for Familia v2 compatibility (P0)
- ``NoMethodError`` in ``show_receipt_recent`` — now returns Receipt objects (P0)
- Field name mapping: ``identifier`` -> ``metadata_key``, ``secret_identifier``
  -> ``secret_key``, ``has_passphrase`` -> ``passphrase_required``,
  ``recipients`` -> ``recipient``, ``receipt_ttl`` -> ``metadata_ttl``,
  ``secret_value`` -> ``value``
- State value translation: ``previewed`` -> ``viewed``, ``revealed`` ->
  ``received``, ``shared`` -> ``new``
- ``custid`` emits customer email address (not internal UUID)
- ``share_domain`` returns empty string instead of null
- ``received`` timestamp falls back to ``revealed`` when empty

AI Assistance
-------------

- Claude assisted with debugging V1 compatibility regressions, designing the
  ``receipt_hsh`` field mapping, and writing validation tooling and test
  coverage.

.. _changelog-v0.24.0:

v0.24.0 — 2026-03-05
====================

<!-- SafeDump DSL migration for Familia v2.0.0-pre12 upgrade -->

Added
-----

- UUIDv7 refinements for SecureRandom, String, and Time classes with methods for generating and extracting timestamps from UUIDv7s.

- New unified session architecture using standard Onetime::Session store
- Authentication adapter pattern supporting both Redis-backed auth and future Rodauth integration
- Session helpers extracted to dedicated modules for cleaner controller code
- CSRF protection via shrimp tokens now integrated with Rack sessions

- Database migration 002_add_external_id.rb to support Otto's derived identity integration with unique indexing
- Redis session compatibility methods for validating Otto-linked authentication state

- Identity resolution middleware integrated across all applications (API v1, v2, Web Core)
- Dual authentication mode support (basic Redis vs Rodauth) with automatic detection
- External ID lookup functionality in Onetime::Customer for Otto-Rodauth identity bridging
- RodauthUser class for unified user representation with full feature access

- Account closure with automatic Otto customer cleanup in Rodauth after_close_account hook
- Enhanced V2 authentication strategies to use identity resolution middleware across all strategy types

- Comprehensive authentication configuration system with YAML-based mode control
- Authentication migration guide with step-by-step procedures and troubleshooting
- Database migration tools for customer linking and session preservation during auth mode switches
- Configuration-based authentication mode detection with environment variable fallbacks
- Rollback migration tools for safe auth mode reversal

- Git JSON merge driver for automated locale file conflict resolution. Semantic 3-way merging automatically resolves non-conflicting changes in ``src/locales/**/*.json`` files, preserving keys added on different branches without manual conflict resolution.
- ``.gitattributes`` configuration for locale JSON files to enable the custom merge driver.

- Secret reveal notifications: Users can now opt-in to receive email notifications when their secrets are viewed. Enable this feature in Account Settings > Notifications.
- New notification settings page at ``/account/settings/profile/notifications`` for managing email notification preferences.
- ``notify_on_reveal`` field on Customer model to store user notification preference.

- Dashboard experience variants: The dashboard now adapts based on user capabilities and team count, showing appropriate views for free users, single-team users, and multi-team users.
- Self-hosted feature parity: Full capabilities granted when billing is disabled for opensource/self-hosted installations.
- Team-count driven UX with onboarding flow for users with no teams.

- Development process manager (``bin/dev``) for single-command startup of backend, frontend, and worker processes using Overmind.
- Setup script (``install-dev.sh``) to symlink shared dev resources from ``~/.config/onetimesecret-dev``, run ``bundle install``, and run ``pnpm install``, enabling consistent multi-worktree development.
- New ``Procfile.dev`` defining development services: Puma backend (port 7143), Vite frontend, and background worker.

- New ``DlqEmailConsumerJob`` scheduled job replays auth-critical emails from
  the dead-letter queue (``dlq.email.message``) on a 5-minute cycle. Raw
  Rodauth emails (password reset, verify account, email change) are always
  replayed; templated auth emails are replayed only if the underlying Rodauth
  key is still valid; non-auth emails (secret links, expiration warnings) are
  discarded as stale. Enabled by default; set
  ``JOBS_DLQ_CONSUMER_ENABLED=false`` to disable. PR #2530

Changed
-------

- Updated all models to use the new SafeDump DSL, replacing the brittle ``@safe_dump_fields`` class instance variable pattern with clean, explicit ``safe_dump_field`` method calls. This improves code maintainability and follows the modern Familia v2.0 patterns.

- Customer migration now uses deterministic external ID generation based on UUID hash instead of random values.
- Session cleanup migration updated to use Familia::Refinements::TimeLiterals instead of custom time extensions.

- Controllers now use env['onetime.session'] instead of custom Onetime::Session model
- Identity resolution middleware updated to read from standard Rack sessions
- Session persistence moved from custom Familia model to Rack::Session standard
- Colonel stats tracking simplified with session counting removed (handled by middleware)

- Refactored API v2 authentication strategies to use Otto 1.5+ class-based architecture instead of lambda functions. This improves maintainability, error handling, and type safety while providing better structured authentication results. Issue #1619

- Updated API v2 logic layer to use Otto RequestContext for consistent request state management across the application. This provides better encapsulation of session, user, auth method, and request metadata. Issue #1619

- Integrated Otto customer creation with Rodauth account registration, automatically linking new accounts with derived Otto external IDs
- Unified session management by replacing Roda sessions with Redis-backed Onetime::Session for consistency across applications
- Enhanced session validation with Otto integration checks and configurable session expiration
- Updated session cookie configuration for unified naming convention (onetime.session, onetime.remembers)

- Identity resolution middleware now supports both Redis-only and Rodauth authentication modes
- All application middleware stacks updated to include centralized identity resolution
- Customer lookup enhanced with find_by_extid method for external identity resolution
- Authentication flow unified across applications with consistent user object interfaces

- V2SessionStrategy updated to leverage pre-resolved identity from IdentityResolution middleware
- V2CombinedStrategy refactored to prioritize identity resolution over basic auth with intelligent fallback
- V2OptionalStrategy enhanced with identity-aware anonymous access and improved authentication flow
- All authentication strategies now support both Rodauth and Redis session sources with unified metadata

- Updated authentication configuration structure with unified session settings and mode-specific configurations for basic and advanced auth modes.
- Enhanced AuthConfig class to support environment variable overrides and improved error handling with detailed configuration guidance.

- Publisher now supports configurable fallback strategies when RabbitMQ is
  unavailable: ``:async_thread`` (default, non-blocking), ``:sync`` (blocking),
  ``:raise`` (error), or ``:none`` (silent fail). This replaces the previous
  3-second retry delay that could block Puma threads during outages. PR #2064

- Critical auth flows (password reset, Rodauth emails) use ``:sync`` fallback
  to ensure delivery; non-critical paths (feedback) use ``:none`` to avoid
  thread proliferation.

- Renamed TeamDashboard component to TeamView for naming consistency.
- API parameter access standardized from symbol keys to string keys across account, teams, and secrets APIs.
- Team updates now use PUT instead of PATCH for full resource replacement semantics.

- **Frontend Architecture**: Restructured Vue application from flat `views/` and `components/` directories to domain-driven `apps/` structure with five interaction modes: Secret (transactional flows), Workspace (management), Session (authentication), Kernel (admin), and Billing (commerce). This migration moves ~116 files, creates 15 new files, and removes 18 redundant files. PR #2114

- Simplified ``.env.example`` by removing shell export directives and adding explicit ``NODE_ENV=production``.
- Added ``.env.sh`` symlink convention for environment sourcing.

- Replace WindowService with Pinia-based bootstrapStore as single source of truth for server-injected state
- Rename window variable from ``__ONETIME_STATE__`` to ``__BOOTSTRAP_ME__`` and delete it immediately after consumption

- DLQ message TTL is now managed via a RabbitMQ policy (``dlq-ttl``) rather
  than queue arguments. Policies are mutable at runtime; queue arguments are
  not, and caused ``PRECONDITION_FAILED`` errors on worker startup when TTL
  config changed. PR #2529

- ``bin/ots queue init`` now applies the ``dlq-ttl`` policy as step 4 via the
  Management API. ``bin/ots queue status`` reports active DLQ policies.

**Upgrading existing installs** (environments with DLQ queues declared before
this release):

.. code-block:: bash

   # Check DLQ message counts — any messages are failed jobs already dead-lettered
   bin/ots queue status

   # Stop workers, then delete and recreate all queues (destroys DLQ messages)
   bin/ots queue reset --force

   # Recreate infrastructure and apply the dlq-ttl policy
   bin/ots queue init

   # Restart workers and verify
   bin/ots queue status

If DLQ messages must be preserved, drain them before resetting (requeue or
archive via the Management UI), then proceed with the reset.

Removed
-------

- V2::Session model and all associated custom session management code
- SessionMessages mixin (functionality moved to standard session handling)
- ClearSessionMessages middleware (no longer needed with Rack::Session)
- Custom session-based tryout tests replaced with Rack::Session approach
- Deprecated customer session management methods

- NewRelic monitoring dependency from auth service production Gemfile (moved to application-level configuration)

Fixed
-----


- Fixed NameError in ShowSecretStatus API logic where `@realttl` instance variable was referenced as undefined `current_expiration` method
- Fixed syntax errors in Team and Organization models where double dots (`team..to_s`, `org..to_s`) caused parsing failures

- Auth service now properly loads Vite assets in both development and production modes, eliminating style flash and Vue app initialization errors
- Development mode loads scripts from Vite dev server with proper URL configuration for hot module replacement
- Production mode uses compiled manifest with optimized asset loading and font preloading
- Removed duplicate window.__ONETIME_STATE__ initialization that was causing conflicts
- Fixed hardcoded frontend_development flag to use dynamic configuration
- Improved script placement consistency with core app (all assets loaded in head section)
- Added critical CSS to prevent flash of unstyled content during asset loading
- Enhanced ViteAssets helper with proper dev server URL support and configuration awareness

- Fixed Redis session key reference in identity resolution middleware. Issue #1679
- Fixed missing Singleton require in auth configuration module.
- Fixed relative path in customer migration script for proper module loading.

- Fixed undefined variable `expire_after` in Rodauth session validation by using configured expiry values
- Fixed customer creation to pass email string directly instead of hash parameter
- Fixed malformed newline string literals in error backtrace output
- Fixed auth mode detection logic to properly load and use centralized configuration system
- Fixed hardcoded session expiry values to use configurable timeout settings

Documentation
-------------

- AUTHENTICATION_MIGRATION.md with complete migration procedures and rollback instructions
- Authentication configuration reference with environment-specific overrides
- Migration tool documentation with dry-run and live execution modes
- Troubleshooting guide for common migration scenarios and recovery procedures

- Added Git JSON merge driver setup instructions to README.md Development section.

AI Assistance
-------------

- Systematic migration of 10 model files (both V1 and V2 APIs) from legacy ``@safe_dump_fields`` array syntax to the new DSL. AI assistance included code analysis, pattern identification, and bulk refactoring while preserving all existing functionality and field definitions.

- Automated PR review feedback analysis identified critical runtime errors that were systematically fixed

- Session architecture implementation guided by Claude Code per issue #1673

- Significant assistance with refactoring authentication strategy architecture from lambda-based to class-based implementations, ensuring proper inheritance from Otto::Security::AuthStrategy and consistent error handling patterns.

- Used Claude Code to identify and fix session key inconsistencies and module dependencies in Phase 5 of Otto authentication integration.

- Used Claude Code to analyze PR review feedback from multiple automated tools and implement critical runtime fixes based on systematic analysis of identified issues

- RabbitMQ architecture review identified sync fallback as blocking issue.
  Claude assisted with designing the opt-in fallback parameter API and
  Thread.new implementation for Puma compatibility.

- Claude assisted with full-stack implementation including backend (Ruby email templates, API endpoint, reveal flow integration) and frontend (Vue component, Pinia store, TypeScript schema, i18n strings).

- Claude assisted with dashboard variant architecture, capability-based routing, and component refactoring.

- Claude Code assisted with planning the migration strategy, generating the migration manifest, and updating import paths across the codebase.

- Claude Code assisted with PR feedback implementation: security improvements (removing auto-install behavior), path traversal validation, and shell script best practices.

- Claude assisted with implementation of ``DlqEmailConsumerJob``, including
  idempotency design, token expiry validation, channel management, and
  tryout test coverage.

- Claude assisted with debugging CI test failures in the DLQ policy filter
  and nil/empty-array return value semantics for the Management API client.
