.. A new scriv changelog fragment.

Added
-----

- Operator audit events are now emitted to the dedicated ``ColonelAudit`` log
  category before storage. Route this category to persistent log collection when
  retention beyond the console's configured caps is required (#4334).

- Added optional syslog delivery for the audit category. Set
  ``LOG_AUDIT_SYSLOG=true`` and configure ``LOG_AUDIT_SYSLOG_URL`` to enable it
  (#4334).

- The Colonel Audit Log can now export its retained, filtered results as CSV or
  NDJSON. ``ots audit list`` provides the same formats for shell workflows
  (#4334).

Security
--------

- Audit retention trimming can no longer empty the operator trail through the
  audit API (#4334).
