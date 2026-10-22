.. A new scriv changelog fragment.

Fixed
-----

- The "secret about to expire" email now names the secret by its short id
  and links to the owner's recent-secrets page (``/recent``, sign-in
  required) on the canonical host. It linked to ``/secret/`` plus the
  short id, which no route resolves, so every link in every warning was
  dead. The email carries no receipt or secret identifier: both are bearer
  capabilities for the secret. The queued payload is ``recipient``,
  ``secret_shortid`` and ``expires_at``; a warning queued by the previous
  version is rejected as an invalid message instead of being sent with the
  dead link.
