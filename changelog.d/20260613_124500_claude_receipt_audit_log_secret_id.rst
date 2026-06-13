.. A new scriv changelog fragment.

Fixed
-----

- The "Receipt state transition to revealed/burned" audit log lines now
  record the actual secret identifier. Both ``Receipt#revealed!`` and
  ``Receipt#burned!`` cleared ``secret_identifier`` to an empty string before
  building the log payload, so every reveal/burn event was logged with
  ``secret_id: ""`` — defeating the trail for incident review. The identifier
  is now captured before it is cleared (matching ``orphaned!`` and
  ``expired!``), so the log reflects which secret the event refers to.
