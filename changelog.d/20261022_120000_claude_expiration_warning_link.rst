.. A new scriv changelog fragment.

Fixed
-----

- The "secret about to expire" email now links to the owner's receipt page
  (``/receipt/<identifier>``), where the owner can see whether the secret
  has been viewed and burn it. It linked to ``/secret/`` plus the secret's
  8-character short id, which no route resolves, so every link in every
  warning was dead. The queued payload carries ``receipt_identifier`` in
  place of ``secret_key``; a warning queued by the previous version is
  rejected as an invalid message instead of being sent with the dead link.
