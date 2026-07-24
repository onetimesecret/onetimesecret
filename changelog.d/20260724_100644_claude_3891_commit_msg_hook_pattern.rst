.. A new scriv changelog fragment.

Fixed
-----

- Tightened the ``add-msg-issue-prefix`` commit-message hook so it no longer
  mistakes version and encoding tokens in a branch name for issue IDs. The old
  ``--pattern`` regex made the hyphen optional and was unanchored, so branches
  like ``fix/tailwind-v4-button-cursor`` stamped ``[#V4]``, and ``rel/0.26.2``
  stamped ``[#0]`` — prefixes referencing issues that do not exist. The pattern
  now anchors extraction at a ``/`` or ``#`` boundary and requires a hyphen
  between an alphabetic prefix and the number, so only real issue references
  (``feature/3840-...`` → ``[#3840]``, bare ``NNNN``) are matched. The ``#``
  anchor is deliberate: the same pattern is reused to detect an already-present
  ``[#NNNN]`` tag, so keeping it preserves the guard against double-prefixing on
  reword. Config-only change to ``.pre-commit-config.yaml``. (#3891)
