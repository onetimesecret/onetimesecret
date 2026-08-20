.. A new scriv changelog fragment.

Fixed
-----

- Deleting an organization no longer strands domain records that point at it.
  A custom domain can drift out of its organization's domain collection while
  ``CustomDomain.owners`` still attributes it to that organization; the domain
  then disappears from the owner's domain list, and the delete guardrail —
  which counts the collection — saw nothing to refuse. The shared
  ``Onetime::Operations::Org::Delete`` operation now probes for that drift
  before any teardown step and repairs the affected domains back into the
  collection through the audited ``Operations::Domains::Repair``, which makes
  them visible again and turns the delete into an ordinary "remove your
  domains first" refusal. Repair-then-refuse, never repair-then-delete.

- Drift that cannot be repaired automatically is refused with its own
  ``drifted_domains`` status instead of a bare ``Onetime::Problem`` raised from
  ``Organization#destroy!`` mid-teardown, after the ``Organization.instances``
  entry had already been removed. The orphaned shape — an owners entry naming
  the organization while the record's own ``org_id`` is blank — is left to
  operator intent (``bin/ots domains doctor --all --repair``) rather than having
  ownership inferred from a stale index during a delete. The operator
  surfaces (CLI, colonel console) name the affected domains and the
  remediation; the customer-facing API reports only a count, because a domain
  that drifted via a transfer now belongs to a different tenant and must not
  be named to the previous owner.

- ``Organization#archive!`` now warns when it archives an organization that
  still owns domains. Archiving deliberately does not refuse — the domain SSO
  login path self-heals by archiving personal workspaces, and raising there
  would turn data drift into login failures — so ``bin/ots domains doctor``
  check #9 remains the operator surface for that state.

AI Assistance
-------------

- Claude reconciled two independently developed organization-delete
  implementations, moved the domain-drift detection and self-heal into the
  shared operation as a guardrail, and added the mocked and real-datastore
  coverage for it.
