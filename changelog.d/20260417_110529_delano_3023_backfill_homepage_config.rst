.. A new scriv changelog fragment.

Fixed
-----

- Added a backfill migration for ``CustomDomain::HomepageConfig`` so domains that had ``allow_public_homepage`` enabled under the legacy BrandSettings schema continue to render correctly after the v0.25 homepage-config split. The migration is idempotent and safe to re-run; production was already manually pre-mitigated. (#3023)
