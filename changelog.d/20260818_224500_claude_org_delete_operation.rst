.. A new scriv changelog fragment.

Added
-----

- Added operator organization deletion through ``bin/ots org delete ORG`` and
  Colonel, with a deletion preview and safeguards for domains, default
  workspaces, subscriptions, and sole-owner organizations.

Security
--------

- Customer organization deletion now refuses to delete a default workspace.

Changed
-------

- Customer organization deletion now requires cancellation of subscriptions
  that can still bill.

AI Assistance
-------------

- Claude assisted with organization-deletion tooling and coverage.
