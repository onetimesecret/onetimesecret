.. A new scriv changelog fragment.

Added
-----

- Every operator audit event is now emitted as a structured log line on its own
  ``ColonelAudit`` log category at write time, before it is stored (#4334).
  That stream is the durability story — a Valkey outage, an eviction or a trim
  can no longer lose the record — and the capped sorted sets behind the admin
  console are a queryable cache of it. Operators who need retention beyond the
  caps ship that stream.

- An optional syslog destination for the audit stream, filtered to the audit
  category so it carries nothing else: ``LOG_AUDIT_SYSLOG=true`` plus
  ``LOG_AUDIT_SYSLOG_URL`` / ``_LEVEL`` / ``_FACILITY``
  (``audit.syslog`` in the logging config). Default off. A local
  ``syslog://`` destination needs nothing extra; a remote ``tcp://`` /
  ``udp://`` one needs the ``syslog_protocol`` gem added to the Gemfile, and
  without it the appender is skipped with a boot warning rather than failing
  the start.

- Audit export: ``GET /api/colonel/audit/export?format=csv|ndjson`` downloads
  the whole retained trail under the current filters, with Export CSV and
  Export NDJSON buttons on the admin Audit Log screen.

- ``bin/ots audit list`` reads the trail from a shell, with ``--limit``,
  ``--actor``, ``--verb`` and ``--format text|json|csv|ndjson``. Redirect a
  csv/ndjson run to a file for an export without the console.

Security
--------

- The audit API no longer exposes a way to empty the trail. ``trim!`` and
  ``trim_security!`` clamp their arguments so retention can only widen:
  ``trim!(0)``, previously a one-call wipe of the entire operator trail, is now
  a no-op. Shortening retention means changing the configured caps, which is a
  code change under review.
