Fixed
-----

- Reduced font preloads on server-rendered pages to avoid unnecessary
  downloads and unused-font preload warnings.

- Canonical links now include the page URL, without query parameters,
  instead of an empty ``href``. ``og:url`` and ``twitter:url`` carry the
  same URL, and ``twitter:domain`` names the served host, so pages on a
  custom domain no longer point social scrapers at the install's site.
