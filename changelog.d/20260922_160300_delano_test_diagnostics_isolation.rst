.. A new scriv changelog fragment.

Changed
-------

- Under ``RACK_ENV=test`` diagnostics (Sentry) stay off unless
  ``DIAGNOSTICS_ENABLED_IN_TEST=true`` is set as well, and the server that
  Playwright starts itself is given ``DIAGNOSTICS_ENABLED=false``
  (``E2E_DIAGNOSTICS_ENABLED=true`` opts back in). A test server booted from
  a developer's shell no longer reports to the Sentry project that shell
  points at. No other environment changes.
