Fixed
-----

- Browser language detection now works for regional locale variants (e.g.
  ``it-IT``, ``fr-FR``, ``pt-BR``). Previously, 13 of 19 production locales
  failed Accept-Language auto-detection, causing users to see English instead
  of their language. Issue #2668

- Frontend ``navigator.language`` is now read during store initialization, so
  anonymous users on public pages (e.g. secret reveal) get the correct language
  instead of always falling back to English. Issue #2668

Changed
-------

- Promoted 10 locales from ``incomplete`` to fully supported: ar, ca_ES, cs,
  he, hu, pt_PT, ru, sl_SI, vi, zh. Added eo (Esperanto). All 30 locales are
  at 92-94% translation coverage. The ``incomplete`` config section has been
  removed.

- Expanded ``fallback_locale`` chains to cover all regional variants (ca, da,
  el, mi, pt-BR, pt-PT, sl, sv) so related locales degrade gracefully.

Added
-----

- ``Middleware::LocaleFallback`` Rack middleware applies the ``fallback_locale``
  config chains after Otto's initial locale detection. When a user's exact
  regional variant is unavailable, the middleware walks the configured chain to
  find the best available match (e.g. ``fr-CA`` falls back to ``fr_FR`` when
  ``fr_CA`` is not available).

- Regression tests: 29 Vitest tests for frontend locale detection, 79 RSpec
  examples for server-side locale mapping and fallback chain resolution.

AI Assistance
-------------

- Claude assisted with implementing the locale fallback middleware, wiring
  ``navigator.language`` into the frontend store initialization, and writing
  test coverage for both server and frontend locale detection.
