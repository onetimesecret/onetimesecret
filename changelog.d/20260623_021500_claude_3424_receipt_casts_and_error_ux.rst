.. A new scriv changelog fragment.

Fixed
-----

- A transient or schema failure on the secret reveal page is no longer shown as
  "this secret has been viewed or expired"; only a genuine 404 shows that, while
  load errors get a distinct, retryable message. (#3424)

- Receipts no longer fail to load when a numeric or timestamp field is
  string-typed at rest: ``ShowReceipt`` coerces ``expiration_in_seconds`` and the
  ``previewed``/``revealed``/``burned``/``shared`` timestamps at the boundary, and
  ``expiration`` may now be null for a consumed or expired secret. (#3424)
