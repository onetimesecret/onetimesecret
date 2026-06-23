.. A new scriv changelog fragment.

Fixed
-----

- A transient or schema-parse failure on the secret reveal page is no longer
  reported to the recipient as "this secret has been viewed or expired."
  ``BaseShowSecret`` now distinguishes a terminal not-found (HTTP 404 —
  consumed/expired/missing), which keeps the ``UnknownSecret`` view, from a
  network/5xx/schema failure, which renders the (previously dead) ``error`` slot
  with neutral, retryable copy. ``useSecret`` records the failing status code to
  drive the distinction. (#3424)

- Closed the remaining uncast leaks on the receipt/dashboard surface behind the
  #3424 class of failures. ``ShowReceipt`` coerces ``expiration_in_seconds`` (raw
  ``secret_ttl``) to an Integer at the boundary, and the receipt ``safe_dump``
  now casts the ``previewed``/``revealed``/``burned``/``shared`` timestamps to
  ``Integer``-or-``nil`` (they were emitted raw and uncovered by the earlier
  ``lifespan``/``created``/``updated`` casts), so a string- or empty-typed value
  can no longer trip the strict ``z.number()`` contract and null the whole
  receipt. The ``expiration`` contract is now nullable, since a consumed or
  expired receipt legitimately has no live secret expiration. (#3424)
