.. A new scriv changelog fragment.

Changed
-------

- Upgraded Familia to v2.10. Existing ``unique_index`` hashkeys now store identifiers as raw strings rather than JSON-encoded strings. Run ``rebuild_<name>_index`` (e.g. ``CustomDomain.rebuild_display_domain_index``) after deploy to convert legacy entries. (#3336)

Added
-----

- SSO self-heal: when a legacy user signs in via domain SSO, ``JoinDomainOrganization`` now repoints ``default_org_id`` to the domain org and soft-archives the personal workspace. Retries on subsequent logins if adoption partially failed. (#3336)
- ``Organization#archive!`` / ``archived?`` / ``unarchive!`` soft-archival methods backed by ``archived_at`` and ``archived_comment`` fields. (#3336)
- ``OrganizationLoader`` step 4 now skips archived default workspaces. (#3336)

Fixed
-----

- Tryouts accessing ``Familia::StringKey`` fields on unsaved parents now call ``.save`` first, satisfying Familia v2.10's ``raise_on_unsaved_parent_write`` guard. (#3336)
