.. A new scriv changelog fragment.

Fixed
-----

- The optional index rebuild maintenance job
  (``jobs.maintenance.index_rebuild``) compared the JSON-encoded values
  stored on customer, organization and custom domain records with the
  plain values their indexes are keyed by. Audit runs reported every entry
  as mismatched and every record as missing. With ``auto_repair`` enabled,
  each run moved the entries of the customer email, organization contact
  email and custom domain name indexes to keys that lookups never read.
  The job now compares decoded values and writes repairs in the same form
  the application does. The job is off by default. If ``auto_repair`` was
  enabled on an earlier version, one repair run of the fixed job moves
  those entries back.
