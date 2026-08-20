.. A new scriv changelog fragment.

Fixed
-----

- Transferring a custom domain between organizations no longer makes the
  source organization impossible to delete. ``Operations::Domains::Transfer``
  reassigned ``CustomDomain#org_id`` and moved both organizations' domain
  collections but never updated the ``CustomDomain.owners`` class hashkey, so
  the source organization kept a stale ownership entry forever. The delete
  guardrail reads that hashkey, so it refused with ``drifted_domains`` — a
  status with no override — while ``bin/ots domains doctor`` reported nothing
  to repair, because its checks keyed off ``org_id``, which was by then
  correctly the *new* organization. ``CustomDomain.record_owner`` is now the
  single writer for that index, and both ``Transfer`` (including its rollback
  path) and ``Operations::Domains::Repair`` route through it.

- ``bin/ots domains doctor`` gained check #10, which detects and repairs
  ``CustomDomain.owners`` entries that disagree with the record's own
  ``org_id``. The index sweep is what surfaces a domain that was transferred
  *away* from the organization being scanned, since such a domain is no longer
  in that organization's collection for any per-domain check to reach.

- The drift refusal advertised ``bin/ots domains doctor --repair``, which
  printed usage and exited 0 without ``--all``, ``--org``, or an FQDN. Every
  live message now names the working invocation, ``--all --repair``.

- Domain-scoped receipt listing (``scope=domain``) returned 403 for every
  caller, including organization owners, on billing-enabled deployments,
  because no shipped plan granted the ``audit_logs`` entitlement it requires.

- Stripe ``checkout.session.completed`` no longer returns 500 when it races
  organization creation. The handler rescued only
  ``Familia::RecordExistsError``, but the ``contact_email`` reservation trips
  before the ``stripe_customer_id`` index, so the losing writer always saw
  ``Onetime::OrganizationExists``. Re-resolution now falls back to an
  ownership-checked ``contact_email`` lookup, which is the only way to reach a
  winner that carries no Stripe customer yet.

- The colonel console silently dropped the ``drifted_domains`` payload (the
  response schema omitted the key, so it was stripped) and omitted the status
  from its blocking list, so a dry run that reported drift showed no blocked
  banner and let the operator submit an apply the server then rejected.

Deployment Notes
----------------

- **Operator action required for domain-scoped receipt listing.** Effective
  entitlements are materialized into the ``Billing::Plan`` cache from Stripe
  product metadata; ``etc/billing.yaml`` is only a fallback used when that
  cache is empty. Adding ``audit_logs`` to the shipped example catalog
  therefore helps fresh installs only. Existing billing-enabled deployments
  must add ``audit_logs`` to the entitlements of every plan that should read a
  shared receipt index in their own ``etc/billing.yaml``, then run
  ``bin/ots billing catalog sync``. Until then, both ``scope=org`` and
  ``scope=domain`` receipt listing keep returning 403 for all callers,
  including owners.

AI Assistance
-------------

- Claude reviewed the merged #4211 follow-up work, found the ownership-index
  and entitlement regressions, and implemented the fixes and coverage.
