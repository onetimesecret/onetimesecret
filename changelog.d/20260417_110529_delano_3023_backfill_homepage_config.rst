.. A new scriv changelog fragment.

Fixed
-----

- Added a backfill migration for ``CustomDomain::HomepageConfig`` so domains that had ``allow_public_homepage`` enabled under the legacy BrandSettings schema continue to render correctly after the v0.25 homepage-config split. The migration is idempotent and safe to re-run; production was already manually pre-mitigated. (#3023)
- ``CustomDomain#destroy!`` now cleans up the ``HomepageConfig`` and ``ApiConfig`` sibling records in addition to the existing ``SsoConfig`` / ``MailerConfig`` / ``IncomingConfig`` cleanup. Each sibling cleanup is isolated so one failure does not block the others, preventing orphaned per-domain config records when a domain is removed. (#3023)

Changed
-------

- The HomepageConfig backfill migration now emits a periodic progress line (every 250 domains) with a running stat breakdown, so operators have visibility into long-running backfills. Small datasets remain quiet — no progress output below the threshold. (#3023)
- ``CustomDomain::HomepageConfig`` and ``CustomDomain::ApiConfig`` gained ``find_or_create_for_domain``, an atomic create-if-missing class method backed by Familia's ``save_if_not_exists!`` (WATCH + MULTI). The backfill migration now uses it, so a concurrent PUT that writes before the migration does cannot have its value silently overwritten. ``upsert`` remains in place for PUT endpoint callers where last-write-wins is the intended semantic. (#3023)
