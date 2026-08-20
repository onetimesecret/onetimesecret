.. A new scriv changelog fragment.

Added
-----

- Added an opt-in nightly entitlement re-materialization job. Enable
  ``jobs.maintenance.enabled`` and
  ``jobs.maintenance.entitlement_materialize.enabled`` to repair entitlement
  drift from verified Stripe plan data. See
  ``docs/runbooks/entitlement-rematerialization.md``. (#4203)

AI Assistance
-------------

- Claude assisted with entitlement re-materialization, configuration, tests,
  and its operator runbook.
