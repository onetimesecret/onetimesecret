.. A new scriv changelog fragment.

Added
-----

- ``bin/ots domains backfill-canonical-index`` audits custom domains against
  the custom-domain name index and adds the domains that are missing from it.
  Operators should run it once, with the application stopped: first without
  options to review the report, then with ``--apply``. See
  ``docs/runbooks/custom-domain-canonical-index-backfill.md``. (#4780)
- ``bin/ots domains doctor --all`` reports domains missing from that index
  and names held by more than one domain. (#4780)
