.. A new scriv changelog fragment.

Fixed
-----

- The ``add-msg-issue-prefix`` commit hook no longer mistakes version tokens in
  branch names for issue IDs (e.g. ``fix/...-v4-...`` stamped ``[#V4]``).
  Config-only pattern fix. (#3891)
