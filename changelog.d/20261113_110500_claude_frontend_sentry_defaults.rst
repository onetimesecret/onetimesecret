.. A new scriv changelog fragment.

Fixed
-----

- The frontend Sentry client now uses ``diagnostics.sentry.defaults``
  (``SENTRY_SAMPLE_RATE``, ``SENTRY_MAX_BREADCRUMBS``, ``SENTRY_LOG_ERRORS``)
  and the same keys under ``diagnostics.sentry.frontend``. Before, it always
  got ``sampleRate`` 1.0, ``maxBreadcrumbs`` 5 and ``logErrors`` true, so it
  sent every error event instead of the configured share (shipped default
  0.10).
