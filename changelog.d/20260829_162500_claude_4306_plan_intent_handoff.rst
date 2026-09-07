.. A new scriv changelog fragment.

Fixed
-----

- Paid-plan selections made before signup now survive MFA and are consumed only
  after the signed-in user reaches the billing plans flow. A failed handoff can
  be retried during its 24-hour window (#4306).

- ``/billing`` and ``/billing/plans`` now preserve plan-selector query
  parameters when resolving to organization-scoped billing pages (#4306).
