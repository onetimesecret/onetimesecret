.. A new scriv changelog fragment.

Fixed
-----

- The colonel customer detail page no longer times out. Its secrets and receipts
  read-outs walked the entire ``secret:*`` / ``receipt:*`` keyspace, loading every
  object one at a time to filter by owner; the 10,000-item guard counted MATCHES
  rather than keys scanned, so it never tripped for a normal account and the walk
  ran to completion on every page load. Both sections now read a bounded,
  newest-first page from a per-owner index — receipts from the existing
  ``customer:<id>:receipts`` set, secrets from a new ``customer:<id>:secrets``
  index written at the same two chokepoints as the ``secrets_active`` counter, so
  the two can only drift together. Accounts whose secrets predate the index fall
  back to a scan that is bounded by scan rounds *and* a wall-clock deadline, and
  any partial result is reported to the UI as such rather than rendered as if it
  were the whole record. A slow or failing activity lookup now degrades that
  section alone — identity, plan, role, organization and billing still render.

- Revealing an email address in an admin table no longer also opens the row's
  detail drawer. The reveal toggle and its copy button now contain their own
  clicks, which fixes the same interaction across every console table that
  renders an obscured address inside a clickable row.

Added
-----

- Each row of the admin customers table links directly to the customer's full
  detail page, so an operator can escalate without opening the drawer first. It
  is a real link, so middle-click and open-in-new-tab work.
