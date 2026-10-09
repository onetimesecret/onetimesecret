.. A new scriv changelog fragment.

Fixed
-----

- Signing in through a custom domain's SSO no longer archives the
  organization being joined. When the signed-in customer owned the domain
  organization and it was also their default workspace, the sign-in
  self-heal treated it as the personal workspace to retire and archived it
  on every login, so the owner and members lost organization-gated
  features. The self-heal now leaves the destination organization alone
  (#4717).

Added
-----

- ``bin/ots org unarchive ORG [--run] [--force]`` restores an archived
  organization. The default is a dry run that prints the owner, the
  archived comment and where the owner's default points; ``--run``
  applies and records one ``organization.unarchive`` audit event. See
  ``docs/runbooks/sso-self-archived-organization.md`` for the repair
  procedure (#4717).
