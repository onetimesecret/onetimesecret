.. A new scriv changelog fragment.

Changed
-------

- Diagnostics remain disabled under ``RACK_ENV=test`` unless
  ``DIAGNOSTICS_ENABLED_IN_TEST=true``. Playwright-managed servers also disable
  diagnostics unless ``E2E_DIAGNOSTICS_ENABLED=true``.
- ``bin/ots diagnostics sentry doctor`` now accounts for
  ``DIAGNOSTICS_ENABLED_IN_TEST`` under ``RACK_ENV=test``.
