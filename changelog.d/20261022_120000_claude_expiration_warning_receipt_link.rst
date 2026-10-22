.. A new scriv changelog fragment.

Fixed
-----

- The "secret about to expire" email now links the secret's creator to their
  receipt page (``/receipt/<receipt identifier>``) on the domain the secret
  was shared from. Before this, it linked to ``/secret/`` with the first 8
  characters of the secret identifier, which never resolved. The receipt page
  shows the secret's status and expiry, and shows the share link only when
  the secret's provenance allows it. The HTML email labels the link as a
  receipt link.
- Expiration warning emails queued before this change carry no receipt
  identifier. The email worker now rejects them instead of sending a link
  that does not work.
