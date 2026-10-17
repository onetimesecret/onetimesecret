.. A new scriv changelog fragment.

Fixed
-----

- Custom domain lookups reject and log index entries pointing to a record
  stored under a different DNS name, rather than using that record's
  configuration. Existing index drift still needs repair; see the
  `custom domain index runbook
  <docs/runbooks/custom-domain-ascii-index-backfill.md>`__.
- Deleting a custom domain releases its name-index entries using the stored
  name, even when the loaded copy differs, without removing entries owned
  by another record sharing the hostname.
- Fixed a race that could recreate a custom domain record deleted during
  a concurrent save.

Changed
-------

- Domain-removal CLI JSON and Colonel API responses no longer include
  ``reasserts_survivor``.
