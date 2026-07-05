.. A new scriv changelog fragment.

Added
-----

- Organization audit trail: secret activity for receipts created in an
  organization's context — creation, link/status fetches, reveal, burn,
  expiry — is now recorded to a per-organization audit stream and exposed
  via ``GET /api/organizations/:extid/audit-events`` (paginated, newest
  first). Access requires the ``audit_logs`` entitlement, which the
  role/plan intersection grants to admins and owners on qualifying plans;
  this makes the previously catalog-only entitlement functional. Events
  carry receipt/secret shortids only, never full identifiers. Creator
  self-access is recorded distinctly (``creator_status_get`` /
  ``creator_secret_get``), the receipt-page view is recorded as
  ``receipt_viewed`` (unambiguous, unlike the UI word "preview"), and a
  single hammered link cannot flood the org trail — each receipt
  contributes at most its own per-receipt cap of fetch events. (#3633)

Fixed
-----

- ``Receipt#expired!`` had no state guard, so every later view of an
  already-expired receipt re-ran the transition (redundant writes and
  duplicate log entries — and duplicate audit events once the trail
  existed). The transition now only fires from a live (new/previewed)
  receipt, matching its sibling transitions. (#3633)
