.. A new scriv changelog fragment.

Fixed
-----

- Fixed stale custom-domain ownership after organization transfers. Use
  ``bin/ots domains doctor --all --repair`` to repair existing drift.

- Fixed domain-scoped receipt listings being unavailable to authorized users.

- Fixed Stripe checkout webhooks failing when they race organization creation.

- Fixed Colonel organization-deletion previews reporting domain drift.

Changed
-------

- Billing-enabled deployments must grant ``audit_logs`` to plans that need
  shared receipt listings, then run ``bin/ots billing catalog sync``.

AI Assistance
-------------

- Claude assisted with domain-drift and entitlement fixes.
