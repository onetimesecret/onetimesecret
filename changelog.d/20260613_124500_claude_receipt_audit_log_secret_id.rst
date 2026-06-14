.. A new scriv changelog fragment.

Fixed
-----

- The "Receipt state transition" audit log lines now record the actual secret
  identifier. ``Receipt#revealed!``, ``Receipt#burned!`` and ``Receipt#expired!``
  cleared ``secret_identifier`` to an empty string before building the log
  payload, so every reveal/burn/expire event was logged with ``secret_id: ""``
  — defeating the trail for incident review. The identifier is now captured
  before it is cleared (matching ``orphaned!``), so the log reflects which
  secret the event refers to.
