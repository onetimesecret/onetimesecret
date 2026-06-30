.. A new scriv changelog fragment.

Security
--------

- Added a Content-Security-Policy violation report receiver at ``POST /api/v1/csp-report`` and pointed the Core web app's report-only CSP at it (``report-uri`` plus a modern ``report-to``/``Reporting-Endpoints`` pair). Previously the report-only policy carried no reporting directive, so browser violation reports went nowhere and report-only mode collected no data. The endpoint is anonymous and public (browsers POST reports unauthenticated and without a CSRF token, which ``/api/*`` already bypasses), reads a size-capped body (≤ 64 KiB), parses both the legacy ``application/csp-report`` and the Reporting API ``application/reports+json`` formats, tolerates malformed input, never touches the database, and always responds ``204 No Content``. Because this is a secret-sharing app, a report's ``document-uri`` / ``blocked-uri`` / ``referrer`` / ``source-file`` can contain a secret link such as ``https://host/secret/<KEY>``; all such URLs are REDACTED (query strings and path collapsed to ``[redacted-path]``, origin only) before anything is logged or forwarded to Sentry, so secret tokens can never leak into logs. (#3498)
