.. A new scriv changelog fragment.

Changed
-------

- Customer purge commands have been renamed. Update scripts that use them:

  - ``bin/ots customers purge IDENTIFIER`` deletes one account, replacing
    ``purge-one``; the old name is no longer accepted.
  - ``bin/ots customers purge-inactive --older-than DURATION`` replaces the
    bulk ``purge`` command. It previews by default; add ``--purge`` to delete.
    The old ``purge --older-than`` invocation is rejected.

Fixed
-----

- Reduced the time and CPU overhead of single-account customer purges on
  large deployments by avoiding repeated full-record scans during preflight.
