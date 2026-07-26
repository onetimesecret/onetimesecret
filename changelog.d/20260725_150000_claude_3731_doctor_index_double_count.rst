.. A new scriv changelog fragment.

Fixed
-----

- ``bin/ots domains doctor`` no longer reports every stale
  ``display_domain_index`` entry twice. It ran two byte-identical passes over the
  same index hash with the same predicates, differing only in the severity and
  key they reported under, so N stale entries surfaced as N HIGH findings *and* N
  MEDIUM findings. With ``--repair`` the second pass also re-deleted each field
  and appended a second ``repaired`` record, so the summary and the ``--json``
  report both claimed 2N repairs for N real problems. There is now one check, at
  HIGH severity, reporting under ``display_domain_index_stale`` and repairing
  under ``display_domain_index_cleaned``. The ``display_domain_index_hash_stale``
  finding and the ``display_domain_index_hash_cleaned`` repair action no longer
  exist — anything parsing the ``--json`` report for those keys should read the
  non-``_hash`` ones. The doctor's numbered check list shifts accordingly (the
  org.domains membership check is now #4, orphan reporting #8).

- The colonel entitlement-override endpoints rejected a malformed action with
  "Action must be grant or revoke", which is wrong on ``DELETE
  /api/colonel/organizations/:org_id/entitlements/overrides``: that route carries
  no action parameter and maps to the ``clear`` action, which the operation has
  always accepted. The message is now derived from the operation's ``ACTIONS``
  constant so it cannot drift again, and reads "Action must be one of: grant,
  revoke, clear".

- Four CLI command files (``domains probe``, ``domains repair``, ``org create``,
  ``org transfer-ownership``) included a shared helper module they never
  required, so they only loaded successfully because ``lib/onetime/cli.rb``
  happened to require the helper first. Loaded directly, or after any reordering
  of that manifest, they raised ``NameError`` at class-definition time. Each file
  now requires its own dependencies.
