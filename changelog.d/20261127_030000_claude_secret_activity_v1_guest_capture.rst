.. A new scriv changelog fragment.

Added
-----

- Secret Activity now records events on secrets guests create on an
  organization's custom domain in a separate guest partition with its own
  cap (``SECRET_ACTIVITY_MAX_GUEST_EVENTS``, default 10,000), so guest
  activity cannot push out members' events.
- Identical secret and status fetches from the same network and actor within
  one window (``SECRET_ACTIVITY_COALESCE_WINDOW``, default 3600 seconds; 0
  turns it off) are stored as one row with a count. The Activity tab shows
  the count with the first and last times. Creation and lifecycle events are
  never combined.
- When a member shares on a custom domain owned by another organization, the
  events also go to the domain owner's Secret Activity. The owner is
  recorded when the secret is created, so transferring the domain later
  does not show earlier shares to the new owner.

Changed
-------

- Each organization's existing Secret Activity history moves into the new
  storage on its first write or read, and counts toward
  ``SECRET_ACTIVITY_MAX_EVENTS``: the oldest rows are removed once newer
  rows exceed the cap. ``bin/ots migrate --run
  20261127_01_migrate_secret_activity_legacy`` moves every organization at
  once.
- The Activity tab's "older activity has been trimmed" notice appears only
  after rows have actually been removed.

Fixed
-----

- Secrets created through the v1 API now reach the organization's Secret
  Activity trail. v1 creation stamps the receipt with the creator's
  organization and custom domain, indexes it the way v2 does, and records
  the ``created`` event, so the secret's later views, reveals, burns and
  expiry are recorded too. A v1 secret fetch that does not reveal the
  secret (a wrong passphrase, or a lost reveal race) records ``secret_get``,
  or ``previewed`` for the creator. Receipts created before this change stay
  off the trail.
- Secrets a guest creates on an organization's custom domain, through v1 or
  v2/v3, now record to that organization's Secret Activity trail, with the
  actor recorded as anonymous. They are not added to the organization's
  receipt list. Nothing is recorded when that organization is archived.
