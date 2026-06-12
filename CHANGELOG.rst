CHANGELOG
=========

All notable changes to Onetime Secret are documented here.

The format is based on `Keep a
Changelog <https://keepachangelog.com/en/1.1.0/>`__, and this project
adheres to `Semantic
Versioning <https://semver.org/spec/v2.0.0.html>`__.

.. raw:: html

   <!--scriv-insert-here-->

.. _changelog-v0.25.9:

v0.25.9 — 2026-06-09
====================

Added
-----

- Opt-in on-demand heap dumps for diagnosing memory growth. When
  ``HEAP_DUMP_ENABLED`` is set (default off), every OTS process (web, scheduler,
  worker, CLI) installs a ``SIGUSR2`` handler at boot; ``kill -USR2 <pid>``
  writes an ``ObjectSpace.dump_all`` snapshot to ``heap-<pid>-<epoch>.json``
  (under ``HEAP_DUMP_DIR``, default ``/var/tmp``) so operators can diagnose RSS
  vs. Ruby heap growth without attaching GDB or restarting with extra
  instrumentation. The dump runs in a spawned thread (``ObjectSpace.dump_all``
  is not signal-safe) and the handler is installed in the Puma/Sneakers master
  and inherited by forked workers. A companion ``scripts/analyze-heapdump``
  summarizes a dump (object counts by type, bytes by type, top STRING
  allocation sites). (#3366)

Security
--------

- Heap dumps are off by default and gated behind ``HEAP_DUMP_ENABLED``: a dump
  serializes live String values, so it contains plaintext secrets and key
  material, and the handler is a memory-disclosure primitive that bypasses the
  default container ptrace restriction. When enabled, dumps are written
  owner-only (``0600``) and created exclusively (``O_EXCL``) so they cannot
  clobber or follow a pre-planted symlink in a shared directory. Treat a dump
  file as a credential and delete it after analysis. (#3366)

AI Assistance
-------------

- Heap dump boot initializer, analysis script, and tests drafted with AI
  assistance. (#3366)

.. _changelog-v0.25.8:

v0.25.8 — 2026-06-06
====================

Added
-----

- SSO self-heal: when a legacy user signs in via domain SSO, ``JoinDomainOrganization`` now repoints ``default_org_id`` to the domain org and soft-archives the personal workspace. Retries on subsequent logins if adoption partially failed. (#3336)
- ``Organization#archive!`` / ``archived?`` / ``unarchive!`` soft-archival methods backed by ``archived_at`` and ``archived_comment`` fields. (#3336)
- ``OrganizationLoader`` step 4 now skips archived default workspaces. (#3336)
- Familia migration ``20260606_01_unique_index_json_to_raw`` rewrites legacy JSON-encoded ``unique_index`` values (written by Familia 2.9) to the raw 2.10 storage format, restoring generated finders such as ``CustomDomain.from_display_domain`` and the domain-based ``OrganizationLoader`` selection used for custom-domain SSO. Stale class-level indexes are discovered automatically via ``Familia.stale_indexes``; organization-scoped ``email_index`` keys are handled via an explicit SCAN pattern. Idempotent and dry-run by default. (#3347)
- Boot-time ``CheckUniqueIndexFormat`` initializer warns (non-fatally) when any class-level ``unique_index`` still holds legacy JSON-encoded data, logging the exact ``bin/ots migrate`` remediation command so a deploy that skips the rebuild no longer degrades silently. (#3347)

Changed
-------

- Upgraded Familia to v2.10. Existing ``unique_index`` hashkeys now store identifiers as raw strings rather than JSON-encoded strings. Run ``rebuild_<name>_index`` (e.g. ``CustomDomain.rebuild_display_domain_index``) after deploy to convert legacy entries. (#3336)
- Bumped Familia to v2.10.1 for its unique-index introspection API (``Familia.stale_indexes``, ``Familia.assert_indexes_current!``, ``Familia.legacy_json_encoded?``). (#3347)

Fixed
-----

- Tryouts accessing ``Familia::StringKey`` fields on unsaved parents now call ``.save`` first, satisfying Familia v2.10's ``raise_on_unsaved_parent_write`` guard. (#3336)

.. _changelog-v0.25.6:

v0.25.6 — 2026-06-01
====================

Changed
-------

- ``CustomDomain#allow_public_homepage?`` and ``allow_public_api?`` fail
  closed when the corresponding ``HomepageConfig`` / ``ApiConfig`` record is
  missing: they return ``false`` (the safe default for a public-access
  toggle) and emit an ``OT.le`` log line pointing operators at the
  ``20260417_01_backfill_homepage_config`` migration. The fallback to
  ``BrandSettings`` (which the field has been removed from) is gone. With
  the new bootstrap below, the missing-record case is data corruption
  rather than expected state — but a hot read-path predicate on a Rack
  authorization flow is the wrong layer to raise on integrity violations;
  the write path (``create!`` bootstrap, brand PUT upsert, migration)
  handles strict enforcement, and the ``?``-suffix convention of boolean
  return is preserved. Treat the log line's rate as an alertable signal.
  (#3026)
- ``CustomDomain.create!`` now bootstraps default-disabled ``HomepageConfig`` and
  ``ApiConfig`` records via the existing ``find_or_create_for_domain`` primitive,
  symmetric with the sibling-cleanup pattern in ``destroy!``. This maintains the
  per-domain config invariant going forward without requiring callers to defend
  against missing records. Rollback on a failed ``create!`` also tears down
  these records to avoid orphans. (#3026)
- Removed the legacy ``/api/domains/:extid/recipients`` endpoints (``GET`` / ``PUT`` / ``DELETE``) and their backing ``Onetime::CustomDomain::IncomingSecretsConfig`` JSON-blob model. ``CustomDomain::IncomingConfig`` is now the single source of truth for per-domain incoming recipients. The frontend service ``recipients.service.ts`` and the dual-state composable architecture in ``useIncomingConfig`` are likewise gone. (#3095)
- ``RecipientResolver#enabled?`` now returns ``false`` for any custom domain that has no ``IncomingConfig`` record. The implicit fallback to the legacy ``incoming_secrets`` jsonkey blob has been removed. (#3095)
- ``CustomDomain::IncomingConfig#public_recipients`` now returns the canonical ``{'digest' => ..., 'display_name' => ...}`` shape (string keys) used by the canonical-domain initializer and consumed by ``CreateIncomingSecret``. The earlier ``{hash:, name:}`` symbol-key shape has been retired. (#3095)
- Narrowed ``Billing`` logger scope to payment-only concerns (Stripe checkout, invoices, webhooks). Entitlement operations in ``ApplySubscriptionToOrg`` now log under the ``Ents`` category for cleaner ``DEBUG_ENTS=1`` filtering. (#3257)
- Standardized database command logging on the canonical ``DEBUG_DATABASE`` env var; the undocumented ``DATABASE_DEBUG``, ``DEBUG_VALKEY``, and ``DEBUG_REDIS`` aliases have been removed. (#3274)

Removed
-------

- Retired the legacy ``allow_public_homepage`` and ``allow_public_api`` fields
  on ``BrandSettings``. ``HomepageConfig`` and ``ApiConfig`` are the single
  source of truth post-#3023 backfill. The brand-update endpoint no longer
  accepts these keys, the serializer strips them from the branding response so
  pre-cleanup Redis hashes can't echo stale values through, and the
  ``BrandSettings#allow_public_homepage?`` / ``allow_public_api?`` predicates
  are gone. (#3026)
- Frontend Zod schemas dropped matching ``allow_public_homepage`` /
  ``allow_public_api`` from the v2 and v3 brand shapes and the canonical
  ``brandSettingsCanonical`` contract. ``brandStore``'s default branding
  and ``isEqual`` comparator no longer reference the retired keys, and any
  legacy values returned by older backends are now silently stripped by
  the schema parsers. The ``allowPublicHomepage`` computed in
  ``identityStore`` (derived from ``homepage_config.enabled``) is unchanged
  and remains the single read-side surface for the toggle. (#3026)
- Colonel admin endpoint ``GET /api/v1/colonel/domains`` restructured to
  emit ``homepage_config`` and ``api_config`` blocks at the top level of
  each domain entry (matching the public domain serializer shape), with
  the legacy ``brand.allow_public_homepage`` / ``brand.allow_public_api``
  fields removed. ``ColonelDomains.vue`` and the colonel response Zod
  schema were updated in lockstep so the admin list no longer claims
  these are brand fields. (#3026)
- CLI ``ots domains info`` and ``ots domains verify`` outputs separated
  ``Feature Toggles`` from ``Brand Settings`` so the toggle state is no
  longer attributed to brand configuration. The verify JSON output emits
  ``homepage_config`` / ``api_config`` at the top level instead of nesting
  under ``brand``. The unused ``DomainsHelpers#format_brand_summary``
  helper was deleted — it had no callers and its name no longer
  matched the post-cleanup data model. (#3026)

Fixed
-----

- Adding a recipient on a domain's incoming-secrets configuration no longer wipes existing recipients on save. The form now reads plaintext recipients from the ``IncomingConfig`` admin endpoint and writes the merged list back via ``PUT /api/domains/:extid/incoming-config``, replacing the legacy hashed-digest model that left the client unable to round-trip prior entries. (#3095)

Deployment
----------

- Operators must run the ``migrate_incoming_secrets_to_config`` housekeeping chore as part of the deploy that picks up these changes, before traffic resumes. The chore copies entries from the legacy ``CustomDomain#incoming_secrets`` JSON blob into newly created ``IncomingConfig`` records and is idempotent::

      bin/ots housekeeping run Onetime::CustomDomain migrate_incoming_secrets_to_config

  Until the chore has run, custom domains whose recipients were configured before this change will appear disabled to the resolver. The nightly housekeeping cron will run the chore as a safety net, but the explicit invocation at deploy time is the supported path. (#3095)

- The ``jsonkey :incoming_secrets`` field declaration on ``CustomDomain`` is intentionally retained for one release so the chore can re-read the legacy data if needed. It will be removed in a follow-up release once telemetry confirms all domains have a corresponding ``IncomingConfig`` record. (#3095)

.. _changelog-v0.25.0:

v0.25.0 — 2026-04-29
====================

Changed
-------

- Invitation login flow now accepts the invite atomically during login instead of requiring a separate API call afterward. Reduces latency and prevents race conditions where login succeeds but invite acceptance fails. (#2897)
- The HomepageConfig backfill migration now emits a periodic progress line (every 250 domains) with a running stat breakdown, so operators have visibility into long-running backfills. Small datasets remain quiet — no progress output below the threshold. (#3023)
- ``CustomDomain::HomepageConfig`` and ``CustomDomain::ApiConfig`` gained ``find_or_create_for_domain``, an atomic create-if-missing class method backed by Familia's ``save_if_not_exists!`` (WATCH + MULTI). The backfill migration now uses it, so a concurrent PUT that writes before the migration does cannot have its value silently overwritten. ``upsert`` remains in place for PUT endpoint callers where last-write-wins is the intended semantic. (#3023)

Removed
-------

- Dropped the vestigial ``ots:migration_needed:db_0`` SETNX write from the connection pool initializer. The flag was never read and its name misled operators grepping Redis — actual migrations run through ``bin/ots migrate`` and ``Familia::Migration::Base``, which are independent of this key. Removes one Redis round-trip per boot. (#3027)

Fixed
-----

- Added a backfill migration for ``CustomDomain::HomepageConfig`` so domains that had ``allow_public_homepage`` enabled under the legacy BrandSettings schema continue to render correctly after the v0.25 homepage-config split. The migration is idempotent and safe to re-run; production was already manually pre-mitigated. (#3023)
- ``CustomDomain#destroy!`` now cleans up the ``HomepageConfig`` and ``ApiConfig`` sibling records in addition to the existing ``SsoConfig`` / ``MailerConfig`` / ``IncomingConfig`` cleanup. Each sibling cleanup is isolated so one failure does not block the others, preventing orphaned per-domain config records when a domain is removed. (#3023)
- ``OrganizationMembership#accept!`` now re-populates ``org_email_lookup`` with the activated membership's objid after ``activate_members_instance`` returns. The Familia 2.5.0 upgrade introduced automatic class-index cleanup on ``Horreum#destroy!``, which meant the destroy of the staged UUID model wiped the index entry the composite-keyed save had just written (both share the same ``org_email_key``). Without the restore, ``find_by_org_email`` returned ``nil`` for freshly accepted invitations. (#3023)
- ``Onetime::CustomDomain.claim_orphaned_domain`` no longer calls ``save`` inside a raw ``dbclient.multi`` block. Inside MULTI, Familia's unique-index guard issues HGETs that return ``QUEUED`` instead of real identifiers, making the guard blind — the method could raise a spurious ``RecordExistsError`` or silently bypass validation under concurrent orphan claims. The block now uses Familia 2.6.0's ``atomic_write``, which runs ``prepare_for_save`` (and therefore ``guard_unique_indexes!``) outside the transaction with real reads, then wraps the scalar HMSET, index updates, and collection mutations (``add_to_organization_domains``, ``owners``) in a single MULTI/EXEC. Independent of #3020 — same surface symptom, different root cause. (#3025)

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
