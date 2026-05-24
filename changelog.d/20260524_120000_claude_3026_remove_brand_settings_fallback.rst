.. A new scriv changelog fragment.

Removed
-------

- Retired the legacy ``allow_public_homepage`` and ``allow_public_api`` fields
  on ``BrandSettings``. ``HomepageConfig`` and ``ApiConfig`` are the single
  source of truth post-#3023 backfill. The brand-update endpoint no longer
  accepts these keys, the serializer strips them from the branding response so
  pre-cleanup Redis hashes can't echo stale values through, and the
  ``BrandSettings#allow_public_homepage?`` / ``allow_public_api?`` predicates
  are gone. (#3026)

Changed
-------

- ``CustomDomain#allow_public_homepage?`` and ``allow_public_api?`` now raise
  ``Onetime::Problem`` when the corresponding ``HomepageConfig`` / ``ApiConfig``
  record is missing instead of silently falling back to the legacy brand value.
  The raise points operators at the ``20260417_01_backfill_homepage_config``
  migration. With the new bootstrap below the missing-record case is data
  corruption rather than expected legacy state. (#3026)
- ``CustomDomain.create!`` now bootstraps default-disabled ``HomepageConfig`` and
  ``ApiConfig`` records via the existing ``find_or_create_for_domain`` primitive,
  symmetric with the sibling-cleanup pattern in ``destroy!``. This maintains the
  per-domain config invariant going forward without requiring callers to defend
  against missing records. Rollback on a failed ``create!`` also tears down
  these records to avoid orphans. (#3026)
