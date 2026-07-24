.. A new scriv changelog fragment.

Fixed
-----

- Hardened the ``add-msg-issue-prefix`` commit hook (bumped to
  ``v0.1.1-fork``): it no longer mistakes version tokens in branch names for
  issue IDs (``fix/...-v4-...`` stamped ``[#V4]``), no longer double-prefixes
  ``[#I18N]`` commits on reword, and now emits a bare number for ``issue-1234``
  branches. Adds a dedicated ``--tag-pattern`` so tag detection no longer
  depends on the branch-extraction regex. (#3891)
