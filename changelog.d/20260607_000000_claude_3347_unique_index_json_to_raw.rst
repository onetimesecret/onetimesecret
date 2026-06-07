.. A new scriv changelog fragment.

Added
-----

- Familia migration ``20260606_01_unique_index_json_to_raw`` rewrites legacy JSON-encoded ``unique_index`` values (written by Familia 2.9) to the raw 2.10 storage format, restoring generated finders such as ``CustomDomain.from_display_domain`` and the domain-based ``OrganizationLoader`` selection used for custom-domain SSO. Stale class-level indexes are discovered automatically via ``Familia.stale_indexes``; organization-scoped ``email_index`` keys are handled via an explicit SCAN pattern. Idempotent and dry-run by default. (#3347)
- Boot-time ``CheckUniqueIndexFormat`` initializer warns (non-fatally) when any class-level ``unique_index`` still holds legacy JSON-encoded data, logging the exact ``bin/ots migrate`` remediation command so a deploy that skips the rebuild no longer degrades silently. (#3347)

Changed
-------

- Bumped Familia to v2.10.1 for its unique-index introspection API (``Familia.stale_indexes``, ``Familia.assert_indexes_current!``, ``Familia.legacy_json_encoded?``). (#3347)
