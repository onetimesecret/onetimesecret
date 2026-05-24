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
