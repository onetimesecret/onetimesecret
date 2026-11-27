.. A new scriv changelog fragment.

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
