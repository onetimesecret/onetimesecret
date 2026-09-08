.. A new scriv changelog fragment.

Fixed
-----

- Searching or filtering the admin console's Organizations list no longer
  loads every organization (and every owner) on each request. The endpoint
  now answers from the exact-ID and email indexes plus a bounded newest-first
  window, hydrates only the returned page, and reports ``pagination.capped``
  when a bound stopped short. On a production-sized fleet the old path, and
  its size-capped roster cache that never engaged there, pinned the web
  workers for 30-60 seconds per search and was the cause of the repeated
  outages triggered from the console.

- Every search box in the admin console (customers, domains, organizations,
  sessions, Stripe customers, the organization picker and the add-member
  dialog) now searches only when submitted (Enter or the search button).
  Typing no longer fires a request per pause, and a submit while a search is
  in flight is dropped rather than queued, so one operator can no longer
  generate a burst of concurrent index scans.

- The admin sessions list reads session blobs in batches (one ``MGET`` per
  500 keys) instead of one ``GET`` per key, cutting a full-cap list from
  roughly 10,000 round-trips to about 20. The customers and domains searches
  scan their indexes 1,000 entries per round-trip instead of 100.

Added
-----

- The admin console shows the running app version (linked to its release
  notes) in the sidebar foot, so operators no longer have to leave the console
  for a workspace page to check it.

Removed
-----

- The Organizations list's server-side roster cache and its ``refresh=1``
  bypass. The parameter is still accepted and ignored; the ``details.cache``
  block is no longer sent.
